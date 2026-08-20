import EarnDomain
import Foundation
import SwiftUI

/// Wires the services together and owns the state the UI observes.
@MainActor
@Observable
final class AppEnvironment {
    let screenTime: ScreenTimeServing
    let health: HealthKitServing

    private(set) var state: SharedState
    private(set) var lastError: String?
    private(set) var isRefreshing = false

    init(screenTime: ScreenTimeServing? = nil, health: HealthKitServing? = nil) {
        self.screenTime = screenTime ?? AppEnvironment.makeScreenTimeService()
        self.health = health ?? AppEnvironment.makeHealthService()
        self.state = SharedStore.shared.load()
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
    var isLocked: Bool { state.ledger.restrictionState == .locked }
    var hasCompletedOnboarding: Bool { state.onboardingCompleted }
    var nextMilestone: NextMilestone { CreditEngine.nextMilestone(in: state.ledger) }

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
            SharedStore.shared.mutate { state in
                state.ledger = CreditEngine.apply(activityAmount: steps, to: state.ledger).ledger
                state.lastActivitySyncAt = Date()
            }
            lastError = nil
        } catch {
            // A failed step read must never break the app: the wallet simply does not grow.
            lastError = error.localizedDescription
        }

        state = screenTime.reconcile()
    }

    /// Re-reads shared state without touching HealthKit (the extension may have changed it).
    func reload() {
        state = screenTime.reconcile()
    }

    func completeOnboarding() {
        state = SharedStore.shared.mutate { $0.onboardingCompleted = true }
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
        SharedStore.shared.reset()
        reload()
    }

    var isAppGroupConfigured: Bool { AppGroup.isConfigured }
}
