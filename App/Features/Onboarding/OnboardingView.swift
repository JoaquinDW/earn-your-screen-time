import EarnDomain
import SwiftUI

enum OnboardingRouteStorage {
    static let key = "onboarding.route.v3"

    static func reset() {
        AppGroup.defaults.set(OnboardingView.Route.hook.rawValue, forKey: key)
    }
}

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @AppStorage(OnboardingRouteStorage.key, store: AppGroup.defaults) private var storedRoute = Route.hook.rawValue

    @State private var profile = OnboardingProfile()
    @State private var isMovingBack = false
    @State private var isLoadingHealth = false
    @State private var isActivating = false
    @State private var healthMessage: String?
    @State private var isShowingScienceSource = false

    private var route: Route { Route(rawValue: storedRoute) ?? .hook }

    var body: some View {
        ZStack {
            Night.ground.ignoresSafeArea()
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
        .sheet(isPresented: $isShowingScienceSource) {
            ScienceSourceSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
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
        case .timeCost:
            timeCostStep
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
        case .previousAttempt:
            adaptiveLayout("WHAT YOU'VE TRIED", "What have you tried before?", back: goBack) {
                Text("There is no wrong answer. This helps us explain what Earnit changes.")
                    .font(.sans(15))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, Theme.Space.s)
                choices(OnboardingProfile.PreviousAttempt.allCases, selected: profile.previousAttempt) { value in
                    profile.previousAttempt = value
                } label: { $0.label }
            } action: {
                continueButton(disabled: profile.previousAttempt == nil, action: advance)
            }
        case .difference:
            differenceStep
        case .mechanism:
            mechanismStep
        case .science:
            scienceStep
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
            adaptiveLayout("YOUR STARTING POINT", "You're averaging \((profile.baselineDailySteps ?? 0).formatted()) steps a day.", back: goBack) {
                Spacer(minLength: Theme.Space.xl)
                Text("This isn't a score. It's the number your first plan will grow from.")
                    .font(.serif(27))
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("Measured from recent Health activity or the estimate you selected.")
                    .font(.sans(15))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, Theme.Space.s)
            } action: { Button("Show my first goal", action: advance).buttonStyle(.pill) }
            .onAppear { env.analytics.track(.personalizedResultViewed) }
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

    private var timeCostStep: some View {
        let range = profile.scrolling.map(ScreenTimeCostRange.init(scrollingBand:))
        return adaptiveLayout("TIME ADDS UP", "Scrolling rarely feels this long in the moment.", back: goBack) {
            if let range {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    insightMetric(range.weeklyHours.display(locale: locale), "hours every week")
                    Hairline()
                    insightMetric(range.annualDays.display(locale: locale), "full days every year")
                }
                .padding(Theme.Space.m)
                .background(Night.panel, in: .rect(cornerRadius: Theme.cornerRadius))
                .overlay { RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Night.edge) }
                .padding(.top, Theme.Space.xl)
            }
            Text("An estimate based on the range you selected. The point isn't guilt. It's seeing what autopilot can cost.")
                .font(.sans(14.5))
                .foregroundStyle(Theme.muted)
                .padding(.top, Theme.Space.m)
        } action: {
            Button("I want some of that time back", action: advance).buttonStyle(.pill)
        }
    }

    private var differenceStep: some View {
        adaptiveLayout(
            "A DIFFERENT APPROACH",
            profile.previousAttempt?.differenceHeadline ?? "Restriction alone is hard to sustain.",
            back: goBack
        ) {
            Text(profile.previousAttempt?.differenceBody ?? "Most tools ask you to resist the same impulse again and again. Earnit changes what happens before an app opens.")
                .font(.sans(17))
                .foregroundStyle(Night.textSoft)
                .padding(.top, Theme.Space.l)
            VStack(spacing: 0) {
                comparisonRow("Traditional limits", "Keep saying no", emphasized: false)
                Hairline()
                comparisonRow("Earnit", "Move once, choose later", emphasized: true)
            }
            .padding(.horizontal, Theme.Space.m)
            .background(Night.panel, in: .rect(cornerRadius: Theme.cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Night.edge) }
            .padding(.top, Theme.Space.xl)
        } action: {
            Button("Show me how", action: advance).buttonStyle(.pill)
        }
    }

    private var mechanismStep: some View {
        adaptiveLayout("THIS IS EARNIT", "Your apps stop opening on autopilot.", back: goBack) {
            VStack(spacing: Theme.Space.s) {
                mechanismRow("figure.walk", "Walk 500 steps", "Do something good for yourself")
                mechanismConnector
                mechanismRow("timer", "Earn 5 minutes", "Your movement becomes a balance")
                mechanismConnector
                mechanismRow("hand.tap", "Choose when to use them", "Open a 5, 10, or 15-minute session")
            }
            .padding(.top, Theme.Space.xl)
            Text("Not a permanent ban. Not another limit to ignore. A pause between impulse and choice.")
                .font(.sans(15, weight: .semibold))
                .foregroundStyle(Night.textSoft)
                .padding(.top, Theme.Space.l)
        } action: {
            Button("That makes sense") {
                env.analytics.track(.mechanismUnderstood)
                advance()
            }
            .buttonStyle(.pill)
        }
    }

    private var scienceStep: some View {
        adaptiveLayout("BUILT FROM YOUR BASELINE", "10,000 isn't a magic number.", back: goBack) {
            Text("A 2022 meta-analysis of 15 international studies found that health benefits were associated with step counts below 10,000, and the pattern differed by age.")
                .font(.sans(17))
                .foregroundStyle(Night.textSoft)
                .padding(.top, Theme.Space.l)
            Text("Earnit's reward loop also draws on “temptation bundling”: pairing something you want with an activity that benefits you. It is a behavioral principle, not a guarantee.")
                .font(.sans(15))
                .foregroundStyle(Theme.muted)
                .padding(.top, Theme.Space.m)
            Button {
                isShowingScienceSource = true
            } label: {
                Label("See the study", systemImage: "doc.text.magnifyingglass")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Night.cobaltText)
                    .frame(minHeight: Theme.minTouchTarget)
            }
            .buttonStyle(.plain)
            .padding(.top, Theme.Space.s)
            Text("That is why Earnit starts from your recent activity and recommends a small increase, rather than assigning the same target to everyone.")
                .font(.serif(25))
                .padding(.top, Theme.Space.xl)
        } action: {
            Button("Build my starting point", action: advance).buttonStyle(.pill)
        }
        .onAppear { env.analytics.track(.scienceScreenViewed) }
    }

    private var healthStep: some View {
        adaptiveLayout("A GOAL THAT FITS", "Let's see where you're starting from.", back: goBack) {
            Text("Earnit uses your walking activity to create a goal that actually fits you.")
                .font(.sans(16))
                .foregroundStyle(Theme.muted)
                .padding(.top, Theme.Space.s)
            VStack(spacing: Theme.Space.m) {
                permissionRow("heart.fill", "Apple Health", Night.textSoft)
                Image(systemName: "arrow.down").foregroundStyle(Theme.muted).accessibilityHidden(true)
                permissionRow("target", "Your personal baseline", Night.cobaltText)
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
                    if isLoadingHealth { ProgressView().tint(Color.white) }
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
        let increase = max(0, goal - baseline)
        return adaptiveLayout("YOUR FIRST GOAL", "\(goal.formatted()) steps. Just \(increase.formatted()) more than now.", back: goBack) {
            HStack(spacing: Theme.Space.m) {
                goalMetric("Today", baseline)
                Image(systemName: "arrow.right")
                    .foregroundStyle(Night.cobaltText)
                    .accessibilityHidden(true)
                goalMetric("First goal", goal)
            }
            .padding(.top, Theme.Space.xl)
            Text("Earnit starts from your average and changes the goal only after a full week of activity. You decide whether to accept each change.")
                .font(.sans(15))
                .foregroundStyle(Theme.muted)
                .padding(.top, Theme.Space.l)
        } action: { Button("Use this goal", action: advance).buttonStyle(.pill) }
    }

    private var starterPlanStep: some View {
        adaptiveLayout("YOUR PLAN IS READY", "Move once. Choose later.", back: goBack) {
            planRow("target", "Daily movement goal", "\(profile.dailyStepGoal.formatted()) steps")
            planRow("figure.walk", "Earn rate", "500 steps → 5 min")
            planRow("apps.iphone", "Protected apps", "\(env.state.restrictedItemCount) selected")
            planRow("sparkles", "Goal reward", "+10 bonus min")
            Text("Protected apps stay paused until you deliberately start a 5, 10, or 15-minute session with the balance you've earned.")
                .font(.sans(14.5))
                .foregroundStyle(Theme.muted)
                .padding(.top, Theme.Space.m)
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
        .onAppear {
            env.analytics.track(.starterPlanViewed)
            env.analytics.track(.planGenerated)
        }
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
            .background(Night.panel, in: .rect(cornerRadius: Theme.cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Night.edge) }
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
        let walkingHours = projection.upliftWalkingMinutes / 60
        let walkingMinutes = projection.upliftWalkingMinutes % 60
        return adaptiveLayout("IF YOU REACH YOUR GOAL FOR 30 DAYS", "This is what you'll add to your routine.", back: goBack) {
            VStack(spacing: 0) {
                projectionRow("arrow.up.right", "Steps above your current average", projection.upliftSteps.formatted())
                Hairline()
                projectionRow("figure.walk.motion", "Estimated extra walking", "≈ \(walkingHours) h \(walkingMinutes) min")
            }
            .padding(.horizontal, Theme.Space.m)
            .background(Night.panel, in: .rect(cornerRadius: Theme.cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Night.edge) }
            .padding(.top, Theme.Space.xl)
            Text("Calculated as \(projection.dailyStepUplift.formatted()) additional steps × 30 days. Walking time assumes about 100 steps per minute.")
                .font(.sans(13.5))
                .foregroundStyle(Theme.muted)
                .padding(.top, Theme.Space.m)
            Text("This is a conditional estimate, not a health outcome or a prediction of what you will do.")
                .font(.sans(13.5))
                .foregroundStyle(Theme.muted)
                .padding(.top, Theme.Space.s)
        } action: {
            Button("Continue with my plan") {
                env.analytics.track(.thirtyDayProjectionCTA)
                advance()
            }
            .buttonStyle(.pill)
        }
        .onAppear { env.analytics.track(.thirtyDayProjectionViewed) }
    }

    /// The commitment moment, and the only other place onboarding spends an illustration: the
    /// path he is about to walk. Everything between the opening and here has been plain ground,
    /// so the artwork returning is what marks this as the end of setup.
    private var missionStep: some View {
        illustratedLayout(scene: .earnPath, eyebrow: "YOUR FIRST MISSION") {
            Text("Your first 5 minutes are 500 steps away.")
                .font(.serif(38, relativeTo: .largeTitle))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            TickMeter(progress: 0, height: 18)
                .padding(.top, Theme.Space.l)
            HStack {
                Text("0 steps")
                Spacer()
                Text("500 steps")
            }
            .font(.sans(12.5, weight: .medium))
            .foregroundStyle(Theme.muted)
            .padding(.top, Theme.Space.s)
            Text("Take a short walk. Open Earnit when you return and your first reward will be waiting.")
                .font(.sans(15))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.l)
        } action: {
            Button {
                guard !isActivating else { return }
                isActivating = true
                env.analytics.track(.firstEarnStarted)
                Task { await env.activateAdaptivePlan(profile) }
            } label: {
                HStack {
                    if isActivating { ProgressView().tint(Color.white) }
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
                    env.analytics.track(.healthKitGranted)
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
                TickMeter(
                    progress: Double(route.progress) / Double(Route.progressCount),
                    height: 8
                )
                .padding(.bottom, Theme.Space.l)
                .accessibilityLabel("Onboarding progress")
            }
            Text(eyebrow).eyebrowStyle(Night.textMuted)
            Text(title)
                .font(.serif(40, relativeTo: .largeTitle))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)
            content()
        } action: { action() }
    }

    /// The illustrated variant of `adaptiveLayout`, for the one step that earns artwork.
    private func illustratedLayout<Content: View, Action: View>(
        scene: IllustratedScene,
        eyebrow: LocalizedStringKey,
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action
    ) -> some View {
        let body = content()
        let footer = action()
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SceneHero(scene: scene, share: 0.42) {
                        Text(eyebrow).eyebrowStyle(Night.textMuted)
                    }
                    VStack(alignment: .leading, spacing: 0) { body }
                        .padding(.horizontal, Theme.Space.gutter)
                        .padding(.top, Theme.Space.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, Theme.Space.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 2) { footer }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.vertical, Theme.Space.s)
                .background(alignment: .top) {
                    VStack(spacing: 0) {
                        GroundFade(edge: .bottom, height: 28)
                        Night.ground
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
        }
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
                    .frame(minHeight: 58)
                    .background(
                        isSelected ? Night.cobaltWash : Night.panel,
                        in: .rect(cornerRadius: Theme.cornerRadius)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cornerRadius)
                            .stroke(isSelected ? Night.cobalt : Night.edge, lineWidth: isSelected ? 1.5 : 1)
                    }
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
            .background(Night.panel, in: .rect(cornerRadius: Theme.cornerRadius))
    }

    private func permissionRow(_ icon: String, _ label: LocalizedStringKey, _ color: Color) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(Night.forestLift, in: .circle)
            Text(label).font(.serif(23))
        }
        .accessibilityElement(children: .combine)
    }

    private func insightMetric(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(value)
                .font(.serif(38))
                .foregroundStyle(Night.cobaltText)
                .monospacedDigit()
            Text(label)
                .font(.sans(15, weight: .semibold))
                .foregroundStyle(Night.textSoft)
        }
        .accessibilityElement(children: .combine)
    }

    private func comparisonRow(
        _ label: LocalizedStringKey,
        _ value: LocalizedStringKey,
        emphasized: Bool
    ) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: emphasized ? "arrow.right.circle.fill" : "minus.circle")
                .foregroundStyle(emphasized ? Night.cobaltText : Night.textMuted)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.sans(13)).foregroundStyle(Theme.muted)
                Text(value).font(.sans(16, weight: .semibold))
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 68)
        .accessibilityElement(children: .combine)
    }

    private func mechanismRow(
        _ icon: String,
        _ title: LocalizedStringKey,
        _ detail: LocalizedStringKey
    ) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Night.cobaltText)
                .frame(width: 48, height: 48)
                .background(Night.cobaltWash, in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.sans(17, weight: .semibold))
                Text(detail).font(.sans(13.5)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var mechanismConnector: some View {
        Image(systemName: "arrow.down")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Night.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 17)
            .accessibilityHidden(true)
    }

    private func goalMetric(_ label: LocalizedStringKey, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(label).font(.sans(12.5, weight: .semibold)).foregroundStyle(Theme.muted)
            Text(value.formatted()).font(.serif(28)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.m)
        .background(Night.panel, in: .rect(cornerRadius: Theme.cornerRadius))
        .overlay { RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Night.edge) }
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
        case hook, scrolling, timeCost, intent, previousAttempt, difference, mechanism, science
        case health, manualBaseline, baselineResult, progressiveGoal
        case apps, plan, customize, projection, paywall, mission

        static let progressCount = 15
        var progress: Int {
            switch self {
            case .hook: 0
            case .scrolling: 1
            case .timeCost: 2
            case .intent: 3
            case .previousAttempt: 4
            case .difference: 5
            case .mechanism: 6
            case .science: 7
            case .health, .manualBaseline: 8
            case .baselineResult: 9
            case .progressiveGoal: 10
            case .apps: 11
            case .plan, .customize: 12
            case .projection: 13
            case .paywall: 14
            case .mission: 15
            }
        }
        var next: Route? {
            switch self {
            case .hook: .scrolling
            case .scrolling: .timeCost
            case .timeCost: .intent
            case .intent: .previousAttempt
            case .previousAttempt: .difference
            case .difference: .mechanism
            case .mechanism: .science
            case .science: .health
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
            case .timeCost: .scrolling
            case .intent: .timeCost
            case .previousAttempt: .intent
            case .difference: .previousAttempt
            case .mechanism: .difference
            case .science: .mechanism
            case .health: .science
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

private extension ScreenTimeCostRange.Bounds {
    func display(locale: Locale) -> String {
        let lower = Int(lowerBound.rounded(.down))
        if lower == 0, let upperBound {
            return String(localized: "Up to \(Int(upperBound.rounded(.up)))", locale: locale)
        }
        guard let upperBound else {
            return String(localized: "\(lower)+", locale: locale)
        }
        return String(localized: "\(lower)–\(Int(upperBound.rounded(.up)))", locale: locale)
    }
}

private extension OnboardingProfile.PreviousAttempt {
    var label: LocalizedStringKey {
        switch self {
        case .appleLimits: "Apple's app limits"
        case .blockingApps: "A blocking app"
        case .deletingApps: "Deleting the apps"
        case .willpower: "Trying to use willpower"
        case .nothingYet: "Nothing yet"
        }
    }

    var differenceHeadline: LocalizedStringKey {
        switch self {
        case .appleLimits: "A limit is easy to override in the moment."
        case .blockingApps: "A total block can feel too rigid."
        case .deletingApps: "Deleting an app doesn't change the impulse."
        case .willpower: "Willpower makes you decide again and again."
        case .nothingYet: "Restriction alone is hard to sustain."
        }
    }

    var differenceBody: LocalizedStringKey {
        switch self {
        case .appleLimits:
            "Earnit changes the default: protected apps stay paused until your movement creates a balance you choose to use."
        case .blockingApps:
            "Earnit keeps the pause, but gives you a clear way to earn intentional access instead of banning the apps forever."
        case .deletingApps:
            "Earnit puts a pause before the app opens and turns that moment into a choice you have already earned."
        case .willpower:
            "Earnit moves the decision earlier: walk, build a balance, then choose a short session without negotiating with yourself."
        case .nothingYet:
            "Most tools ask you to resist the same impulse repeatedly. Earnit changes what happens before a protected app opens."
        }
    }
}

private struct ScienceSourceSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    source(
                        title: "Daily steps and all-cause mortality",
                        citation: "Paluch et al. · The Lancet Public Health · 2022",
                        explanation: "A meta-analysis of 15 international cohorts. It supports the statement that 10,000 steps is not a universal threshold and that the observed dose-response pattern varies by age.",
                        url: URL(string: "https://doi.org/10.1016/S2468-2667(21)00302-9")!
                    )
                    Hairline()
                    source(
                        title: "Holding the Hunger Games hostage at the gym",
                        citation: "Milkman, Minson & Volpp · Management Science · 2014",
                        explanation: "A field experiment on temptation bundling: linking a desired experience to exercise. It supports the behavioral principle behind pairing movement with access, not a claim that Earnit itself has been clinically validated.",
                        url: URL(string: "https://doi.org/10.1287/mnsc.2013.1784")!
                    )
                }
                .padding(Theme.Space.gutter)
            }
            .background(Night.ground)
            .foregroundStyle(Night.text)
            .navigationTitle("Evidence behind the plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func source(
        title: LocalizedStringKey,
        citation: LocalizedStringKey,
        explanation: LocalizedStringKey,
        url: URL
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title).font(.serif(27))
            Text(citation).font(.sans(13, weight: .semibold)).foregroundStyle(Night.cobaltText)
            Text(explanation).font(.sans(15)).foregroundStyle(Night.textSoft)
            Link(destination: url) {
                Label("Open published study", systemImage: "arrow.up.right.square")
                    .font(.sans(14, weight: .semibold))
                    .frame(minHeight: Theme.minTouchTarget)
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
