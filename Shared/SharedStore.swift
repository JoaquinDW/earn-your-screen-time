import EarnDomain
import Foundation
import Darwin

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

    private var lockPath: String {
        let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier
        )?.path ?? NSTemporaryDirectory()
        return (directory as NSString).appendingPathComponent("shared.state.lock")
    }

    /// Current state, rolled over to today if the stored ledger belongs to a previous day.
    func load(now: Date = Date()) -> SharedState {
        withExclusiveLock { loadUnlocked(now: now) }
    }

    private func loadUnlocked(now: Date) -> SharedState {
        let today = DayKey(date: now)
        let defaults = defaults
        defaults.synchronize()
        guard
            let data = defaults.data(forKey: Key.state),
            let stored = try? SharedState.decoded(from: data)
        else {
            return SharedState.initial(day: today)
        }

        guard stored.ledger.day != today else { return stored }

        // A session can continue through midnight using the next day's carry-over allowance.
        let boundary = Calendar.current.startOfDay(for: now)
        var settled = ScreenTimeSessionEngine.recoverExpiredSession(in: stored, at: boundary)
        let crossingSession = settled.activeSession(at: boundary)
        if let crossingSession,
           crossingSession.remainingSeconds(at: boundary) <= ScreenTimeWallet.maximumCarryOverSeconds {
            settled = ScreenTimeSessionEngine.settleActiveSessionThrough(in: settled, at: boundary)
        } else if settled.currentSession?.status == .active {
            settled = ScreenTimeSessionEngine.pauseActiveSession(in: settled, at: boundary)
        }
        var rolled = settled
        let finishedDay = DaySummary(ledger: settled.ledger)
        rolled.history.record(finishedDay)
        if let journey = rolled.journey {
            rolled.journey = journey
                .incorporating(finishedDay)
                .finalizing(asOf: today)
        }
        let remaining = settled.ledger.wallet.remainingValueSeconds
        let carried = min(remaining, ScreenTimeWallet.maximumCarryOverSeconds)
        let expired = max(0, remaining - carried)
        rolled.ledger = CreditEngine.rollOverIfNeeded(
            settled.ledger,
            to: today,
            carryOverSeconds: carried
        )
        if let crossingSession,
           crossingSession.remainingSeconds(at: boundary) <= ScreenTimeWallet.maximumCarryOverSeconds {
            let reserved = rolled.ledger.wallet.reserve(
                seconds: crossingSession.remainingSeconds(at: boundary)
            )
            if !reserved {
                rolled.currentSession?.status = .cancelled
                rolled.currentSession?.settledAt = boundary
            }
        }
        if expired > 0 {
            rolled.ledger.walletTransactions.append(WalletTransaction(
                kind: .expired,
                amountSeconds: expired,
                source: .dayRollover,
                date: boundary
            ))
        }
        rolled.schemaVersion = SharedState.currentSchemaVersion
        rolled.shieldsApplied = rolled.activeSession(at: now) == nil
        saveUnlocked(rolled)
        return rolled
    }

    func save(_ state: SharedState) {
        withExclusiveLock { saveUnlocked(state) }
    }

    private func saveUnlocked(_ state: SharedState) {
        guard let data = try? state.encoded() else { return }
        let defaults = defaults
        defaults.set(data, forKey: Key.state)
        defaults.synchronize()
    }

    /// Loads, mutates and persists in one step. Returns the state that was written.
    @discardableResult
    func mutate(now: Date = Date(), _ body: (inout SharedState) -> Void) -> SharedState {
        withExclusiveLock {
            var state = loadUnlocked(now: now)
            body(&state)
            saveUnlocked(state)
            return state
        }
    }

    @discardableResult
    func mutateThrowing(
        now: Date = Date(),
        _ body: (inout SharedState) throws -> Void
    ) rethrows -> SharedState {
        try withExclusiveLock {
            var state = loadUnlocked(now: now)
            try body(&state)
            saveUnlocked(state)
            return state
        }
    }

    func reset() {
        withExclusiveLock { defaults.removeObject(forKey: Key.state) }
    }

    private func withExclusiveLock<T>(_ body: () throws -> T) rethrows -> T {
        let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return try body() }
        flock(descriptor, LOCK_EX)
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        return try body()
    }
}
