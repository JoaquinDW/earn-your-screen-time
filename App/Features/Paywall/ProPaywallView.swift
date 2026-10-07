import EarnDomain
import SwiftUI

struct ProPaywallView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var source: PaywallSource
    var profile: OnboardingProfile?
    var allowsDismiss: Bool
    var onActivated: (() -> Void)?
    /// For a paywall shown in place rather than presented, where `dismiss` has nothing to close.
    var onClose: (() -> Void)?

    init(
        source: PaywallSource,
        profile: OnboardingProfile? = nil,
        allowsDismiss: Bool = true,
        onActivated: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.source = source
        self.profile = profile
        self.allowsDismiss = allowsDismiss
        self.onActivated = onActivated
        self.onClose = onClose
    }

    var body: some View {
        let savedProfile = env.profile
        let resolvedProfile = profile ?? (savedProfile.isComplete ? savedProfile : nil)
        ProPaywallContent(
            viewModel: PaywallViewModel(
                subscriptionManager: env.subscriptionManager,
                source: source,
                analytics: env.analytics
            ),
            profile: resolvedProfile,
            earnedMinutes: env.earnedMinutesSoFar,
            allowsDismiss: allowsDismiss,
            activated: { onActivated?() ?? dismiss() },
            dismiss: { onClose?() ?? dismiss() }
        )
    }
}

private struct ProPaywallContent: View {
    @Environment(\.locale) private var locale
    @State private var viewModel: PaywallViewModel
    let profile: OnboardingProfile?
    /// Minutes this person has already earned by moving. Once there are any, they are the
    /// paywall's opening line: proof beats promise.
    let earnedMinutes: Int
    let allowsDismiss: Bool
    let activated: () -> Void
    let dismiss: () -> Void

    private var trialPackage: PaywallPackage? {
        guard let package = viewModel.selectedPackage,
              package.freeTrialDescription(locale: locale) != nil else { return nil }
        return package
    }

    init(
        viewModel: PaywallViewModel,
        profile: OnboardingProfile?,
        earnedMinutes: Int,
        allowsDismiss: Bool,
        activated: @escaping () -> Void,
        dismiss: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.profile = profile
        self.earnedMinutes = earnedMinutes
        self.allowsDismiss = allowsDismiss
        self.activated = activated
        self.dismiss = dismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    benefits
                    pricing
                    trialTimeline
                    cancelNudge
                    renewalDisclosure
                    legalLinks
                }
                .padding(.bottom, Theme.Space.l)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Theme.ink)
        .background(Night.ground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                purchaseButton
                purchaseSummary
            }
            .padding(.bottom, Theme.Space.s)
            .background {
                Night.groundDeep
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .task { await viewModel.viewAppeared() }
        .alert(item: $viewModel.alert, content: alert(for:))
    }

    private var header: some View {
        HStack {
            if allowsDismiss {
                Button {
                    viewModel.paywallClosed()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Night.text)
                        .frame(width: Theme.minTouchTarget, height: Theme.minTouchTarget)
                        .background(Night.panel, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close paywall")
            }
            Spacer()
            restoreButton
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.s)
    }

    private var hero: some View {
        VStack(spacing: Theme.Space.m) {
            Group {
                if trialPackage != nil {
                    Text("3-day free trial")
                } else if profile == nil {
                    Text("paywall.eyebrow")
                } else {
                    Text("paywall.plan.eyebrow")
                }
            }
            .eyebrowStyle(Night.textSoft)

            if earnedMinutes > 0 {
                earnedProof
            }

            Group {
                if trialPackage != nil {
                    Text("Try Earnit Pro free for 3 days.")
                } else {
                    Text("Keep your momentum going.")
                }
            }
            .font(.serif(38, relativeTo: .largeTitle))
            .foregroundStyle(Night.text)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Group {
                if trialPackage != nil {
                    Text("No charge today or during your 3-day trial.")
                } else {
                    Text("Go Pro to keep earning and unlocking your chosen apps.")
                }
            }
            .font(.sans(15, weight: .medium))
            .foregroundStyle(Night.textSoft)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.m)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            benefit("lock.iphone", "Keep your chosen apps protected")
            benefit("figure.walk", "Earn more access from your steps")
            benefit("timer", "Use focus sessions and see your progress")
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Night.panel, in: .rect(cornerRadius: Night.panelRadius))
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.l)
    }

    private func benefit(_ symbol: String, _ title: LocalizedStringKey) -> some View {
        Label {
            Text(title)
                .font(.sans(14, weight: .semibold))
                .foregroundStyle(Night.text)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Night.cobaltText)
                .frame(width: 25)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var trialTimeline: some View {
        if let package = trialPackage {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                timelineRow("Today", detail: "No charge during your trial", price: package.zeroPrice)
                Rectangle()
                    .fill(Night.edge)
                    .frame(height: 1)
                    .padding(.leading, 26)
                    .accessibilityHidden(true)
                timelineRow("After 3 days", detail: "Subscription begins unless you cancel", price: "\(package.price) \(billingPeriod(for: package))")
            }
            .padding(Theme.Space.m)
            .background(Night.cobaltWash, in: .rect(cornerRadius: Night.panelRadius))
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, Theme.Space.l)
        }
    }

    private func timelineRow(_ title: LocalizedStringKey, detail: LocalizedStringKey, price: String) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(Night.cobaltText)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sans(14, weight: .bold))
                    .foregroundStyle(Night.text)
                Text(detail)
                    .font(.sans(12))
                    .foregroundStyle(Night.textSoft)
            }
            Spacer(minLength: Theme.Space.s)
            Text(verbatim: price)
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(Night.text)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var earnedProof: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text("\(earnedMinutes) min")
                .font(.serif(24))
                .monospacedDigit()
                .foregroundStyle(Night.cobaltText)
            Text("earned so far")
                .font(.sans(14, weight: .semibold))
                .foregroundStyle(Night.textSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(Night.panel, in: .rect(cornerRadius: Night.panelRadius))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var cancelNudge: some View {
        if viewModel.showsCancelNudge, trialPackage != nil {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("No charge today or during your 3-day trial.")
                    .font(.sans(16, weight: .bold))
                    .foregroundStyle(Night.text)
                Text("Cancel in App Store settings at least 24 hours before the trial ends.")
                    .font(.sans(14))
                    .foregroundStyle(Night.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.m)
            .background(Night.cobaltWash, in: .rect(cornerRadius: Night.panelRadius))
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, Theme.Space.m)
            .accessibilityElement(children: .combine)
        }
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
                ForEach(viewModel.packages.sorted { $0.plan == .yearly && $1.plan != .yearly }) { package in
                    PlanRow(
                        package: package,
                        isSelected: viewModel.selectedPackage?.plan == package.plan,
                        action: { viewModel.selectPackage(package) }
                    )
                }
            }
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.m)
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
        .accessibilityHint(
            trialPackage == nil
                ? Text("Purchases the selected subscription through the App Store")
                : Text("Starts a 3-day free trial through the App Store. No charge until the trial ends.")
        )
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.s)
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
    private var purchaseSummary: some View {
        if let package = viewModel.selectedPackage {
            VStack(spacing: 3) {
                if trialPackage != nil {
                    Text("No charge today or during your 3-day trial.")
                        .font(.sans(14, weight: .bold))
                        .foregroundStyle(Night.cobaltText)
                    Text("After 3 days: \(package.price) \(billingPeriod(for: package)) unless you cancel at least 24 hours before the trial ends.")
                        .font(.sans(12, weight: .medium))
                        .foregroundStyle(Night.textSoft)
                } else {
                    Text("\(package.price) \(billingPeriod(for: package)).")
                        + Text(verbatim: " ")
                        + Text("Renews automatically.")
                }
            }
            .font(.sans(13, weight: .medium))
            .foregroundStyle(Night.textSoft)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, Theme.Space.s)
        }
    }

    private var renewalDisclosure: some View {
        Text("Subscription renews automatically unless canceled at least 24 hours before the end of the current period. Manage or cancel in App Store settings.")
            .font(.sans(11.5))
            .foregroundStyle(Night.textMuted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, Theme.Space.s)
    }

    private func billingPeriod(for package: PaywallPackage) -> String {
        switch package.plan {
        case .monthly: PaywallPackage.localized("per month", locale: locale)
        case .yearly: PaywallPackage.localized("per year", locale: locale)
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
    }

    private var restoreButton: some View {
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
        case .monthly: PaywallPackage.localized("Monthly", locale: locale)
        case .yearly: PaywallPackage.localized("Yearly", locale: locale)
        }
    }

    private var period: String {
        switch package.plan {
        case .monthly: PaywallPackage.localized("per month", locale: locale)
        case .yearly: PaywallPackage.localized("per year", locale: locale)
        }
    }

    private var accessibilityLabel: String {
        let offer = package.freeTrialDescription(locale: locale).map { ", \($0)" } ?? ""
        return "\(title), \(package.price), \(period)\(offer)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack(spacing: Theme.Space.s) {
                        Text(title)
                            .font(.sans(18, weight: .semibold))
                    }
                    if package.freeTrialDescription(locale: locale) != nil {
                        Text("3-day free trial")
                            .font(.sans(12, weight: .semibold))
                            .foregroundStyle(Night.cobaltText)
                    }
                }
                Spacer(minLength: Theme.Space.s)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(package.price)
                        .font(.serif(24, relativeTo: .title3))
                        .foregroundStyle(isSelected ? Night.text : Night.textSoft)
                        .monospacedDigit()
                    Text(period)
                        .font(.sans(12))
                        .foregroundStyle(Theme.muted)
                    if let monthlyEquivalent = package.monthlyEquivalentPrice() {
                        HStack(spacing: Theme.Space.xs) {
                            Text(verbatim: monthlyEquivalent)
                            Text("per month")
                        }
                        .font(.sans(11.5, weight: .semibold))
                        .foregroundStyle(Night.cobaltText)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isSelected ? Night.cobaltText : Night.textFaint)
                    .accessibilityHidden(true)
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

private struct OutcomeComparison: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let profile: OnboardingProfile?

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.Space.s))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: -Theme.Space.l))

        VStack(spacing: Theme.Space.m) {
            layout {
                if let profile {
                    OutcomeCard(
                        eyebrow: Text("Your usual day"),
                        value: profile.currentDailySteps.formatted(),
                        unit: Text("steps"),
                        detail: nil,
                        isHighlighted: false
                    )
                    OutcomeCard(
                        eyebrow: Text("Daily movement goal"),
                        value: profile.dailyStepGoal.formatted(),
                        unit: Text("steps"),
                        detail: goalDifference(for: profile),
                        isHighlighted: true
                    )
                    .offset(y: dynamicTypeSize.isAccessibilitySize ? 0 : Theme.Space.l)
                    .zIndex(1)
                } else {
                    OutcomeCard(
                        eyebrow: Text("Move"),
                        value: "500",
                        unit: Text("steps"),
                        detail: nil,
                        isHighlighted: false
                    )
                    OutcomeCard(
                        eyebrow: Text("Earn"),
                        value: "5",
                        unit: Text("minutes"),
                        detail: nil,
                        isHighlighted: true
                    )
                    .offset(y: dynamicTypeSize.isAccessibilitySize ? 0 : Theme.Space.l)
                    .zIndex(1)
                }
            }
            .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 0 : Theme.Space.l)

            if let profile, let scrolling = profile.scrolling {
                ScreenTimeComparison(profile: profile, scrolling: scrolling)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func goalDifference(for profile: OnboardingProfile) -> Text? {
        let difference = max(0, profile.dailyStepGoal - profile.currentDailySteps)
        guard difference > 0 else { return nil }
        return Text(verbatim: "+") + Text("\(difference.formatted()) steps/day")
    }
}

private struct ScreenTimeComparison: View {
    let profile: OnboardingProfile
    let scrolling: OnboardingProfile.ScrollingBand

    private var dailyEarnedMinutes: Int {
        Projection(
            profile: profile,
            rule: EarningRule(source: .steps, amountRequired: 500, rewardSeconds: 300),
            days: 1
        ).earnedMinutes
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            metric(value: Text(scrolling.label), caption: Text("Usual scrolling"), alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Night.cobaltText)
                .accessibilityHidden(true)

            metric(
                value: Text("common.minutesValue \(dailyEarnedMinutes)"),
                caption: Text("Screen time earned at your goal"),
                alignment: .trailing
            )
        }
        .padding(Theme.Space.m)
        .background(Night.panel.opacity(0.55), in: .rect(cornerRadius: Theme.cornerRadius))
        .accessibilityElement(children: .contain)
    }

    private func metric(value: Text, caption: Text, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: Theme.Space.xs) {
            value
                .font(.sans(17, weight: .semibold))
                .foregroundStyle(Night.text)
            caption
                .font(.sans(11.5, weight: .medium))
                .foregroundStyle(Night.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        .accessibilityElement(children: .combine)
    }
}

private struct OutcomeCard: View {
    let eyebrow: Text
    let value: String
    let unit: Text
    let detail: Text?
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            eyebrow
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(isHighlighted ? Night.cobaltText : Night.textMuted)
            Text(verbatim: value)
                .font(.serif(34, relativeTo: .title))
                .foregroundStyle(Night.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            unit
                .font(.sans(12, weight: .medium))
                .foregroundStyle(Night.textSoft)
            Group {
                if let detail {
                    detail
                } else {
                    Text(verbatim: " ")
                }
            }
            .font(.sans(11.5, weight: .semibold))
            .foregroundStyle(Night.cobaltText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.m)
        .background(
            isHighlighted ? Night.panel : Night.forestLift,
            in: .rect(cornerRadius: Theme.cornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(isHighlighted ? Night.cobalt.opacity(0.7) : Night.edge)
        }
        .shadow(color: Night.groundDeep.opacity(0.45), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
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
