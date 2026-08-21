import EarnDomain
import SwiftUI

struct ProPaywallView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var profile: OnboardingProfile?
    var allowsDismiss: Bool
    var onActivated: (() -> Void)?

    init(
        profile: OnboardingProfile? = nil,
        allowsDismiss: Bool = true,
        onActivated: (() -> Void)? = nil
    ) {
        self.profile = profile
        self.allowsDismiss = allowsDismiss
        self.onActivated = onActivated
    }

    var body: some View {
        ProPaywallContent(
            viewModel: PaywallViewModel(subscriptionManager: env.subscriptionManager),
            profile: profile,
            restrictedItemCount: env.state.restrictedItemCount,
            allowsDismiss: allowsDismiss,
            activated: { onActivated?() ?? dismiss() },
            dismiss: { dismiss() }
        )
    }
}

private struct ProPaywallContent: View {
    @State private var viewModel: PaywallViewModel
    let profile: OnboardingProfile?
    let restrictedItemCount: Int
    let allowsDismiss: Bool
    let activated: () -> Void
    let dismiss: () -> Void

    init(
        viewModel: PaywallViewModel,
        profile: OnboardingProfile?,
        restrictedItemCount: Int,
        allowsDismiss: Bool,
        activated: @escaping () -> Void,
        dismiss: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.profile = profile
        self.restrictedItemCount = restrictedItemCount
        self.allowsDismiss = allowsDismiss
        self.activated = activated
        self.dismiss = dismiss
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TrailView(progress: 0.72, cornerRadius: Theme.sheetRadius)
                        .frame(height: 176)
                        .padding(.horizontal, Theme.Space.m)

                    hero
                    if let profile {
                        personalizedPlan(profile)
                    } else {
                        benefits
                    }
                    pricing
                    purchaseButton
                    legalLinks
                }
                .padding(.top, Theme.Space.m)
                .padding(.bottom, Theme.Space.l)
            }
            .scrollIndicators(.hidden)

            if allowsDismiss {
                Button {
                    viewModel.paywallClosed()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: Theme.minTouchTarget, height: Theme.minTouchTarget)
                        .background(Theme.paper.opacity(0.92), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close paywall")
                .padding(.top, Theme.Space.l)
                .padding(.trailing, Theme.Space.l)
            }
        }
        .foregroundStyle(Theme.ink)
        .paperBackground()
        .task { await viewModel.viewAppeared() }
        .alert(item: $viewModel.alert, content: alert(for:))
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(profile == nil ? "EARN PRO" : "YOUR PLAN IS READY")
                .eyebrowStyle(Theme.coralDeep)
            Text(profile == nil ? "Make your scrolling\ncost something." : "Start your 30-day change.")
                .font(.serif(42, relativeTo: .largeTitle))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(profile == nil ? "Walk more. Scroll less. Feel better." : "Your personalized Earn plan is ready.")
                .font(.sans(17))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.l)
    }

    private func personalizedPlan(_ profile: OnboardingProfile) -> some View {
        let projection = Projection(profile: profile)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("YOUR PLAN").eyebrowStyle()
            paywallPlanRow(icon: "figure.walk", text: "\(profile.dailyStepGoal.formatted()) steps/day")
            paywallPlanRow(icon: "timer", text: "5 min / 1,000 steps")
            paywallPlanRow(icon: "apps.iphone", text: "\(restrictedItemCount) selected items")
            paywallPlanRow(icon: "target", text: "\(projection.totalSteps.formatted())-step 30-day goal")
        }
        .padding(Theme.Space.m)
        .background(Theme.paper, in: .rect(cornerRadius: Theme.cornerRadius))
        .overlay { RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.line) }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.l)
    }

    private func paywallPlanRow(icon: String, text: String) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: icon).foregroundStyle(Theme.coralDeep).frame(width: 24)
            Text(text).font(.sans(15, weight: .semibold))
        }
        .accessibilityElement(children: .combine)
    }

    private var benefits: some View {
        VStack(spacing: 0) {
            benefit("Unlimited blocked apps")
            Hairline()
            benefit("Earn screen time from your steps")
            Hairline()
            benefit("Custom earning rules")
            Hairline()
            benefit("Progress insights")
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.l)
    }

    private func benefit(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.sageDeep)
                .accessibilityHidden(true)
            Text(title)
                .font(.sans(16, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 52)
    }

    @ViewBuilder
    private var pricing: some View {
        VStack(spacing: Theme.Space.s) {
            if viewModel.isLoading {
                PlanSkeleton()
                PlanSkeleton()
            } else if viewModel.loadFailed {
                VStack(spacing: Theme.Space.m) {
                    Text("Unable to load subscription options.")
                        .font(.sans(17, weight: .semibold))
                    Text("Please try again.")
                        .font(.sans(15))
                        .foregroundStyle(Theme.muted)
                    Button("Retry") {
                        Task { await viewModel.loadOffering() }
                    }
                    .buttonStyle(.quietLink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.l)
                .accessibilityElement(children: .combine)
            } else {
                ForEach(viewModel.packages) { package in
                    PlanRow(
                        package: package,
                        isSelected: viewModel.selectedPackage?.plan == package.plan,
                        action: { viewModel.selectPackage(package) }
                    )
                }
            }
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.l)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Subscription plans")
    }

    private var purchaseButton: some View {
        Button {
            Task {
                if await viewModel.purchase() { activated() }
            }
        } label: {
            HStack(spacing: Theme.Space.s) {
                if viewModel.isPurchasing {
                    ProgressView().tint(Theme.paper)
                }
                Text(purchaseButtonTitle)
            }
        }
        .buttonStyle(.pill)
        .disabled(!viewModel.canPurchase)
        .accessibilityHint("Purchases the selected subscription through the App Store")
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.l)
    }

    private var purchaseButtonTitle: String {
        if viewModel.isPurchasing { return "Processing purchase" }
        if let trial = viewModel.selectedPackage?.freeTrialDescription {
            return "Start my \(trial)"
        }
        return profile == nil ? "Start earning your screen time" : "Start my plan"
    }

    private var legalLinks: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.s) { legalItems }
            VStack(spacing: Theme.Space.xs) { legalItems }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Space.m)
        .padding(.top, Theme.Space.m)
    }

    @ViewBuilder
    private var legalItems: some View {
        if let url = AppConfiguration.termsOfUseURL {
            Link("Terms of Use", destination: url)
                .buttonStyle(.quietLink)
        }
        if AppConfiguration.termsOfUseURL != nil,
           AppConfiguration.privacyPolicyURL != nil {
            Text("·").foregroundStyle(Theme.muted).accessibilityHidden(true)
        }
        if let url = AppConfiguration.privacyPolicyURL {
            Link("Privacy Policy", destination: url)
                .buttonStyle(.quietLink)
        }
        if AppConfiguration.termsOfUseURL != nil || AppConfiguration.privacyPolicyURL != nil {
            Text("·").foregroundStyle(Theme.muted).accessibilityHidden(true)
        }
        Button {
            Task {
                if await viewModel.restorePurchases() { activated() }
            }
        } label: {
            HStack(spacing: Theme.Space.xs) {
                if viewModel.isRestoring { ProgressView().controlSize(.small) }
                Text(viewModel.isRestoring ? "Restoring" : "Restore Purchases")
            }
        }
        .buttonStyle(.quietLink)
        .disabled(viewModel.isProcessing)
    }

    private func alert(for alert: PaywallAlert) -> Alert {
        switch alert.kind {
        case .purchase:
            Alert(
                title: Text("Couldn't complete purchase"),
                message: Text("Something went wrong while processing your subscription. Please try again."),
                primaryButton: .default(Text("Try again")) {
                    Task {
                        if await viewModel.purchase() { activated() }
                    }
                },
                secondaryButton: .cancel()
            )
        case .restore:
            Alert(
                title: Text("Couldn't restore purchases"),
                message: Text("Something went wrong while restoring your subscription. Please try again."),
                primaryButton: .default(Text("Try again")) {
                    Task {
                        if await viewModel.restorePurchases() { activated() }
                    }
                },
                secondaryButton: .cancel()
            )
        case .noSubscription:
            Alert(
                title: Text("No subscription found"),
                message: Text("We couldn't find an active Pro subscription for this Apple Account."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

private struct PlanRow: View {
    let package: PaywallPackage
    let isSelected: Bool
    let action: () -> Void

    private var title: String {
        switch package.plan {
        case .monthly: String(localized: "Monthly")
        case .yearly: String(localized: "Yearly")
        }
    }

    private var period: String {
        switch package.plan {
        case .monthly: String(localized: "per month")
        case .yearly: String(localized: "per year")
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m) {
                SelectionDot(isSelected: isSelected)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack(spacing: Theme.Space.s) {
                        Text(title)
                            .font(.sans(17, weight: .semibold))
                        if package.plan == .yearly {
                            Text("Best value")
                                .font(.sans(11, weight: .bold))
                                .foregroundStyle(Theme.coralDeep)
                                .padding(.horizontal, Theme.Space.s)
                                .padding(.vertical, Theme.Space.xs)
                                .background(Theme.coralLight, in: .capsule)
                        }
                    }
                    Text(period)
                        .font(.sans(13))
                        .foregroundStyle(Theme.muted)
                    if let trial = package.freeTrialDescription {
                        Text(trial)
                            .font(.sans(12.5, weight: .semibold))
                            .foregroundStyle(Theme.sageDeep)
                    }
                }
                Spacer(minLength: Theme.Space.s)
                Text(package.price)
                    .font(.serif(24, relativeTo: .title3))
                    .foregroundStyle(isSelected ? Theme.coralDeep : Theme.ink)
                    .monospacedDigit()
            }
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: 76)
            .background(isSelected ? Theme.paper : Theme.background, in: .rect(cornerRadius: Theme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(isSelected ? Theme.coralDeep : Theme.line, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(package.price), \(period)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct PlanSkeleton: View {
    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Circle()
                .fill(Theme.line)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Capsule().fill(Theme.line).frame(width: 92, height: 14)
                Capsule().fill(Theme.line).frame(width: 64, height: 10)
            }
            Spacer()
            Capsule().fill(Theme.line).frame(width: 72, height: 18)
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(minHeight: 76)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.line, lineWidth: 1)
        }
        .accessibilityElement()
        .accessibilityLabel("Loading subscription option")
    }
}
