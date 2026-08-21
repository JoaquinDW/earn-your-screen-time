import EarnDomain
import Foundation

/// The state shared between the app and its extensions, stored in App Group `UserDefaults`.
///
/// Deliberately not a database: `DeviceActivityMonitorExtension` runs under a very small
/// memory budget, so it must be able to read and write this cheaply.
///
/// Concurrency note: session status only moves from active to completed/cancelled. Every writer
/// loads the latest blob before applying that monotonic transition.
struct SharedStore {
    static let shared = SharedStore()

    private enum Key {
        static let state = "shared.state.v1"
    }

    private var defaults: UserDefaults { AppGroup.defaults }

    /// Current state, rolled over to today if the stored ledger belongs to a previous day.
    func load(now: Date = Date()) -> SharedState {
        let today = DayKey(date: now)
        guard
            let data = defaults.data(forKey: Key.state),
            let stored = try? SharedState.decoded(from: data)
        else {
            return SharedState.initial(day: today)
        }

        guard stored.ledger.day != today else { return stored }

        // New calendar day: file the day that just ended, then reset the ledger.
        // MVP has no carry-over (PRD §17).
        var rolled = stored
        let finishedDay = DaySummary(ledger: stored.ledger)
        rolled.history.record(finishedDay)
        if let journey = rolled.journey {
            rolled.journey = journey
                .incorporating(finishedDay)
                .finalizing(asOf: today)
        }
        rolled.ledger = CreditEngine.rollOverIfNeeded(stored.ledger, to: today)
        rolled.currentSession = stored.currentSession.map { session in
            var cancelled = session
            if cancelled.status == .active { cancelled.status = .cancelled }
            return cancelled
        }
        rolled.schemaVersion = SharedState.currentSchemaVersion
        rolled.shieldsApplied = true
        return rolled
    }

    func save(_ state: SharedState) {
        guard let data = try? state.encoded() else { return }
        defaults.set(data, forKey: Key.state)
    }

    /// Loads, mutates and persists in one step. Returns the state that was written.
    @discardableResult
    func mutate(now: Date = Date(), _ body: (inout SharedState) -> Void) -> SharedState {
        var state = load(now: now)
        body(&state)
        save(state)
        return state
    }

    func reset() {
        defaults.removeObject(forKey: Key.state)
    }
}
