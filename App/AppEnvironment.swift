import EarnDomain
import Foundation
import SwiftUI

/// Wires the app's services together and holds the state the UI observes.
@MainActor
@Observable
final class AppEnvironment {
    let screenTime: ScreenTimeServing
    private(set) var state: SharedState

    init(screenTime: ScreenTimeServing? = nil) {
        self.screenTime = screenTime ?? AppEnvironment.makeScreenTimeService()
        self.state = SharedStore.shared.load()
    }

    /// Screen Time simply does not work in the Simulator: authorization always fails and
    /// there are no shields. Use the mock there so the UI is still developable.
    private static func makeScreenTimeService() -> ScreenTimeServing {
        #if targetEnvironment(simulator)
        return MockScreenTimeService()
        #else
        return LiveScreenTimeService()
        #endif
    }

    /// Re-reads the shared state and makes the shields match the balance.
    func refresh() {
        state = screenTime.reconcile()
    }

    /// Debug helper for the Phase 2 spike: grant screen time without walking.
    func grantDebugCredit(seconds: Int) {
        SharedStore.shared.mutate { $0.ledger.wallet.credit(seconds: seconds) }
        refresh()
    }

    func resetToday() {
        SharedStore.shared.reset()
        refresh()
    }

    var isAppGroupConfigured: Bool { AppGroup.isConfigured }
}
