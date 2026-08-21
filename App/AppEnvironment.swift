import EarnDomain
import FamilyControls
import Foundation
import SwiftUI

/// Wires the services together and owns the state the UI observes.
@MainActor
@Observable
final class AppEnvironment {
    let screenTime: ScreenTimeServing
    let health: HealthKitServing
    let subscriptionManager: SubscriptionManager
    let analytics: any AnalyticsTracking
    private let sessionNotifications = SessionNotificationService()

    private(set) var state: SharedState
    private(set) var lastError: String?
    private(set) var isRefreshing = false
    private(set) var isStartingSession = false
    /// Set when a refresh crosses a milestone, cleared once the arrival scene is dismissed.
    private(set) var pendingReward: Reward?

    /// A milestone just reached.
    struct Reward: Equatable, Identifiable {
        let seconds: Int
        var minutes: Int { seconds / 60 }
        var id: Int { seconds }
    }

    init(
        screenTime: ScreenTimeServing? = nil,
        health: HealthKitServing? = nil,
        subscriptionManager: SubscriptionManager? = nil,
        analytics: any AnalyticsTracking = OSLogAnalytics()
    ) {
        self.screenTime = screenTime ?? AppEnvironment.makeScreenTimeService()
        self.health = health ?? AppEnvironment.makeHealthService()
        self.subscriptionManager = subscriptionManager ?? SubscriptionManager()
        self.analytics = analytics
        var loaded = SharedStore.shared.load()
        // Existing completed users keep access and begin the new journey without seeing a paywall.
        if loaded.onboardingCompleted, loaded.journey == nil {
            loaded.journey = ThirtyDayJourney(startDay: loaded.ledger.day, dailyGoal: loaded.dailyStepGoal)
            SharedStore.shared.save(loaded)
        }
        self.state = loaded
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

    // MARK: - Derived state

    var ledger: DailyLedger { state.ledger }
    var wallet: ScreenTimeWallet { state.ledger.wallet }
    var activeSession: ScreenTimeSession? { state.activeSession() }
    var isLocked: Bool { activeSession == nil }
    var supportedSessionDurations: [Int] { ScreenTimeSessionEngine.supportedDurations }
    var hasCompletedOnboarding: Bool { state.onboardingCompleted }
    var nextMilestone: NextMilestone { CreditEngine.nextMilestone(in: state.ledger) }
    var featureAccess: FeatureAccess { subscriptionManager.featureAccess }

    var profile: OnboardingProfile { state.onboarding }
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

    /// 0...1 toward the next reward.
    var milestoneProgress: Double {
        let rule = state.ledger.rule
        guard rule.amountRequired > 0 else { return 0 }
        let done = rule.amountRequired - nextMilestone.remainingAmount
        return min(1, max(0, Double(done) / Double(rule.amountRequired)))
    }

    // MARK: - Actions

    /// Reads today's activity, awards any milestone reached, and makes the shields match.
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let steps = try await health.todaySteps()
            var awarded = 0
            SharedStore.shared.mutate { state in
                let outcome = CreditEngine.apply(activityAmount: steps, to: state.ledger)
                state.ledger = outcome.ledger
                state.lastActivitySyncAt = Date()
                awarded = outcome.awardedSeconds
            }
            // Crossing a milestone is the one moment the app celebrates; the dashboard
            // watches this to show the arrival scene.
            if awarded > 0 { pendingReward = Reward(seconds: awarded) }
            lastError = nil
        } catch {
            // A failed step read must never break the app: the wallet simply does not grow.
            lastError = error.localizedDescription
        }

        state = screenTime.reconcile()
    }

    /// Refreshes immediately on foreground, then re-reads shared state once more because
    /// DeviceActivity may finish delivering a session callback just after the scene becomes active.
    func refreshAfterBecomingActive() async {
        await refresh()
        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled else { return }
        reload()
    }

    /// Re-reads shared state without touching HealthKit (the extension may have changed it).
    func reload() {
        state = screenTime.reconcile()
    }

    func completeOnboarding() {
        state = SharedStore.shared.mutate {
            $0.onboardingCompleted = true
            if $0.journey == nil {
                $0.journey = ThirtyDayJourney(startDay: $0.ledger.day, dailyGoal: $0.dailyStepGoal)
            }
        }
        analytics.track(.onboardingCompleted)
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
    }

    func dismissReward() { pendingReward = nil }

    func startSession(durationMinutes: Int) async {
        guard !isStartingSession else { return }
        isStartingSession = true
        defer { isStartingSession = false }

        await sessionNotifications.requestAuthorizationIfNeeded()
        do {
            state = try screenTime.startSession(durationMinutes: durationMinutes)
            if let session = activeSession {
                await sessionNotifications.schedule(for: session)
            }
            lastError = nil
        } catch ScreenTimeSessionError.insufficientBalance {
            lastError = String(localized: "session.error.insufficientBalance")
        } catch ScreenTimeSessionError.sessionAlreadyActive {
            lastError = String(localized: "session.error.alreadyActive")
        } catch ScreenTimeSessionError.unsupportedDuration {
            lastError = String(localized: "session.error.unsupportedDuration")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updateRestrictedSelection(_ selection: FamilyActivitySelection) {
        if let session = activeSession {
            sessionNotifications.cancel(sessionID: session.id)
        }
        screenTime.selection = selection
        state = screenTime.reconcile()
    }

    /// Changing the rule only affects future milestones (PRD §16).
    func updateRule(_ rule: EarningRule) {
        SharedStore.shared.mutate { state in
            state.ledger = CreditEngine.changeRule(to: rule, in: state.ledger)
        }
        reload()
    }

    // MARK: - Debug helpers (Phase 2 spike)

    func grantDebugCredit(seconds: Int) {
        SharedStore.shared.mutate { $0.ledger.wallet.credit(seconds: seconds) }
        reload()
    }

    func resetToday() {
        if let session = state.currentSession {
            sessionNotifications.cancel(sessionID: session.id)
        }
        state = screenTime.resetToday()
    }

    var isAppGroupConfigured: Bool { AppGroup.isConfigured }
}
