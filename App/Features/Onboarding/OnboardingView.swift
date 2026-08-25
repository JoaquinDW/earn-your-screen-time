import EarnDomain
import SwiftUI

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("onboarding.route.v3", store: AppGroup.defaults) private var storedRoute = Route.hook.rawValue

    @State private var profile = OnboardingProfile()
    @State private var isMovingBack = false
    @State private var isLoadingHealth = false
    @State private var isActivating = false
    @State private var healthMessage: String?

    private var route: Route { Route(rawValue: storedRoute) ?? .hook }

    var body: some View {
        ZStack {
            PaperBackground()
            content
                .id(route)
                .transition(reduceMotion ? .opacity : .push(from: isMovingBack ? .leading : .trailing))
        }
        .foregroundStyle(Theme.ink)
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: route)
        .onAppear {
            profile = env.profile
            env.analytics.track(.onboardingStarted)
        }
        .onChange(of: profile) { _, updated in env.saveProfile(updated) }
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .hook:
            OnboardingHookStep(onContinue: advance)
        case .scrolling:
            adaptiveLayout("A LITTLE ABOUT YOU", "How much time do you think you spend scrolling each day?", back: goBack) {
                choices(OnboardingProfile.ScrollingBand.allCases, selected: profile.scrolling) { value in
                    profile.scrolling = value
                } label: { $0.label }
                if let scrolling = profile.scrolling {
                    contextualScrollingCopy(scrolling)
                        .padding(.top, Theme.Space.m)
                }
            } action: {
                continueButton(disabled: profile.scrolling == nil) {
                    if let scrolling = profile.scrolling {
                        env.analytics.track(.screenTimeEstimateSelected.withProperties([
                            "screen_time_bucket": .string(scrolling.rawValue)
                        ]))
                    }
                    advance()
                }
            }
        case .intent:
            adaptiveLayout("YOUR INTENTION", "What would you like to change?", back: goBack) {
                choices(UserPrimaryGoal.allCases, selected: profile.primaryGoal) { value in
                    profile.primaryGoal = value
                    profile.desiredOutcomes = [value.desiredOutcome]
                } label: { $0.label }
            } action: {
                continueButton(disabled: profile.primaryGoal == nil) {
                    if let goal = profile.primaryGoal {
                        env.analytics.track(.primaryGoalSelected.withProperties(["primary_goal": .string(goal.rawValue)]))
                    }
                    advance()
                }
            }
        case .health:
            healthStep
        case .manualBaseline:
            adaptiveLayout("YOUR STARTING POINT", "About how much do you usually walk?", back: goBack) {
                Text("An estimate is enough. You can adjust your plan later.")
                    .font(.sans(15))
                    .foregroundStyle(Theme.muted)
                    .padding(.bottom, Theme.Space.m)
                choices(ManualBaseline.allCases, selected: manualSelection) { value in
                    applyBaseline(value.steps, source: .selfReported)
                } label: { $0.label }
            } action: {
                continueButton(disabled: profile.baselineSource != .selfReported) {
                    env.analytics.track(.baselineSelfReported.withProperties([
                        "baseline_steps": .int(profile.baselineDailySteps ?? 0)
                    ]))
                    go(to: .baselineResult)
                }
            }
        case .baselineResult:
            adaptiveLayout("YOUR BASELINE", "You're averaging \((profile.baselineDailySteps ?? 0).formatted()) steps/day.", back: goBack) {
                GuardianMark()
                    .frame(width: 72, height: 72)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Space.xl)
                Text("We'll start from there.")
                    .font(.serif(27))
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("No judgment. Just a realistic place to begin.")
                    .font(.sans(15))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, Theme.Space.s)
            } action: { continueButton(action: advance) }
        case .progressiveGoal:
            progressiveGoalStep
        case .apps:
            AppsStep(onContinue: advance, onBack: goBack)
        case .plan:
            starterPlanStep
        case .customize:
            customizeStep
        case .projection:
            projectionStep
        case .paywall:
            OnboardingPaywallStep(profile: profile, onActivated: advance)
        case .mission:
            missionStep
        }
    }

    private var healthStep: some View {
        adaptiveLayout("A GOAL THAT FITS", "Let's see where you're starting from.", back: goBack) {
            Text("Earnit uses your walking activity to create a goal that actually fits you.")
                .font(.sans(16))
                .foregroundStyle(Theme.muted)
                .padding(.top, Theme.Space.s)
            VStack(spacing: Theme.Space.m) {
                permissionRow("heart.fill", "Apple Health", Theme.coralDeep)
                Image(systemName: "arrow.down").foregroundStyle(Theme.muted).accessibilityHidden(true)
                permissionRow("target", "Your personal baseline", Theme.cobaltDeep)
            }
            .padding(.vertical, Theme.Space.xl)
            Text("Your health history stays on your device. Earnit only keeps the baseline used for your plan.")
                .font(.sans(13.5))
                .foregroundStyle(Theme.muted)
            if let healthMessage {
                Text(healthMessage)
                    .font(.sans(13.5, weight: .semibold))
                    .foregroundStyle(Theme.coralDeep)
                    .padding(.top, Theme.Space.m)
            }
        } action: {
            Button(action: connectHealth) {
                HStack {
                    if isLoadingHealth { ProgressView().tint(Theme.paper) }
                    Text(isLoadingHealth ? "Checking your activity" : "Connect Apple Health")
                }
            }
            .buttonStyle(.pill)
            .disabled(isLoadingHealth)
            Button("Use an estimate instead") { go(to: .manualBaseline) }
                .buttonStyle(.quiet)
        }
    }

    private var progressiveGoalStep: some View {
        let baseline = profile.baselineDailySteps ?? 0
        let goal = profile.dailyStepGoal
        return adaptiveLayout("SMALL STEPS, REAL PROGRESS", "No 10,000-step goals overnight.", back: goBack) {
            GuardianPanel(progress: GuardianState.awakening.anchor, height: 170, cornerRadius: Theme.cornerRadius)
                .padding(.vertical, Theme.Space.l)
            Text("You're averaging about \(baseline.formatted()) steps/day.")
                .font(.sans(17, weight: .semibold))
            Text("We'll start with \(goal.formatted()) and suggest small changes only when you're ready.")
                .font(.serif(27))
                .padding(.top, Theme.Space.s)
            Text("Small changes are easier to stick with. You always choose whether your goal changes.")
                .font(.sans(15))
                .foregroundStyle(Theme.muted)
                .padding(.top, Theme.Space.m)
        } action: { Button("Sounds good", action: advance).buttonStyle(.pill) }
    }

    private var starterPlanStep: some View {
        adaptiveLayout("YOUR PLAN IS READY", "Your starter plan", back: goBack) {
            GuardianPanel(progress: GuardianState.rising.anchor, height: 160, cornerRadius: Theme.cornerRadius)
                .padding(.vertical, Theme.Space.m)
            planRow("target", "Daily movement goal", "\(profile.dailyStepGoal.formatted()) steps")
            planRow("figure.walk", "Earn rate", "500 steps → 5 min")
            planRow("apps.iphone", "Protected apps", "\(env.state.restrictedItemCount) selected")
            planRow("sparkles", "Goal reward", "+10 bonus min")
        } action: {
            Button("Start my plan") {
                env.analytics.track(.starterPlanAccepted.withProperties([
                    "selected_goal": .int(profile.dailyStepGoal),
                    "earn_rate": .string("500:5")
                ]))
                advance()
            }
            .buttonStyle(.pill)
            Button("Customize") {
                env.analytics.track(.starterPlanCustomized)
                go(to: .customize)
            }
            .buttonStyle(.quiet)
        }
        .onAppear { env.analytics.track(.starterPlanViewed) }
    }

    private var customizeStep: some View {
        adaptiveLayout("MAKE IT YOURS", "Adjust your daily goal", back: { go(to: .plan, movingBack: true) }) {
            Text("Your goal and earn rate are separate. Start with our recommended earn rate and change it later from Settings.")
                .font(.sans(15))
                .foregroundStyle(Theme.muted)
            Stepper(value: goalBinding, in: 2_000...20_000, step: 500) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily movement goal").font(.sans(14, weight: .semibold)).foregroundStyle(Theme.muted)
                    Text("\(profile.dailyStepGoal.formatted()) steps").font(.serif(30)).monospacedDigit()
                }
            }
            .padding(Theme.Space.m)
            .background(Theme.paper, in: .rect(cornerRadius: Theme.cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.line) }
            .padding(.top, Theme.Space.l)
            planRow("figure.walk", "Recommended earn rate", "500 steps → 5 min")
                .padding(.top, Theme.Space.s)
        } action: {
            Button("Save plan") { go(to: .projection) }.buttonStyle(.pill)
        }
    }

    private var projectionStep: some View {
        let projection = Projection(
            currentDailySteps: profile.baselineDailySteps ?? 0,
            goalDailySteps: profile.dailyStepGoal,
            rule: EarningRule(source: .steps, amountRequired: 500, rewardSeconds: 300)
        )
        return adaptiveLayout("30 DAYS FROM NOW", "Imagine where small walks could take you.", back: goBack) {
            VStack(spacing: 0) {
                projectionRow("plus.forwardslash.minus", "Extra steps", "≈ \(projection.upliftSteps.formatted())")
                Hairline()
                projectionRow("clock", "Extra walking", "≈ \(projection.upliftWalkingMinutes / 60) hours")
            }
            .padding(.horizontal, Theme.Space.m)
            .background(Theme.paper, in: .rect(cornerRadius: Theme.cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.line) }
            .padding(.top, Theme.Space.xl)
            Text("This is simple arithmetic based on your baseline and plan, not a health promise.")
                .font(.sans(13.5))
                .foregroundStyle(Theme.muted)
                .padding(.top, Theme.Space.m)
        } action: { Button("Continue", action: advance).buttonStyle(.pill) }
    }

    private var missionStep: some View {
        adaptiveLayout("YOUR FIRST MISSION", "Your first 5 minutes are 500 steps away.", back: nil) {
            GuardianPanel(progress: GuardianState.awakening.anchor, height: 190, cornerRadius: Theme.cornerRadius)
                .padding(.vertical, Theme.Space.l)
            ProgressView(value: 0, total: 500)
                .tint(Theme.cobalt)
            HStack {
                Text("0 steps")
                Spacer()
                Text("500 steps")
            }
            .font(.sans(13, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .padding(.top, Theme.Space.s)
            Text("Take a short walk. Open Earnit when you return and your first reward will be waiting.")
                .font(.sans(15))
                .foregroundStyle(Theme.muted)
                .padding(.top, Theme.Space.l)
        } action: {
            Button {
                guard !isActivating else { return }
                isActivating = true
                env.analytics.track(.firstEarnStarted)
                Task { await env.activateAdaptivePlan(profile) }
            } label: {
                HStack {
                    if isActivating { ProgressView().tint(Theme.paper) }
                    Text(isActivating ? "Activating your plan" : "Take a short walk")
                }
            }
            .buttonStyle(.pill)
            .disabled(isActivating)
        }
    }

    private func connectHealth() {
        guard !isLoadingHealth else { return }
        isLoadingHealth = true
        healthMessage = nil
        env.analytics.track(.healthKitRequested)
        Task {
            do {
                guard env.health.isAvailable else { throw HealthKitError.unavailable }
                if !env.health.hasRequestedAuthorization { try await env.health.requestAuthorization() }
                let result = try await env.health.recentDailySteps()
                if let baseline = result.baselineSteps {
                    applyBaseline(baseline, source: .healthKit)
                    env.analytics.track(.baselineCalculated.withProperties([
                        "baseline_steps": .int(baseline),
                        "sample_days": .int(result.samples.count)
                    ]))
                    go(to: .baselineResult)
                } else {
                    env.analytics.track(.healthKitPermissionDenied)
                    healthMessage = String(localized: "We couldn't find enough walking history. A quick estimate works too.", locale: env.appLanguage.locale)
                    go(to: .manualBaseline)
                }
            } catch {
                env.analytics.track(.healthKitPermissionDenied)
                healthMessage = error.localizedDescription
                go(to: .manualBaseline)
            }
            isLoadingHealth = false
        }
    }

    private func applyBaseline(_ steps: Int, source: BaselineSource) {
        profile.baselineDailySteps = steps
        profile.baselineSource = source
        profile.movement = movementBand(for: steps)
        profile.recommendedDailyStepGoal = GoalRecommendationEngine.recommend(forBaseline: steps)
        env.analytics.track(.recommendedGoalCreated.withProperties([
            "baseline_steps": .int(steps),
            "recommended_goal": .int(profile.dailyStepGoal)
        ]))
    }

    private func movementBand(for steps: Int) -> OnboardingProfile.MovementBand {
        switch steps {
        case ..<3_000: .underThreeThousand
        case ..<5_000: .threeToFiveThousand
        case ..<8_000: .fiveToEightThousand
        default: .eightThousandPlus
        }
    }

    private var manualSelection: ManualBaseline? {
        guard profile.baselineSource == .selfReported else { return nil }
        return ManualBaseline.allCases.first { $0.steps == profile.baselineDailySteps }
    }

    private var goalBinding: Binding<Int> {
        Binding(get: { profile.dailyStepGoal }, set: { profile.recommendedDailyStepGoal = $0 })
    }

    private func advance() {
        guard let next = route.next else { return }
        go(to: next)
    }

    private func goBack() {
        guard let previous = route.previous else { return }
        go(to: previous, movingBack: true)
    }

    private func go(to route: Route, movingBack: Bool = false) {
        isMovingBack = movingBack
        storedRoute = route.rawValue
    }

    private func adaptiveLayout<Content: View, Action: View>(
        _ eyebrow: LocalizedStringKey,
        _ title: LocalizedStringKey,
        back: (() -> Void)?,
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action
    ) -> some View {
        OnboardingScaffold(onBack: back) {
            if route != .mission {
                ProgressView(value: Double(route.progress), total: Double(Route.progressCount))
                    .tint(Theme.cobalt)
                    .padding(.bottom, Theme.Space.l)
                    .accessibilityLabel("Onboarding progress")
            }
            Text(eyebrow).eyebrowStyle(Theme.coralDeep)
            Text(title)
                .font(.serif(40, relativeTo: .largeTitle))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)
            content()
        } action: { action() }
    }

    private func continueButton(disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button("Continue", action: action).buttonStyle(.pill).disabled(disabled)
    }

    private func choices<Value: Hashable>(
        _ values: [Value],
        selected: Value?,
        select: @escaping (Value) -> Void,
        label: @escaping (Value) -> LocalizedStringKey
    ) -> some View {
        VStack(spacing: Theme.Space.s) {
            ForEach(values, id: \.self) { value in
                let isSelected = selected == value
                let title = label(value)
                Button { select(value) } label: {
                    HStack {
                        Text(title)
                            .font(.sans(16, weight: .semibold))
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Theme.cobaltDeep : Theme.muted)
                    }
                    .padding(.horizontal, Theme.Space.m)
                    .frame(minHeight: 56)
                    .background(isSelected ? Theme.cobaltSoft : Theme.paper, in: .rect(cornerRadius: Theme.cornerRadius))
                    .overlay { RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(isSelected ? Theme.cobalt : Theme.line) }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.top, Theme.Space.l)
    }

    @ViewBuilder
    private func contextualScrollingCopy(_ band: OnboardingProfile.ScrollingBand) -> some View {
        let weeklyHours = switch band {
        case .underOneHour: 7
        case .oneToTwoHours: 14
        case .twoToThreeHours, .threeToFourHours: 28
        case .fourHoursPlus: 28
        }
        Text(band == .fourHoursPlus
             ? "That's more than \(weeklyHours) hours every week. Earnit helps you reclaim some of it without forcing you to quit your favorite apps."
             : "That can add up to about \(weeklyHours) hours each week. Earnit helps you make that time more intentional.")
            .font(.sans(14.5))
            .foregroundStyle(Theme.muted)
            .padding(Theme.Space.m)
            .background(Theme.sageLight, in: .rect(cornerRadius: Theme.cornerRadius))
    }

    private func permissionRow(_ icon: String, _ label: LocalizedStringKey, _ color: Color) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.1), in: .circle)
            Text(label).font(.serif(23))
        }
        .accessibilityElement(children: .combine)
    }

    private func planRow(_ icon: String, _ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon).foregroundStyle(Theme.cobaltDeep).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.sans(13)).foregroundStyle(Theme.muted)
                Text(value).font(.sans(17, weight: .semibold))
            }
            Spacer()
        }
        .padding(.vertical, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }

    private func projectionRow(_ icon: String, _ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon).foregroundStyle(Theme.coralDeep).frame(width: 26)
            Text(label).font(.sans(15, weight: .semibold))
            Spacer()
            Text(value).font(.serif(23)).monospacedDigit()
        }
        .frame(minHeight: 64)
        .accessibilityElement(children: .combine)
    }

    enum Route: String, CaseIterable {
        case hook, scrolling, intent, health, manualBaseline, baselineResult, progressiveGoal
        case apps, plan, customize, projection, paywall, mission

        static let progressCount = 10
        var progress: Int {
            switch self {
            case .hook: 0
            case .scrolling: 1
            case .intent: 2
            case .health, .manualBaseline: 3
            case .baselineResult: 4
            case .progressiveGoal: 5
            case .apps: 6
            case .plan, .customize: 7
            case .projection: 8
            case .paywall: 9
            case .mission: 10
            }
        }
        var next: Route? {
            switch self {
            case .hook: .scrolling
            case .scrolling: .intent
            case .intent: .health
            case .health: .baselineResult
            case .manualBaseline: .baselineResult
            case .baselineResult: .progressiveGoal
            case .progressiveGoal: .apps
            case .apps: .plan
            case .plan: .projection
            case .customize: .projection
            case .projection: .paywall
            case .paywall: .mission
            case .mission: nil
            }
        }
        var previous: Route? {
            switch self {
            case .hook: nil
            case .scrolling: .hook
            case .intent: .scrolling
            case .health: .intent
            case .manualBaseline: .health
            case .baselineResult: .health
            case .progressiveGoal: .baselineResult
            case .apps: .progressiveGoal
            case .plan: .apps
            case .customize: .plan
            case .projection: .plan
            case .paywall: .projection
            case .mission: nil
            }
        }
    }
}

private enum ManualBaseline: Int, CaseIterable, Hashable {
    case underTwo, twoToFive, fiveToEight, eightPlus
    var steps: Int {
        switch self {
        case .underTwo: 1_500
        case .twoToFive: 3_500
        case .fiveToEight: 6_500
        case .eightPlus: 9_000
        }
    }
    var label: LocalizedStringKey {
        switch self {
        case .underTwo: "Under 2,000 steps/day"
        case .twoToFive: "2,000–5,000 steps/day"
        case .fiveToEight: "5,000–8,000 steps/day"
        case .eightPlus: "8,000+ steps/day"
        }
    }
}

private extension UserPrimaryGoal {
    var label: LocalizedStringKey {
        switch self {
        case .moveMore: "Move more"
        case .scrollLess: "Scroll less"
        case .feelInControl: "Feel more in control"
        case .healthierRoutine: "Build a healthier routine"
        }
    }
    var desiredOutcome: OnboardingProfile.DesiredOutcome {
        switch self {
        case .moveMore: .walkMore
        case .scrollLess: .scrollLess
        case .feelInControl: .feelInControl
        case .healthierRoutine: .beMoreActive
        }
    }
}

private struct OnboardingPaywallStep: View {
    let profile: OnboardingProfile
    let onActivated: () -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ProPaywallView(profile: profile, allowsDismiss: false, onActivated: onActivated)
            .task {
                await env.subscriptionManager.refresh()
                if env.subscriptionManager.isPro { onActivated() }
            }
    }
}

#Preview {
    OnboardingView()
        .environment(AppEnvironment(
            screenTime: MockScreenTimeService(status: .approved),
            health: MockHealthKitService(dailySteps: [2_900, 2_700, 3_100, 2_600, 2_800, 2_500, 3_000])
        ))
}
