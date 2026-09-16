import EarnDomain
import FamilyControls
import Foundation
import SwiftUI

enum AppRoute: Equatable {
    case home
    /// Home, with the push-up camera pushed on top of it.
    case pushups
}

/// Wires the services together and owns the state the UI observes.
@MainActor
@Observable
final class AppEnvironment {
    let screenTime: ScreenTimeServing
    let health: HealthKitServing
    let subscriptionManager: SubscriptionManager
    let analytics: any AnalyticsTracking
    let study: any StudyServing
    let studyOCR: any StudyOCRServing
    let exercise: any ExerciseServing
    let pendingExerciseClaims: PendingExerciseClaimStore
    private let sessionNotifications = SessionNotificationService()
    private let liveActivities = EarnLiveActivityManager()

    private(set) var state: SharedState
    private(set) var lastError: String?
    private(set) var isRefreshing = false
    private(set) var isStartingSession = false
    private(set) var isPausingSession = false
    private(set) var appLanguage: AppLanguage
    private(set) var isPresentingBlockedAppDetail = false
    /// Transient feedback for a transition that has already completed in the domain layer.
    /// This is deliberately never persisted: reopening Home must not replay a celebration.
    private(set) var presentationFeedback: EarnPresentationFeedback?
    private(set) var pendingRoute: AppRoute?
    private var identifiedBackendUserID: UUID?

    init(
        screenTime: ScreenTimeServing? = nil,
        health: HealthKitServing? = nil,
        subscriptionManager: SubscriptionManager? = nil,
        appLanguage: AppLanguage? = nil,
        analytics: (any AnalyticsTracking)? = nil,
        study: (any StudyServing)? = nil,
        studyOCR: (any StudyOCRServing)? = nil,
        exercise: (any ExerciseServing)? = nil,
        pendingExerciseClaims: PendingExerciseClaimStore? = nil
    ) {
        let analytics = analytics ?? AppAnalytics.make()
        self.screenTime = screenTime ?? AppEnvironment.makeScreenTimeService()
        self.health = health ?? AppEnvironment.makeHealthService()
        self.subscriptionManager = subscriptionManager ?? SubscriptionManager()
        self.analytics = analytics
        self.study = study ?? AppEnvironment.makeStudyService()
        self.studyOCR = studyOCR ?? VisionStudyOCRService()
        self.exercise = exercise ?? AppEnvironment.makeExerciseService()
        self.pendingExerciseClaims = pendingExerciseClaims ?? PendingExerciseClaimStore()
        self.appLanguage = appLanguage ?? .saved
        var shouldTrackWalletCreation = false
        let loaded = SharedStore.shared.mutate { state in
            // Existing completed users keep access and begin the new journey without seeing a paywall.
            if state.onboardingCompleted, state.journey == nil {
                state.journey = ThirtyDayJourney(startDay: state.ledger.day, dailyGoal: state.dailyStepGoal)
            }
            if !state.walletCreatedTracked {
                state.walletCreatedTracked = true
                shouldTrackWalletCreation = true
            }
        }
        self.state = loaded
        if shouldTrackWalletCreation { analytics.track(.walletCreated) }
        if loaded.onboardingCompleted, ShieldLaunchIntent.consume() {
            isPresentingBlockedAppDetail = true
            analytics.track(.earnScreenOpenedFromShield)
        }
        reportPendingSessionSettlement()
    }

    /// Screen Time simply does not work in the Simulator: authorization always fails and there
    /// are no shields. Use the mocks there so the UI stays developable without a device.
    private static func makeScreenTimeService() -> ScreenTimeServing {
        #if targetEnvironment(simulator)
        MockScreenTimeService()
        #else
        LiveScreenTimeService()
        #endif
    }

    private static func makeHealthService() -> HealthKitServing {
        #if targetEnvironment(simulator)
        MockHealthKitService()
        #else
        LiveHealthKitService()
        #endif
    }

    private static func makeStudyService() -> any StudyServing {
        SupabaseStudyService() ?? UnconfiguredStudyService()
    }

    private static func makeExerciseService() -> any ExerciseServing {
        SupabaseExerciseService() ?? UnconfiguredExerciseService()
    }

    // MARK: - Derived state

    var ledger: DailyLedger { state.ledger }
    var wallet: ScreenTimeWallet { state.ledger.wallet }
    var activeSession: ScreenTimeSession? { state.activeSession() }
    var isLocked: Bool { activeSession == nil }
    var supportedSessionDurations: [Int] { ScreenTimeSessionEngine.supportedDurations }
    var hasCompletedOnboarding: Bool { state.onboardingCompleted }
    var nextMilestone: NextMilestone { CreditEngine.nextMilestone(in: state.ledger) }
    var featureAccess: FeatureAccess { subscriptionManager.featureAccess }
    var hapticFeedbackEnabled: Bool { HapticManager.isEnabled }

    var profile: OnboardingProfile { state.onboarding }
    var requiresSubscription: Bool { hasCompletedOnboarding && subscriptionManager.status == .free }
    /// The daily step target the user picked during onboarding.
    var dailyStepGoal: Int { state.dailyStepGoal }
    var projection: Projection { Projection(profile: state.onboarding, rule: state.ledger.rule) }
    var streakDays: Int { state.history.streak(endingOn: state.ledger.day, including: state.ledger) }
    var week: [DaySummary] { state.history.week(endingOn: state.ledger.day, including: state.ledger) }
    var journey: ThirtyDayJourney? { state.journey }
    var journeyDay: Int { state.journey?.elapsedDay(asOf: state.ledger.day) ?? 0 }
    var journeyProgress: ThirtyDayJourney.Progress? {
        state.journey?.progress(includingToday: DaySummary(ledger: state.ledger))
    }
    var monthTotals: ActivityHistory.Totals {
        state.history.totals(
            forMonthContaining: state.ledger.day,
            including: DaySummary(ledger: state.ledger)
        )
    }

    /// 0…1 through today's step goal.
    ///
    /// This is what Home's illustration and Earn time's meter read from. It has to be
    /// the *day*, not `milestoneProgress`: the milestone resets every few hundred steps, so a
    /// screen driven by it would saw up and down all day instead of waking once.
    var dayProgress: Double {
        guard dailyStepGoal > 0 else { return 0 }
        return min(1, max(0, Double(ledger.activityAmount) / Double(dailyStepGoal)))
    }

    /// Minutes credited today, before anything was spent.
    var earnedMinutesToday: Int { wallet.earnedSeconds / 60 }
    var consumedMinutesToday: Int { currentConsumedSeconds() / 60 }
    var walletBalanceMinutes: Int { currentWalletBalanceSeconds() / 60 }
    var maximumStartableMinutes: Int {
        ScreenTimeSessionEngine.maximumStartableMinutes(
            availableMinutes: wallet.availableMinutes,
            at: Date()
        )
    }

    func canFitStudyReward(seconds: Int) -> Bool {
        seconds > 0 && wallet.remainingValueSeconds <= ScreenTimeWallet.maximumSavedSeconds - seconds
    }

    func currentWalletBalanceSeconds(at date: Date = Date()) -> Int {
        wallet.availableSeconds
    }

    func currentConsumedSeconds(at date: Date = Date()) -> Int {
        wallet.consumedSeconds + (activeSession?.elapsedSeconds(at: date) ?? 0)
    }

    /// Whether the next milestone is the one that completes today's goal.
    var isFinalMilestoneOfDay: Bool {
        ledger.activityAmount + nextMilestone.remainingAmount >= dailyStepGoal
    }

    /// 0...1 toward the next reward.
    var milestoneProgress: Double {
        let rule = state.ledger.rule
        guard rule.amountRequired > 0 else { return 0 }
        let done = rule.amountRequired - nextMilestone.remainingAmount
        return min(1, max(0, Double(done) / Double(rule.amountRequired)))
    }

    // MARK: - Actions

    func prepareStudyConfiguration() async throws -> StudyConfiguration {
        guard featureAccess.canUseFocusEarning else { throw StudyAccessError.subscriptionRequired }
        let userID = try await study.ensureIdentity()
        if identifiedBackendUserID != userID {
            try await subscriptionManager.identify(appUserID: userID.uuidString.lowercased())
            identifiedBackendUserID = userID
        }
        let configuration = try await study.configuration()
        guard configuration.enabled else { throw StudyAccessError.disabled }
        guard configuration.entitled else { throw StudyAccessError.subscriptionRequired }
        return configuration
    }

    func prepareExerciseConfiguration() async throws -> ExerciseConfiguration {
        guard featureAccess.canUseWorkoutEarning else { throw ExerciseAccessError.subscriptionRequired }
        let userID = try await exercise.ensureIdentity()
        if identifiedBackendUserID != userID {
            try await subscriptionManager.identify(appUserID: userID.uuidString.lowercased())
            identifiedBackendUserID = userID
        }
        let configuration = try await exercise.configuration()
        guard configuration.enabled else { throw ExerciseAccessError.disabled }
        guard configuration.entitled else { throw ExerciseAccessError.subscriptionRequired }
        guard configuration.updateRequired != true else { throw ExerciseAccessError.updateRequired }
        return configuration
    }

    func canFitExerciseReward(seconds: Int) -> Bool {
        seconds > 0 && wallet.remainingValueSeconds <= ScreenTimeWallet.maximumSavedSeconds - seconds
    }

    @discardableResult
    func applyExerciseReward(_ reward: ExerciseReward) throws -> Bool {
        let receipt = ServerRewardReceipt(
            id: reward.id,
            method: .pushups,
            rewardSeconds: reward.amountSeconds,
            issuedAt: reward.createdAt,
            externalReference: reward.sessionID.uuidString.lowercased()
        )
        var result = ServerRewardEngine.Result.invalidReward
        state = SharedStore.shared.mutate { state in
            let outcome = ServerRewardEngine.apply(receipt, to: state)
            state = outcome.state
            result = outcome.result
        }
        switch result {
        case .applied:
            analytics.track(.pushupsRewardClaimed.withProperties([
                "reward_seconds": .int(reward.amountSeconds)
            ]))
            analytics.track(.rewardCompleted.withProperties([
                "reward_minutes": .int(reward.amountSeconds / 60),
                "earning_method": .string(EarningMethod.pushups.rawValue)
            ]))
            analytics.track(.minutesEarned.withProperties([
                "seconds": .int(reward.amountSeconds),
                "balance_seconds": .int(state.ledger.wallet.remainingValueSeconds),
                "earning_method": .string(EarningMethod.pushups.rawValue)
            ]))
            HapticManager.trigger(.earned)
            synchronizeLiveActivity(presentation: .earned(minutes: reward.amountSeconds / 60))
            return true
        case .duplicate:
            return true
        case .insufficientWalletCapacity:
            throw ExerciseAccessError.walletCapacity
        case .invalidReward:
            throw ExerciseAccessError.invalidReward
        }
    }

    @discardableResult
    func applyStudyReward(_ reward: StudyAPIReturnedReward) throws -> Bool {
        let receipt = StudyRewardReceipt(
            id: reward.id,
            rewardSeconds: reward.amountSeconds,
            issuedAt: reward.issuedAt,
            externalReference: reward.sessionID.uuidString.lowercased()
        )
        var result = StudyRewardEngine.Result.invalidReward
        state = SharedStore.shared.mutate { state in
            let outcome = StudyRewardEngine.apply(receipt, to: state)
            state = outcome.state
            result = outcome.result
        }
        switch result {
        case .applied:
            analytics.track(.studyRewardGranted.withProperties([
                "reward_seconds": .int(reward.amountSeconds)
            ]))
            analytics.track(.rewardCompleted.withProperties([
                "reward_minutes": .int(reward.amountSeconds / 60),
                "earning_method": .string(EarningMethod.study.rawValue)
            ]))
            analytics.track(.minutesEarned.withProperties([
                "seconds": .int(reward.amountSeconds),
                "balance_seconds": .int(state.ledger.wallet.remainingValueSeconds),
                "earning_method": .string(EarningMethod.study.rawValue)
            ]))
            HapticManager.trigger(.earned)
            synchronizeLiveActivity(presentation: .earned(minutes: reward.amountSeconds / 60))
            return true
        case .duplicate:
            return true
        case .insufficientWalletCapacity:
            throw StudyAccessError.walletCapacity
        case .invalidReward:
            throw StudyAccessError.invalidReward
        }
    }

    /// Reads today's activity, awards any milestone reached, and makes the shields match.
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        HapticManager.prepare(.earned)
        HapticManager.prepare(.goalCompleted)

        var livePresentation: EarnActivityAttributes.ContentState.PresentationState?
        do {
            let steps = try await health.todaySteps()
            var outcome: CreditEngine.Outcome?
            let previousLedger = state.ledger
            let hadEarnedFirstReward = state.hasEarnedFirstReward
            let previousStreak = streakDays
            state = SharedStore.shared.mutate { state in
                let applied = CreditEngine.apply(activityAmount: steps, to: state.ledger)
                state.ledger = applied.ledger
                state.lastActivitySyncAt = Date()
                if applied.didAwardSteps, !state.hasEarnedFirstReward {
                    state.hasEarnedFirstReward = true
                }
                outcome = applied
            }
            if let outcome, outcome.didAward {
                let reachedGoal = previousLedger.activityAmount < dailyStepGoal
                    && outcome.ledger.activityAmount >= dailyStepGoal
                let earnedFirstReward = outcome.didAwardSteps && !hadEarnedFirstReward
                let currentStreak = streakDays
                if earnedFirstReward {
                    publish(.firstRewardEarned(minutes: outcome.awardedStepSeconds / 60))
                    livePresentation = .earned(minutes: outcome.awardedStepSeconds / 60)
                    analytics.track(.firstRewardEarned.withProperties([
                        "reward_minutes": .int(outcome.awardedStepSeconds / 60)
                    ]))
                } else if outcome.didAwardGoalBonus || reachedGoal {
                    publish(.dailyGoalCompleted(minutes: outcome.awardedGoalBonusSeconds / 60))
                    livePresentation = .goalCompleted
                } else {
                    publish(.screenTimeEarned(minutes: outcome.awardedSeconds / 60))
                    livePresentation = .earned(minutes: outcome.awardedSeconds / 60)
                }
                if outcome.didAwardGoalBonus || reachedGoal {
                    analytics.track(.dailyGoalCompleted.withProperties([
                        "bonus_minutes": .int(outcome.awardedGoalBonusSeconds / 60)
                    ]))
                }
                if !reachedGoal, currentStreak > previousStreak {
                    // Earning feedback is more important than a routine streak tick.
                    // The numeric streak still transitions with the refreshed state.
                }
                analytics.track(.rewardCompleted.withProperties(["reward_minutes": .int(outcome.awardedSeconds / 60)]))
                analytics.track(.minutesEarned.withProperties([
                    "seconds": .int(outcome.awardedSeconds),
                    "balance_seconds": .int(outcome.ledger.wallet.remainingValueSeconds)
                ]))
            }
            if let outcome, outcome.didReachWalletCapacity {
                publish(.walletFull)
                analytics.track(.walletCapReached.withProperties([
                    "uncredited_seconds": .int(outcome.uncreditedSeconds),
                    "cap_minutes": .int(ScreenTimeWallet.maximumSavedSeconds / 60)
                ]))
            }
            lastError = nil
        } catch HealthKitError.unavailable {
            setError(String(localized: "health.error.unavailable", locale: appLanguage.locale))
        } catch {
            // A failed step read must never break the app: the wallet simply does not grow.
            setError(error.localizedDescription)
        }

        applyReconciledState(screenTime.reconcile(), livePresentation: livePresentation)
    }

    /// Refreshes immediately on foreground, then re-reads shared state once more because
    /// DeviceActivity may finish delivering a session callback just after the scene becomes active.
    func refreshAfterBecomingActive() async {
        await refresh()
        presentShieldDetailIfRequested()
        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled else { return }
        reload()
    }

    /// Re-reads shared state without touching HealthKit (the extension may have changed it).
    func reload() {
        applyReconciledState(screenTime.reconcile())
    }

    private func applyReconciledState(
        _ nextState: SharedState,
        livePresentation: EarnActivityAttributes.ContentState.PresentationState? = nil
    ) {
        let previousSession = state.currentSession
        state = nextState
        reportPendingSessionSettlement()
        guard previousSession?.status == .active,
              nextState.currentSession?.id == previousSession?.id,
              nextState.currentSession?.status == .completed else {
            synchronizeLiveActivity(presentation: livePresentation)
            return
        }
        publish(.appLocked, haptic: .balanceExpired)
        synchronizeLiveActivity(presentation: livePresentation ?? .balanceExpired)
    }

    func activateAdaptivePlan(_ profile: OnboardingProfile) async {
        let currentSteps = (try? await health.todaySteps()) ?? state.ledger.activityAmount
        let adaptiveRule = EarningRule(source: .steps, amountRequired: 500, rewardSeconds: 5 * 60)
        let now = Date()
        let today = DayKey(date: now)
        state = SharedStore.shared.mutate(now: now) { state in
            var finalizedProfile = profile
            finalizedProfile.onboardingCompletedAt = now
            finalizedProfile.pendingGoalRecommendation = nil
            state.onboarding = finalizedProfile
            state.onboardingCompleted = true
            state.adaptiveIntroSeen = true
            // Onboarding introduces push-ups itself, so a fresh user is never owed the announcement.
            state.pushupsIntroSeen = true
            state.hasEarnedFirstReward = false
            state.goalProgressionCooldownUntil = today.adding(days: 7)
            state.ledger.rule = adaptiveRule
            state.ledger.activityAmount = max(state.ledger.activityAmount, currentSteps)
            state.ledger.baselineAmount = state.ledger.activityAmount
            state.ledger.milestonesRewarded = 0
            state.ledger.dailyGoal = finalizedProfile.dailyStepGoal
            state.ledger.goalBonusSeconds = 10 * 60
            state.ledger.goalBonusAwarded = state.ledger.activityAmount >= finalizedProfile.dailyStepGoal
            state.ledger.transactions = []
            state.journey = ThirtyDayJourney(startDay: state.ledger.day, dailyGoal: finalizedProfile.dailyStepGoal)
        }
        analytics.track(.onboardingCompleted.withProperties([
            "baseline_steps": .int(profile.baselineDailySteps ?? 0),
            "selected_goal": .int(profile.dailyStepGoal),
            "earn_rate_steps": .int(adaptiveRule.amountRequired),
            "earn_rate_minutes": .int(adaptiveRule.rewardMinutes)
        ]))
        synchronizeLiveActivity()
    }

    func acknowledgeJourneyCompletion() {
        state = SharedStore.shared.mutate { state in
            if let journey = state.journey {
                state.journey = journey.acknowledgingCompletion()
            }
        }
    }

    /// Stores the onboarding answers. Called as the user answers, so leaving mid-flow and
    /// coming back does not lose them.
    func saveProfile(_ profile: OnboardingProfile) {
        state = SharedStore.shared.mutate { $0.onboarding = profile }
        synchronizeLiveActivity()
    }

    func dismissPresentationFeedback(_ feedback: EarnPresentationFeedback) {
        guard presentationFeedback?.id == feedback.id else { return }
        presentationFeedback = nil
    }

    func setHapticFeedbackEnabled(_ isEnabled: Bool) {
        HapticManager.isEnabled = isEnabled
    }

    func dismissBlockedAppDetail() {
        isPresentingBlockedAppDetail = false
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "earnyourscreentime", url.host == "home" else { return }
        guard hasCompletedOnboarding else { return }
        isPresentingBlockedAppDetail = false
        pendingRoute = .home
    }

    func requestRoute(_ route: AppRoute) {
        pendingRoute = route
    }

    func consumePendingRoute() {
        pendingRoute = nil
    }

    private func presentShieldDetailIfRequested() {
        guard hasCompletedOnboarding, ShieldLaunchIntent.consume() else { return }
        isPresentingBlockedAppDetail = true
        analytics.track(.earnScreenOpenedFromShield)
    }

    func setAppLanguage(_ language: AppLanguage) {
        guard language != appLanguage else { return }
        language.save()
        appLanguage = language
        lastError = nil
        if let session = activeSession {
            Task { await sessionNotifications.schedule(for: session, language: language) }
        }
        synchronizeLiveActivity()
    }

    func startSession(durationMinutes: Int) async {
        guard !isStartingSession else { return }
        isStartingSession = true
        defer { isStartingSession = false }
        HapticManager.prepare(.unlocked)

        await sessionNotifications.requestAuthorizationIfNeeded()
        do {
            let walletBalanceBefore = wallet.availableSeconds
            state = try screenTime.startSession(durationMinutes: durationMinutes)
            if let session = activeSession {
                await sessionNotifications.schedule(for: session, language: appLanguage)
            }
            lastError = nil
            publish(.appUnlocked)
            synchronizeLiveActivity(presentation: .unlocked)
            analytics.track(.sessionStarted.withProperties([
                "wallet_balance_before": .int(walletBalanceBefore),
                "wallet_balance_after": .int(state.ledger.wallet.availableSeconds),
                "session_duration": .int(durationMinutes * 60)
            ]))
        } catch ScreenTimeSessionError.insufficientBalance {
            analytics.track(.unlockAttemptWithoutBalance.withProperties([
                "requested_minutes": .int(durationMinutes),
                "balance_seconds": .int(wallet.availableSeconds)
            ]))
            setError(String(
                localized: "session.error.insufficientBalance",
                locale: appLanguage.locale
            ), haptic: .warning)
        } catch ScreenTimeSessionError.sessionAlreadyActive {
            setError(String(
                localized: "session.error.alreadyActive",
                locale: appLanguage.locale
            ), haptic: .warning)
        } catch ScreenTimeSessionError.unsupportedDuration {
            setError(String(
                localized: "session.error.unsupportedDuration",
                locale: appLanguage.locale
            ), haptic: .warning)
        } catch ScreenTimeSessionError.exceedsCarryOverWindow {
            setError(String(
                localized: "session.error.exceedsCarryOverWindow",
                locale: appLanguage.locale
            ), haptic: .warning)
        } catch RestrictionCoordinatorError.noSelection {
            setError(String(localized: "session.error.noSelection", locale: appLanguage.locale), haptic: .warning)
        } catch {
            setError(error.localizedDescription)
        }
    }

    func pauseSession() async {
        guard !isPausingSession, let previous = activeSession else { return }
        isPausingSession = true
        defer { isPausingSession = false }
        let next = screenTime.pauseSession()
        sessionNotifications.cancel(sessionID: previous.id)
        state = next
        let saved = next.currentSession?.id == previous.id
            ? next.currentSession?.savedSeconds ?? 0
            : 0
        lastError = nil
        publish(saved > 0 ? .timeSaved(seconds: saved) : .appLocked)
        synchronizeLiveActivity()
        reportPendingSessionSettlement()
    }

    func updateRestrictedSelection(_ selection: FamilyActivitySelection) {
        screenTime.selection = selection
        state = screenTime.reconcile()
        reportPendingSessionSettlement()
        synchronizeLiveActivity()
    }

    /// Changing the rule only affects future milestones (PRD §16).
    func updateRule(_ rule: EarningRule) {
        SharedStore.shared.mutate { state in
            state.ledger = CreditEngine.changeRule(to: rule, in: state.ledger)
        }
        reload()
    }

    func updateDailyGoal(_ goal: Int) {
        let rounded = max(GoalRecommendationEngine.minimumGoal, (goal / 500) * 500)
        let today = DayKey.today()
        state = SharedStore.shared.mutate { state in
            state.onboarding.recommendedDailyStepGoal = rounded
            state.onboarding.lastGoalRecommendationDate = Date()
            state.onboarding.pendingGoalRecommendation = nil
            state.goalProgressionCooldownUntil = today.adding(days: 7)
            state.ledger.dailyGoal = rounded
            if state.ledger.activityAmount >= rounded {
                state.ledger.goalBonusAwarded = true
            }
        }
        synchronizeLiveActivity()
    }

    func evaluateGoalRecommendation() async {
        let today = DayKey.today()
        guard hasCompletedOnboarding,
              state.onboarding.pendingGoalRecommendation == nil,
              state.goalProgressionCooldownUntil.map({ $0 <= today }) ?? true,
              let result = try? await health.recentDailySteps(),
              result.samples.count == GoalProgressionEngine.windowDays else { return }
        let activities = result.samples.map {
            DailyActivity(day: DayKey(date: $0.date), steps: $0.steps, goal: dailyStepGoal)
        }
        guard let recommendation = GoalProgressionEngine.recommendation(
            currentGoal: dailyStepGoal,
            activities: activities
        ), recommendation != dailyStepGoal else { return }
        state = SharedStore.shared.mutate { $0.onboarding.pendingGoalRecommendation = recommendation }
        let event = recommendation > dailyStepGoal
            ? AnalyticsEvent.goalIncreaseRecommended
            : AnalyticsEvent.goalDecreaseRecommended
        analytics.track(event.withProperties([
            "current_goal": .int(dailyStepGoal),
            "recommended_goal": .int(recommendation),
            "goal_reached_days": .int(activities.count(where: \.reachedGoal))
        ]))
    }

    func respondToGoalRecommendation(accept: Bool) {
        guard let recommendation = state.onboarding.pendingGoalRecommendation else { return }
        let increases = recommendation > dailyStepGoal
        if accept { updateDailyGoal(recommendation) }
        state = SharedStore.shared.mutate { state in
            state.onboarding.pendingGoalRecommendation = nil
            state.onboarding.lastGoalRecommendationDate = Date()
            state.goalProgressionCooldownUntil = DayKey.today().adding(days: 7)
        }
        analytics.track(accept
            ? (increases ? .goalIncreaseAccepted : .goalDecreaseAccepted)
            : (increases ? .goalIncreaseRejected : .goalDecreaseRejected))
    }

    func markAdaptiveIntroSeen() {
        state = SharedStore.shared.mutate { $0.adaptiveIntroSeen = true }
    }

    func markPushupsIntroSeen() {
        state = SharedStore.shared.mutate { $0.pushupsIntroSeen = true }
    }

    // MARK: - Debug helpers (Phase 2 spike)

    func grantDebugCredit(seconds: Int) {
        SharedStore.shared.mutate { state in
            let credited = state.ledger.wallet.credit(seconds: seconds)
            if credited > 0 {
                state.ledger.walletTransactions.append(WalletTransaction(
                    kind: .earned,
                    amountSeconds: credited,
                    source: .debug,
                    date: Date()
                ))
            }
        }
        reload()
    }

    func resetToday() {
        if let session = state.currentSession {
            sessionNotifications.cancel(sessionID: session.id)
        }
        state = screenTime.resetToday()
        synchronizeLiveActivity()
    }

    var isAppGroupConfigured: Bool { AppGroup.isConfigured }

    func synchronizeLiveActivity(
        presentation: EarnActivityAttributes.ContentState.PresentationState? = nil
    ) {
        let next = CreditEngine.nextMilestone(in: state.ledger)
        liveActivities.synchronize(
            EarnLiveActivityManager.Snapshot(
                isEligible: state.onboardingCompleted
                    && health.hasRequestedAuthorization
                    && screenTime.authorizationStatus.isApproved
                    && state.hasRestrictedApps,
                dayKey: state.ledger.day.description,
                steps: state.ledger.activityAmount,
                nextMilestoneTarget: next.targetAmount,
                dailyGoalTarget: state.dailyStepGoal,
                availableMinutes: state.ledger.wallet.availableMinutes,
                earnedMinutesToday: state.ledger.wallet.earnedSeconds / 60,
                nextRewardMinutes: next.rewardMinutes,
                milestoneStepAmount: state.ledger.rule.amountRequired,
                activeSessionEndsAt: state.activeSession()?.endsAt,
                localeIdentifier: appLanguage.locale.identifier
            ),
            presentation: presentation
        )
    }

    #if DEBUG
    func replayOnboarding() {
        OnboardingRouteStorage.reset()
        isPresentingBlockedAppDetail = false
        presentationFeedback = nil
        state = SharedStore.shared.mutate { state in
            state.onboarding = OnboardingProfile()
            state.onboardingCompleted = false
        }
        synchronizeLiveActivity()
    }

    func replayPushupsIntro() {
        state = SharedStore.shared.mutate { $0.pushupsIntroSeen = false }
    }

    func triggerDebugFeedback(_ event: EarnPresentationEvent) {
        publish(event)
    }
    #endif

    private func publish(_ event: EarnPresentationEvent, haptic: EarnHaptic? = nil) {
        presentationFeedback = EarnPresentationFeedback(event: event)
        HapticManager.trigger(haptic ?? event.haptic ?? .light)
    }

    private func reportPendingSessionSettlement() {
        guard let pending = state.currentSession,
              pending.status != .active,
              !pending.settlementAnalyticsReported else { return }
        switch pending.status {
        case .completed:
            analytics.track(.sessionExpired.withProperties([
                "wallet_balance_after": .int(state.ledger.wallet.availableSeconds),
                "session_duration": .int(pending.reservedSeconds),
                "actual_session_duration": .int(pending.consumedSeconds)
            ]))
        case .paused:
            analytics.track(.sessionPaused.withProperties([
                "wallet_balance_after": .int(state.ledger.wallet.availableSeconds),
                "session_duration": .int(pending.reservedSeconds),
                "actual_session_duration": .int(pending.consumedSeconds),
                "reserved_seconds": .int(pending.reservedSeconds),
                "consumed_seconds": .int(pending.consumedSeconds),
                "returned_seconds": .int(pending.savedSeconds)
            ]))
        case .cancelled:
            break
        case .active:
            return
        }
        analytics.track(.minutesConsumed.withProperties(["seconds": .int(pending.consumedSeconds)]))
        if pending.status == .paused {
            analytics.track(.minutesSaved.withProperties(["seconds": .int(pending.savedSeconds)]))
            analytics.track(.sessionTimeReturned.withProperties([
                "returned_seconds": .int(pending.savedSeconds),
                "wallet_balance_after": .int(state.ledger.wallet.availableSeconds)
            ]))
        }
        if state.ledger.wallet.availableSeconds == 0 {
            analytics.track(.walletEmpty)
        }
        state = SharedStore.shared.mutate { state in
            guard state.currentSession?.id == pending.id,
                  state.currentSession?.status != .active else { return }
            state.currentSession?.settlementAnalyticsReported = true
        }
    }


    private func setError(_ message: String, haptic: EarnHaptic = .error) {
        guard lastError != message else { return }
        lastError = message
        publish(.error, haptic: haptic)
    }
}

enum StudyAccessError: LocalizedError {
    case subscriptionRequired
    case disabled
    case walletCapacity
    case invalidReward

    var errorDescription: String? {
        switch self {
        case .subscriptionRequired: "Study to Earn requires an active Pro subscription."
        case .disabled: "Study to Earn is temporarily unavailable."
        case .walletCapacity: "Use some minutes before starting. The full study reward must fit in your balance."
        case .invalidReward: "Earnit could not verify the study reward."
        }
    }
}

enum ExerciseAccessError: LocalizedError {
    case subscriptionRequired
    case disabled
    case updateRequired
    case walletCapacity
    case invalidReward

    var errorDescription: String? {
        switch self {
        case .subscriptionRequired: "Pushups to Earn requires an active Pro subscription."
        case .disabled: "Pushups to Earn is temporarily unavailable."
        case .updateRequired: "Update Earnit to use Pushups to Earn."
        case .walletCapacity: "Use some minutes first. The full push-up reward must fit in your balance."
        case .invalidReward: "Earnit could not verify the push-up reward."
        }
    }
}
