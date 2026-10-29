import AVFoundation
import EarnDomain
import SwiftUI

enum OnboardingRouteStorage {
    /// v4 dropped five read-only screens, so a stored v3 route can point at a step that no longer
    /// exists or no longer means the same thing. A new key restarts anyone caught mid-flow on a
    /// flow that is now a third shorter.
    static let key = "onboarding.route.v4"

    static func reset() {
        AppGroup.defaults.set(OnboardingView.Route.hook.rawValue, forKey: key)
    }
}

/// Onboarding, v7 — *fewer screens, and none of them a page of text.*
///
/// v6 asked for sixteen steps before the paywall, and eight of those existed only to be read:
/// the time cost, the difference, the mechanism, the science, the baseline, the goal, the plan,
/// the projection. Each one was an eyebrow, a serif headline, two paragraphs and a button, and
/// by the fourth they were indistinguishable — which is how someone who wanted the product ends
/// up leaving before ever seeing what it costs.
///
/// Three changes carry this version:
///
/// 1. **The reading screens merged.** Difference folded into mechanism as its headline, science
///    into a single tappable line on the goal screen, baseline and goal into one, projection into
///    the plan. Sixteen steps became eleven, and every remaining one has a job you can name.
/// 2. **Pictures replaced the paragraphs.** A year drawn as 365 marks, the earn loop played once
///    beat by beat, the goal as a sliver of cobalt on the app's own tick rule. See
///    `OnboardingGraphics.swift`. Where a graphic carries the argument, the copy is one line.
/// 3. **Questions answer themselves.** Choosing advances. Four screens no longer charge a second
///    tap to confirm a choice nothing could invalidate.
///
/// The eyebrows are gone everywhere. Sixteen lines of uppercase label that named the screen you
/// were already looking at were the cheapest text in the flow to cut.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(OnboardingRouteStorage.key, store: AppGroup.defaults) private var storedRoute = Route.hook.rawValue

    @State private var profile = OnboardingProfile()
    @State private var isMovingBack = false
    @State private var isLoadingHealth = false
    @State private var isActivating = false
    @State private var isRequestingNotifications = false
    @State private var healthMessage: String?
    @State private var isShowingScienceSource = false
    @State private var reminderTime: Date = {
        let saved = DailyReminderPreference.saved
        return Calendar.current.date(bySettingHour: saved.hour, minute: saved.minute, second: 0, of: Date()) ?? Date()
    }()

    /// Someone who left on the paywall under v7 resumes at the mission: that screen and the
    /// paywall's position after the first unlock both assume they have already set up.
    ///
    /// The push-up demo screens are gone, so anyone who left on one picks up at the apps step,
    /// which is where the demo used to send them.
    private var route: Route {
        if storedRoute == Route.legacyPaywallRawValue { return .mission }
        if Route.legacyPushupsDemoRawValues.contains(storedRoute) { return .apps }
        return Route(rawValue: storedRoute) ?? .hook
    }

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
            // Stamped once per install so `onboarding_completed` can report the total time.
            let isResuming = profile.onboardingStartedAt != nil
            if !isResuming { profile.onboardingStartedAt = Date() }
            // Every relaunch mid-flow used to report a fresh start; `resumed` keeps the funnel's
            // first step counting people, not app launches.
            env.analytics.track(.onboardingStarted.withProperties([
                "resumed": .bool(isResuming),
                "route": .string(route.rawValue)
            ]))
            env.analytics.track(.screenViewed("onboarding_" + route.rawValue))
        }
        .onChange(of: profile) { _, updated in env.saveProfile(updated) }
        .onChange(of: route) { _, newRoute in
            env.analytics.track(.screenViewed("onboarding_" + newRoute.rawValue))
        }
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
            step("How long do you scroll each day?", back: goBack) {
                OnboardingChoices(
                    values: OnboardingProfile.ScrollingBand.allCases,
                    selected: profile.scrolling,
                    label: \.label
                ) { value in
                    profile.scrolling = value
                    env.analytics.track(.screenTimeEstimateSelected.withProperties([
                        "screen_time_bucket": .string(value.rawValue)
                    ]))
                    advance()
                }
            } action: { EmptyView() }
        case .timeCost:
            timeCostStep
        case .intent:
            step("What would you like to change?", back: goBack) {
                OnboardingChoices(
                    values: UserPrimaryGoal.allCases,
                    selected: profile.primaryGoal,
                    label: \.label
                ) { value in
                    profile.primaryGoal = value
                    profile.desiredOutcomes = [value.desiredOutcome]
                    env.analytics.track(.primaryGoalSelected.withProperties([
                        "primary_goal": .string(value.rawValue)
                    ]))
                    advance()
                }
            } action: { EmptyView() }
        case .previousAttempt:
            step("What have you tried before?", back: goBack) {
                // Choosing advances, and people who had tried several things kept coming back
                // from the next screen to pick another. One answer is all the headline uses.
                Text("Pick the one you relied on most.")
                    .font(.sans(15))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Theme.Space.m)
                OnboardingChoices(
                    values: OnboardingProfile.PreviousAttempt.allCases,
                    selected: profile.previousAttempt,
                    label: \.label
                ) { value in
                    profile.previousAttempt = value
                    advance()
                }
            } action: { EmptyView() }
        case .mechanism:
            mechanismStep
        case .health:
            healthStep
        case .manualBaseline:
            step("About how much do you usually walk?", back: goBack) {
                Text("Your estimate sets your goal. Connect Apple Health on the Earn screen to count your steps.")
                    .font(.sans(14))
                    .foregroundStyle(Night.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Theme.Space.l)
                OnboardingChoices(
                    values: ManualBaseline.allCases,
                    selected: manualSelection,
                    label: \.label
                ) { value in
                    applyBaseline(value.steps, source: .selfReported)
                    env.analytics.track(.baselineSelfReported.withProperties([
                        "baseline_steps": .int(value.steps)
                    ]))
                    go(to: .goal)
                }
            } action: { EmptyView() }
        case .goal:
            goalStep
        case .apps:
            AppsStep(onContinue: advance, onBack: goBack)
        case .plan:
            planStep
        case .customize:
            customizeStep
        case .trial:
            trialStep
        case .notifications:
            notificationsStep
        case .mission:
            missionStep
        }
    }

    // MARK: - Steps

    /// The cost of scrolling: the big number, then the year that makes it real.
    ///
    /// Hours lead because "46 days" is the honest unit and the unimpressive one — a thousand-odd
    /// hours is the figure that lands. The calendar underneath then converts it back into
    /// something you can hold, so the screen gets the size of the number *and* the weight of
    /// seeing a month and a half of your own year go dark.
    private var timeCostStep: some View {
        step(nil, back: goBack) {
            VStack(alignment: .leading, spacing: 0) {
                CountUp(value: annualScrollingHours)
                Text("hours a year, spent scrolling")
                    .font(.sans(19, weight: .semibold))
                    .foregroundStyle(Night.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            YearGrid(daysLost: annualScrollingDays)
                .padding(.top, Theme.Space.xxl)
            Text("That's \(annualScrollingDays.formatted()) full days of your year.")
                .font(.sans(15, weight: .semibold))
                .foregroundStyle(Night.textSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.m)
            Text("Each mark is a day, estimated from the range you picked.")
                .font(.sans(13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        } action: {
            Button("I want some of that time back", action: advance).buttonStyle(.pill)
        }
    }

    /// The objection, then the answer — on one screen instead of two.
    ///
    /// The headline is whatever the previous question said has already failed for this person,
    /// and the loop underneath is the reply. The closing line names *their* objection and answers
    /// it in one sentence — without it the screen states a problem, shows a diagram, and leaves
    /// the person to join the two themselves, which is exactly where "this isn't for me" happens.
    ///
    /// It is set in the serif rather than the running sans on purpose: the switch back to the
    /// display face is what marks it as the conclusion instead of another caption.
    private var mechanismStep: some View {
        step(
            profile.previousAttempt?.differenceHeadline ?? "Your apps stop opening on autopilot.",
            back: goBack
        ) {
            EarnLoopDiagram()
                .padding(.top, Theme.Space.m)
            Text(profile.previousAttempt?.differenceClose ?? "Not a ban. A pause you can open, once you've moved.")
                .font(.serif(28))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.xl)
        } action: {
            Button("That makes sense") {
                env.analytics.track(.mechanismUnderstood)
                advance()
            }
            .buttonStyle(.pill)
        }
    }

    private var healthStep: some View {
        step("Let's see where you're starting from.", back: goBack) {
            VStack(spacing: Theme.Space.m) {
                permissionRow("heart.fill", "Apple Health", Night.textSoft)
                Image(systemName: "arrow.down").foregroundStyle(Theme.muted).accessibilityHidden(true)
                permissionRow("target", "Your personal baseline", Night.cobaltText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Space.l)
            Text("Your health history stays on your device. Earnit only keeps the baseline used for your plan.")
                .font(.sans(13.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
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

    /// Baseline and first goal, which v6 spent two full screens saying in sequence.
    ///
    /// The rule does both at once: the ground already covered is soft, the increment is the only
    /// cobalt on the screen, and how little of the rule it takes *is* the argument that the goal
    /// is achievable. The science that used to be its own four-paragraph screen is the quiet line
    /// underneath — available to the one person in twenty who wants the citation, free for the
    /// nineteen who don't.
    private var goalStep: some View {
        let baseline = profile.baselineDailySteps ?? 0
        let goal = profile.dailyStepGoal
        let increase = max(0, goal - baseline)
        return step(
            increase > 0
                ? "Just \(increase.formatted()) more steps than your usual day."
                : "\(goal.formatted()) steps a day.",
            back: goBack
        ) {
            GoalRule(baseline: baseline, goal: goal)
                .padding(.top, Theme.Space.m)
            Text("The goal only changes after a full week, and only if you accept.")
                .font(.sans(14.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.xl)
            Button {
                env.analytics.track(.scienceScreenViewed)
                isShowingScienceSource = true
            } label: {
                Label("Why not 10,000 steps?", systemImage: "doc.text.magnifyingglass")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Night.cobaltText)
                    .frame(minHeight: Theme.minTouchTarget)
            }
            .buttonStyle(.plain)
        } action: {
            Button("Use this goal", action: advance).buttonStyle(.pill)
        }
        .onAppear { env.analytics.track(.personalizedResultViewed) }
    }

    /// The plan and what thirty days of it adds up to, on one screen.
    ///
    /// v6 showed the settings, then made you tap once more for the payoff. The payoff belongs
    /// next to what produces it, so it is a number that counts up rather than a row in a panel.
    private var planStep: some View {
        let projection = Projection(
            currentDailySteps: profile.baselineDailySteps ?? 0,
            goalDailySteps: profile.dailyStepGoal,
            rule: EarningRule(source: .steps, amountRequired: 500, rewardSeconds: 300)
        )
        return step("Move once. Choose later.", back: goBack) {
            VStack(spacing: 0) {
                planRow("target", "Daily movement goal", "\(profile.dailyStepGoal.formatted()) steps")
                planRow("figure.walk", "Earn rate", "500 steps → 5 min")
                planRow("figure.strengthtraining.traditional", "Or push-ups", "5 reps → 5 min")
                planRow("apps.iphone", "Protected apps", "\(env.state.restrictedItemCount) selected")
                planRow("sparkles", "Goal reward", "+10 bonus min")
            }
            Hairline()
                .padding(.vertical, Theme.Space.l)
            CountUp(value: projection.upliftSteps, font: .serif(52))
            Text("extra steps in your first 30 days")
                .font(.sans(16, weight: .semibold))
                .foregroundStyle(Night.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            Text("This is a conditional estimate, not a health outcome or a prediction of what you will do.")
                .font(.sans(13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.m)
        } action: {
            Button("Start my plan") {
                env.analytics.track(.starterPlanAccepted.withProperties([
                    "selected_goal": .int(profile.dailyStepGoal),
                    "earn_rate": .string("500:5")
                ]))
                env.analytics.track(.thirtyDayProjectionCTA)
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
            env.analytics.track(.thirtyDayProjectionViewed)
        }
    }

    private var customizeStep: some View {
        step("Adjust your daily goal", back: { go(to: .plan, movingBack: true) }) {
            Stepper(value: goalBinding, in: 2_000...20_000, step: 500) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily movement goal").font(.sans(14, weight: .semibold)).foregroundStyle(Theme.muted)
                    Text("\(profile.dailyStepGoal.formatted()) steps").font(.serif(30)).monospacedDigit()
                }
            }
            .padding(Theme.Space.m)
            .background(Night.panel, in: .rect(cornerRadius: Theme.cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Night.edge) }
            planRow("figure.walk", "Recommended earn rate", "500 steps → 5 min")
                .padding(.top, Theme.Space.m)
            planRow("figure.strengthtraining.traditional", "Or push-ups", "5 reps → 5 min")
        } action: {
            Button("Save plan") { go(to: .plan, movingBack: true) }.buttonStyle(.pill)
        }
    }

    /// The trial offer, straight after "Start my plan" — the moment intent peaks. In 1.2.2–1.3.0
    /// the only automatic paywall followed the first spent unlock, and most people left before
    /// spending one. Unlike v7's wall at this spot it can be closed: declining carries on to the
    /// free unlock, and the post-unlock paywall still follows it.
    @ViewBuilder
    private var trialStep: some View {
        if env.subscriptionManager.isPro {
            Color.clear.onAppear(perform: advance)
        } else {
            ProPaywallView(
                source: .onboarding,
                profile: profile,
                declineTitle: "Not now, try one free unlock first",
                onActivated: advance,
                onClose: advance
            )
        }
    }

    /// Asked before the first earn because reminders are what bring someone back on day two, and
    /// in 1.2.2 nobody who finished onboarding came back. This screen goes first so the system
    /// prompt only appears for people who already said yes to the idea.
    ///
    /// v9 shows the notifications themselves instead of describing them, the way AppBlock,
    /// BePresent and Blockin prime the prompt, and lets the person pick when the daily one lands
    /// (Bend, Lyfta, Duolingo). "Reminders" in the abstract reads as spam; "+5 min earned" does not.
    private var notificationsStep: some View {
        step("We only nudge you when it matters.", back: goBack) {
            NotificationExamples(
                stepsPerReward: 500,
                rewardMinutes: 5,
                dailyGoal: profile.dailyStepGoal,
                reminderTime: reminderTime
            )
            .padding(.bottom, Theme.Space.l)
            HStack {
                Label("Daily walk reminder", systemImage: "bell.fill")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Night.text)
                Spacer()
                DatePicker(
                    "Daily walk reminder",
                    selection: $reminderTime,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .colorScheme(.dark)
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .background(Night.panel, in: .rect(cornerRadius: Theme.cornerRadius))
            Text("No spam. Change or turn them off any time in Settings.")
                .font(.sans(13.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.m)
        } action: {
            Button {
                guard !isRequestingNotifications else { return }
                isRequestingNotifications = true
                Task {
                    let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                    await env.requestNotificationPermission(source: "onboarding")
                    await env.setDailyReminder(DailyReminderPreference(
                        isEnabled: true,
                        hour: components.hour ?? 18,
                        minute: components.minute ?? 0
                    ))
                    isRequestingNotifications = false
                    advance()
                }
            } label: {
                HStack {
                    if isRequestingNotifications { ProgressView().tint(Color.white) }
                    Text("Turn on reminders")
                }
            }
            .buttonStyle(.pill)
            .disabled(isRequestingNotifications)
            Button("Not now") {
                env.analytics.track(.notificationsPromptSkipped)
                advance()
            }
            .buttonStyle(.quiet)
        }
        .onAppear { env.analytics.track(.notificationsPromptViewed) }
    }

    /// Push-ups are the one way to earn the first minutes without leaving the screen, so the
    /// mission offers them first whenever this phone can count reps and the free reward is
    /// unspent. In 1.2.2, four of the five people who finished onboarding wandered into Home and
    /// Settings instead of earning anything, and none of them came back.
    private var offersPushupsNow: Bool {
        Self.canCountReps && env.featureAccess.canUseWorkoutEarning
    }

    /// Rep counting needs a front camera. The Simulator has none but still gets the push-up
    /// mission, so its layout can be checked there; the camera screen then shows its error.
    private static var canCountReps: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
        #endif
    }

    private func startFirstEarn(withPushups: Bool) {
        guard !isActivating else { return }
        isActivating = true
        env.analytics.track(.firstEarnStarted.withProperties([
            "method": .string(withPushups ? EarningMethod.pushups.rawValue : EarningMethod.steps.rawValue),
            "pushups_offered": .bool(offersPushupsNow)
        ]))
        Task {
            await env.activateAdaptivePlan(profile)
            // Home's navigation stack picks this up as soon as it appears.
            if withPushups {
                // Anyone who has not met push-ups is owed the announcement sheet on Home, which
                // would open over the camera they are about to use.
                env.markPushupsIntroSeen()
                env.requestRoute(.pushups)
            }
        }
    }

    /// The commitment moment, and the only other place onboarding spends an illustration: the
    /// path he is about to walk. Everything between the opening and here has been plain ground,
    /// so the artwork returning is what marks this as the end of setup.
    ///
    /// When this phone can count reps, the screen leads with earning the first minutes here and
    /// now, and spending them straight after: the whole trade the app sells, inside the first
    /// session. Until 1.3.5 it led with a walk, and the median person who finished onboarding
    /// took 38 minutes to earn anything; 27 of 40 never did within a week.
    @ViewBuilder
    private var missionStep: some View {
        if offersPushupsNow {
            pushupsMission
        } else {
            walkMission
        }
    }

    private var pushupsMission: some View {
        illustratedLayout(scene: .earnPath) {
            Text("Earn your first 5 minutes right now.")
                .font(.serif(38, relativeTo: .largeTitle))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                missionBeat(1, "Do 5 push-ups in front of the camera.")
                missionBeat(2, "Your 5 minutes land in your balance.")
                missionBeat(3, "Unlock your apps with them, right away.")
            }
            .padding(.top, Theme.Space.l)
            Text("Push-ups are counted on this iPhone. No video is recorded or uploaded.")
                .font(.sans(13.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.l)
        } action: {
            Button {
                startFirstEarn(withPushups: true)
            } label: {
                HStack {
                    if isActivating { ProgressView().tint(Color.white) }
                    Text(isActivating ? "Activating your plan" : "Earn them now with push-ups")
                }
            }
            .buttonStyle(.pill)
            .disabled(isActivating)
            Button("I'd rather walk 500 steps") { startFirstEarn(withPushups: false) }
                .buttonStyle(.quiet)
                .disabled(isActivating)
        }
    }

    private func missionBeat(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(number.formatted())
                .font(.serif(25))
                .foregroundStyle(Night.cobaltText)
                .frame(width: 22, alignment: .leading)
                .accessibilityHidden(true)
            Text(text)
                .font(.sans(17, weight: .semibold))
                .foregroundStyle(Night.textSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var walkMission: some View {
        illustratedLayout(scene: .earnPath) {
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
                startFirstEarn(withPushups: false)
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

    // MARK: - Data

    /// The midpoint of the band the user picked, so the calendar is neither the flattering end of
    /// the range nor the alarming one. An open-ended band has only its floor to be honest with.
    private var annualScrollingDays: Int { Int(annualScrollingDaysExact.rounded()) }
    private var annualScrollingHours: Int { Int((annualScrollingDaysExact * 24).rounded()) }

    /// Both figures come off this one midpoint, so the headline and the calendar can never
    /// disagree about the same year.
    private var annualScrollingDaysExact: Double {
        guard let scrolling = profile.scrolling else { return 0 }
        let days = ScreenTimeCostRange(scrollingBand: scrolling).annualDays
        guard let upper = days.upperBound else { return days.lowerBound }
        return (days.lowerBound + upper) / 2
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
                    go(to: .goal)
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

    // MARK: - Navigation

    private func advance() {
        guard let next = route.next else { return }
        go(to: next)
    }

    private func goBack() {
        guard let previous = route.previous else { return }
        env.analytics.track(.onboardingBackTapped.withProperties([
            "from": .string(route.rawValue),
            "to": .string(previous.rawValue)
        ]))
        go(to: previous, movingBack: true)
    }

    private func go(to route: Route, movingBack: Bool = false) {
        isMovingBack = movingBack
        storedRoute = route.rawValue
    }

    // MARK: - Layout

    /// Every functional step: the progress rule, an optional headline, the content, the actions.
    ///
    /// The headline is optional because one screen's headline is a number 96pt tall, and wrapping
    /// a label around it would only repeat what the numeral already says.
    private func step<Content: View, Action: View>(
        _ title: LocalizedStringKey?,
        back: (() -> Void)?,
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action
    ) -> some View {
        OnboardingScaffold(
            onBack: back,
            progress: Double(route.progress) / Double(Route.progressCount)
        ) {
            if let title {
                Text(title)
                    .font(.serif(40, relativeTo: .largeTitle))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Theme.Space.l)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
        } action: { action() }
    }

    /// The illustrated variant, for the one step that earns artwork.
    private func illustratedLayout<Content: View, Action: View>(
        scene: IllustratedScene,
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action
    ) -> some View {
        let body = content()
        let footer = action()
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SceneHero(scene: scene, share: 0.42) { EmptyView() }
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

    private func permissionRow(_ icon: String, _ label: LocalizedStringKey, _ color: Color) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(Night.forestLift, in: .circle)
            Text(label).font(.serif(23))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    enum Route: String, CaseIterable {
        case hook, scrolling, timeCost, intent, previousAttempt, mechanism
        case health, manualBaseline, goal
        case apps, plan, customize, trial, notifications, mission

        /// v7 ended onboarding at a paywall; v8 moves it after the first unlock. `trial` is a
        /// new raw value so nobody resuming from that old route lands on the new offer.
        static let legacyPaywallRawValue = "paywall"
        /// Up to 1.3.5 a three-rep push-up demo sat between the goal and the apps. It asked for
        /// the camera and the effort and paid nothing: 23 of 29 people who started it never
        /// finished, and those who did were asked for five more reps at the mission. The first
        /// push-ups are now the real challenge the mission opens, which credits the minutes.
        static let legacyPushupsDemoRawValues: Set<String> = ["pushupsIntro", "pushupsDemo", "pushupsLater"]
        static let progressCount = 11
        var progress: Int {
            switch self {
            case .hook: 0
            case .scrolling: 1
            case .timeCost: 2
            case .intent: 3
            case .previousAttempt: 4
            case .mechanism: 5
            case .health, .manualBaseline: 6
            case .goal: 7
            case .apps: 8
            case .plan, .customize: 9
            // Full screen, with no progress rule of its own.
            case .trial, .notifications: 10
            case .mission: 11
            }
        }
        var next: Route? {
            switch self {
            case .hook: .scrolling
            case .scrolling: .timeCost
            case .timeCost: .intent
            case .intent: .previousAttempt
            case .previousAttempt: .mechanism
            case .mechanism: .health
            case .health, .manualBaseline: .goal
            case .goal: .apps
            case .apps: .plan
            // Customizing returns to the plan rather than skipping past it, so the number the
            // new goal produces is the thing that sends you on.
            case .plan, .customize: .trial
            case .trial: .notifications
            case .notifications: .mission
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
            case .mechanism: .previousAttempt
            case .health: .mechanism
            case .manualBaseline: .health
            case .goal: .health
            case .apps: .goal
            case .plan: .apps
            case .customize: .plan
            // The offer is not a step to walk back into.
            case .trial: nil
            case .notifications: .plan
            case .mission: nil
            }
        }
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

    /// What this person already knows does not work — used as the mechanism screen's headline, so
    /// the answer they are about to watch has something specific to answer.
    var differenceHeadline: LocalizedStringKey {
        switch self {
        case .appleLimits: "A limit is easy to override in the moment."
        case .blockingApps: "A total block can feel too rigid."
        case .deletingApps: "Deleting an app doesn't change the impulse."
        case .willpower: "Willpower makes you decide again and again."
        case .nothingYet: "Restriction alone is hard to sustain."
        }
    }

    /// The reply, in one sentence. Long enough to answer the headline, short enough that someone
    /// who has already understood the diagram can skip it without losing anything.
    var differenceClose: LocalizedStringKey {
        switch self {
        case .appleLimits:
            "There is no “ignore limit” here. Only minutes you already earned."
        case .blockingApps:
            "Earnit never says no. It says not yet — and hands you the way through."
        case .deletingApps:
            "Nothing gets deleted. The impulse just has to move first."
        case .willpower:
            "You decide once, while you move. Not again every time you pick up the phone."
        case .nothingYet:
            "Nothing to resist. Move first, and the time is already yours."
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

#Preview {
    OnboardingView()
        .environment(AppEnvironment(
            screenTime: MockScreenTimeService(status: .approved),
            health: MockHealthKitService(dailySteps: [2_900, 2_700, 3_100, 2_600, 2_800, 2_500, 3_000])
        ))
}
