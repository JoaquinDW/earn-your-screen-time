import EarnDomain
import Foundation

/// The state shared between the app and its extensions, stored in App Group `UserDefaults`.
///
/// Deliberately not a database: `DeviceActivityMonitorExtension` runs under a very small
/// memory budget, so it must be able to read and write this cheaply.
///
/// Concurrency note: the app and the monitor extension are rarely alive at the same time, and
/// the only field the extension writes (`consumedSeconds`) only ever moves forward, so a lost
/// update converges on the next event instead of corrupting the balance.
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

        // New calendar day: reset the ledger. MVP has no carry-over (PRD §17).
        var rolled = stored
        rolled.ledger = CreditEngine.rollOverIfNeeded(stored.ledger, to: today)
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
