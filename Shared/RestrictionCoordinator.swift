import EarnDomain
import Foundation

/// Keeps the shields in sync with the wallet: the single place that decides
/// LOCKED vs AVAILABLE (PRD §11).
///
/// Used by both the app and the DeviceActivity extension so the rule can never drift.
struct RestrictionCoordinator {
    static let shared = RestrictionCoordinator()

    private let store = SharedStore.shared
    private let selectionStore = SelectionStore.shared
    private let shields = ShieldController.shared
    private let scheduler = MonitorScheduler.shared

    /// Applies or removes shields to match the current balance, and refreshes the usage
    /// thresholds. Returns the reconciled state.
    @discardableResult
    func reconcile(refreshMonitoring: Bool = true) -> SharedState {
        let selection = selectionStore.load()
        var state = store.load()
        state.restrictedItemCount = selection.itemCount

        let shouldShield = state.ledger.restrictionState == .locked || selection.isEmpty
        if shouldShield {
            shields.apply(selection)
        } else {
            shields.clear()
        }
        state.shieldsApplied = shouldShield

        if refreshMonitoring {
            try? scheduler.refresh(state: state, selection: selection)
        }

        store.save(state)
        return state
    }

    /// Records usage reported by a DeviceActivity threshold event and re-shields if the
    /// balance is now spent. Safe to call with repeated or out-of-order events.
    @discardableResult
    func recordUsage(totalSeconds: Int) -> SharedState {
        var state = store.mutate { state in
            state.ledger = CreditEngine.applyConsumption(totalSeconds: totalSeconds, to: state.ledger)
        }

        if state.ledger.restrictionState == .locked, !state.shieldsApplied {
            shields.apply(selectionStore.load())
            state.shieldsApplied = true
            store.save(state)
        }
        return state
    }

    /// Called at midnight: the day resets to a zero balance, so everything shields again.
    func startNewDay() {
        var state = store.load()          // load() already rolls the ledger over to today
        shields.apply(selectionStore.load())
        state.shieldsApplied = true
        store.save(state)
    }
}
