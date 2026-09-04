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
            viewModel: PaywallViewModel(
                subscriptionManager: env.subscriptionManager,
                analytics: env.analytics
            ),
            profile: profile,
            restrictedItemCount: env.state.restrictedItemCount,
            allowsDismiss: allowsDismiss,
            activated: { onActivated?() ?? dismiss() },
            dismiss: { dismiss() }
        )
    }
}

private struct ProPaywallContent: View {
    @Environment(\.locale) private var locale
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
                    hero
                    if let profile {
                        personalizedPlan(profile)
                    } else {
                        benefits
                    }
                    pricing
                    subscriptionTerms
                    purchaseButton
                    legalLinks
                }
                .padding(.bottom, Theme.Space.l)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)

            if allowsDismiss {
                Button {
                    viewModel.paywallClosed()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Night.text)
                        .frame(width: Theme.minTouchTarget, height: Theme.minTouchTarget)
                        .background(.ultraThinMaterial, in: .circle)
                        .background(Night.groundDeep.opacity(0.5), in: .circle)
                        .environment(\.colorScheme, .dark)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close paywall")
                .padding(.top, Theme.Space.l)
                .padding(.trailing, Theme.Space.l)
            }
        }
        .foregroundStyle(Theme.ink)
        .background(Night.ground.ignoresSafeArea())
        .task { await viewModel.viewAppeared() }
        .alert(item: $viewModel.alert, content: alert(for:))
    }

    /// The one emotional beat on a screen that otherwise has to be commercially plain.
    ///
    /// The artwork's sky is enormous and empty, so the headline sets straight into it and the
    /// prices below stay on solid ground where nothing competes with them. The share is
    /// deliberately under half the screen: the brief is that the illustration must never push
    /// the price out of the first scroll.
    private var hero: some View {
        SceneHero(scene: .freedomRidge, share: 0.42) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if profile == nil {
                    Text("paywall.eyebrow").eyebrowStyle(Night.textSoft)
                    Text("paywall.headline")
                        .font(.serif(40, relativeTo: .largeTitle))
                        .foregroundStyle(Night.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("paywall.subtitle")
                        .font(.sans(16))
                        .foregroundStyle(Night.textSoft)
                } else {
                    Text("paywall.plan.eyebrow").eyebrowStyle(Night.textSoft)
                    Text("paywall.plan.headline")
                        .font(.serif(40, relativeTo: .largeTitle))
                        .foregroundStyle(Night.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("paywall.plan.subtitle")
                        .font(.sans(16))
                        .foregroundStyle(Night.textSoft)
                }
            }
        }
    }

    private func personalizedPlan(_ profile: OnboardingProfile) -> some View {
        let projection = Projection(profile: profile)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("YOUR PLAN").eyebrowStyle()
            paywallPlanRow(
                icon: "figure.walk",
                text: Text("\(profile.dailyStepGoal.formatted(.number.locale(locale))) steps/day")
            )
            paywallPlanRow(icon: "timer", text: Text("5 min / 500 steps"))
            paywallPlanRow(icon: "apps.iphone", text: Text("\(restrictedItemCount) selected items"))
            paywallPlanRow(
                icon: "target",
                text: Text("\(projection.totalSteps.formatted(.number.locale(locale)))-step 30-day goal")
            )
        }
        .padding(Theme.Space.m)
        .background(Night.panel, in: .rect(cornerRadius: Theme.cornerRadius))
        .overlay { RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Night.edge) }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.l)
    }

    private func paywallPlanRow(icon: String, text: Text) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: icon).foregroundStyle(Night.cobaltText).frame(width: 24)
            text.font(.sans(15, weight: .semibold))
        }
        .accessibilityElement(children: .combine)
    }

    private var benefits: some View {
        VStack(spacing: 0) {
            benefit("Protect the apps that take your time")
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
            Image(systemName: "checkmark")
                .font(.sans(14, weight: .semibold))
                .foregroundStyle(Night.moss)
                .frame(width: 20)
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

                    // Sandbox/TestFlight only: names the actual configuration fault instead
                    // of leaving an unreproducible "try again" loop.
                    if let diagnostic = viewModel.loadDiagnostic {
                        Text(verbatim: diagnostic)
                            .font(.sans(12))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .padding(.top, Theme.Space.s)
                    }
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
                    ProgressView().tint(Color.white)
                }
                purchaseButtonTitle
            }
        }
        .buttonStyle(.pill)
        .disabled(!viewModel.canPurchase)
        .accessibilityHint("Purchases the selected subscription through the App Store")
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.l)
    }

    private var purchaseButtonTitle: Text {
        if viewModel.isPurchasing { return Text("Processing purchase") }
        guard let package = viewModel.selectedPackage else {
            return Text("Choose a subscription")
        }
        if package.freeTrialDescription(locale: locale) != nil {
            return Text("Start My 3-Day Free Trial")
        }
        return Text("Subscribe for \(package.price) \(billingPeriod(for: package))")
    }

    @ViewBuilder
    private var subscriptionTerms: some View {
        if let package = viewModel.selectedPackage {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if let trial = package.freeTrialDescription(locale: locale) {
                    Text("\(trial). Then \(package.price) \(billingPeriod(for: package)).")
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                } else {
                    Text("\(package.price) \(billingPeriod(for: package)).")
                        .font(.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }

                Text("Your subscription automatically renews for \(package.price) \(billingPeriod(for: package)) unless canceled at least 24 hours before the end of the current period. Manage or cancel anytime in App Store settings.")
                    .font(.sans(13))
                    .foregroundStyle(Theme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.m)
            .background(Night.panel.opacity(0.55), in: .rect(cornerRadius: Theme.cornerRadius))
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, Theme.Space.m)
            .accessibilityElement(children: .combine)
        }
    }

    private func billingPeriod(for package: PaywallPackage) -> String {
        switch package.plan {
        case .monthly: String(localized: "per month", locale: locale)
        case .yearly: String(localized: "per year", locale: locale)
        }
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
                if viewModel.isRestoring {
                    Text("Restoring")
                } else {
                    Text("Restore Purchases")
                }
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
        case .entitlementInactive:
            Alert(
                title: Text("Your membership wasn't activated"),
                message: Text("The purchase completed, but subscription access could not be verified. Try restoring purchases. If this continues, contact support."),
                primaryButton: .default(Text("Restore Purchases")) {
                    Task {
                        if await viewModel.restorePurchases() { activated() }
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
                message: Text("We couldn't find an active subscription for this Apple Account."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

private struct PlanRow: View {
    @Environment(\.locale) private var locale
    let package: PaywallPackage
    let isSelected: Bool
    let action: () -> Void

    private var title: String {
        switch package.plan {
        case .monthly: String(localized: "Monthly", locale: locale)
        case .yearly: String(localized: "Yearly", locale: locale)
        }
    }

    private var period: String {
        switch package.plan {
        case .monthly: String(localized: "per month", locale: locale)
        case .yearly: String(localized: "per year", locale: locale)
        }
    }

    private var accessibilityLabel: String {
        let offer = package.freeTrialDescription(locale: locale).map { ", \($0)" } ?? ""
        return "\(title), \(package.price), \(period)\(offer)"
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
                                .foregroundStyle(Night.cobaltText)
                                .padding(.horizontal, Theme.Space.s)
                                .padding(.vertical, Theme.Space.xs)
                                .background(Night.cobaltWash, in: .capsule)
                        }
                    }
                    Text(period)
                        .font(.sans(13))
                        .foregroundStyle(Theme.muted)
                    if let trial = package.freeTrialDescription(locale: locale) {
                        Text(trial)
                            .font(.sans(12.5, weight: .semibold))
                            .foregroundStyle(Night.moss)
                    }
                }
                Spacer(minLength: Theme.Space.s)
                Text(package.price)
                    .font(.serif(26, relativeTo: .title3))
                    .foregroundStyle(isSelected ? Night.text : Night.textSoft)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: 76)
            .background(
                isSelected ? Night.panel : Night.panel.opacity(0.45),
                in: .rect(cornerRadius: Theme.cornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(isSelected ? Night.cobalt : Night.edge, lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct PlanSkeleton: View {
    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Circle()
                .fill(Night.text.opacity(0.1))
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Capsule().fill(Night.text.opacity(0.1)).frame(width: 92, height: 14)
                Capsule().fill(Night.text.opacity(0.1)).frame(width: 64, height: 10)
            }
            Spacer()
            Capsule().fill(Night.text.opacity(0.1)).frame(width: 72, height: 18)
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(minHeight: 76)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Night.edge, lineWidth: 1)
        }
        .accessibilityElement()
        .accessibilityLabel("Loading subscription option")
    }
}
