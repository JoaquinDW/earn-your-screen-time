import EarnDomain
import FamilyControls
import Foundation

enum RestrictionCoordinatorError: LocalizedError {
    case noSelection
    case outsideBlockingHours

    var errorDescription: String? {
        switch self {
        case .noSelection:
            String(localized: "session.error.noSelection")
        case .outsideBlockingHours:
            String(localized: "session.error.outsideBlockingHours")
        }
    }
}

/// The sole decision point for shielded versus temporarily available apps.
struct RestrictionCoordinator {
    static let shared = RestrictionCoordinator()

    private let store = SharedStore.shared
    private let selectionStore = SelectionStore.shared
    private let shields = ShieldController.shared
    private let scheduler = MonitorScheduler.shared

    /// DeviceActivity callbacks land a little either side of a window edge. The schedule and
    /// strict mode are judged this far ahead, so a start callback never finds its window not yet
    /// open and an end callback never finds it still open.
    static let policyLeeway: TimeInterval = 60

    /// Shielded unless an access session is running or the blocking schedule is off right now.
    static func shouldShield(_ state: SharedState, at now: Date, followsSchedule: Bool = true) -> Bool {
        guard state.activeSession(at: now) == nil else { return false }
        return !followsSchedule || state.isWithinBlockingHours(at: now.addingTimeInterval(policyLeeway))
    }

    /// Recovers expired state and makes external restrictions match the persisted session.
    @discardableResult
    func reconcile(
        refreshMonitoring: Bool = true,
        now: Date = Date()
    ) -> SharedState {
        let selection = selectionStore.load()
        var state = store.mutate(now: now) { state in
            state = ScreenTimeSessionEngine.recoverExpiredSession(in: state, at: now)
            state.schemaVersion = SharedState.currentSchemaVersion
            state.restrictedItemCount = selection.itemCount
        }

        // Without the schedule's monitor nothing would put the shields back up when the window
        // opens while Earnit is closed, so a schedule that cannot be monitored is ignored and the
        // apps stay shielded around the clock (fail closed).
        var followsSchedule = true
        if refreshMonitoring {
            do {
                try scheduler.refresh(state: state, selection: selection, now: now)
            } catch {
                // Monitoring is what guarantees re-shielding while Earn is closed. Fail closed.
                state = store.mutate(now: now) { state in
                    state = ScreenTimeSessionEngine.cancelActiveSession(in: state, at: now)
                }
                scheduler.stopAll()
            }
            do {
                try scheduler.refreshPolicy(state: state, now: now)
            } catch {
                followsSchedule = false
            }
        }

        return enforcePolicy(selection: selection, now: now, followsSchedule: followsSchedule)
    }

    /// Makes shields and the strict-mode app-removal lock match the persisted state.
    @discardableResult
    private func enforcePolicy(
        selection: FamilyActivitySelection,
        now: Date,
        followsSchedule: Bool = true
    ) -> SharedState {
        store.mutate(now: now) { latest in
            let shouldShield = Self.shouldShield(latest, at: now, followsSchedule: followsSchedule)
            if shouldShield {
                shields.apply(selection)
            } else {
                shields.clear()
            }
            shields.setAppRemovalDenied(latest.isStrictModeActive(at: now.addingTimeInterval(Self.policyLeeway)))
            latest.shieldsApplied = shouldShield
        }
    }

    /// Reserves credit, persists the session, schedules its end, then removes shields.
    func startSession(
        durationMinutes: Int,
        now: Date = Date()
    ) throws -> SharedState {
        let selection = selectionStore.load()
        guard !selection.isEmpty else { throw RestrictionCoordinatorError.noSelection }
        // Outside blocking hours the apps are already open; a session would only spend minutes.
        guard store.load(now: now).isWithinBlockingHours(at: now.addingTimeInterval(Self.policyLeeway)) else {
            throw RestrictionCoordinatorError.outsideBlockingHours
        }

        var sessionState = try store.mutateThrowing(now: now) { state in
            state = ScreenTimeSessionEngine.recoverExpiredSession(in: state, at: now)
            state = try ScreenTimeSessionEngine.start(
                durationMinutes: durationMinutes,
                at: now,
                in: state
            )
            state.schemaVersion = SharedState.currentSchemaVersion
            state.restrictedItemCount = selection.itemCount
            state.shieldsApplied = true
        }

        do {
            try scheduler.refresh(state: sessionState, selection: selection, now: now)
        } catch {
            scheduler.stopAll()
            shields.apply(selection)
            _ = store.mutate(now: now) { state in
                guard state.currentSession?.id == sessionState.currentSession?.id else { return }
                state = ScreenTimeSessionEngine.cancelActiveSession(in: state, at: now)
                state.shieldsApplied = true
            }
            throw error
        }

        sessionState = store.mutate(now: now) { state in
            if state.currentSession?.id == sessionState.currentSession?.id,
               state.currentSession?.status == .active {
                shields.clear()
                state.shieldsApplied = false
            } else {
                shields.apply(selection)
                state.shieldsApplied = true
            }
        }
        return sessionState
    }

    /// Called by the monitor warning/end callbacks. A stale callback cannot finish a newer session.
    @discardableResult
    func completeSession(sessionID: UUID, now: Date = Date()) -> SharedState {
        var didComplete = false
        let state = store.mutate(now: now) { state in
            guard state.currentSession?.id == sessionID,
                  state.currentSession?.status == .active else { return }
            state = ScreenTimeSessionEngine.complete(sessionID: sessionID, in: state, at: now)
            state.shieldsApplied = true
            didComplete = true
        }
        guard didComplete else {
            if state.shieldsApplied {
                scheduler.stop(sessionID: sessionID)
                return enforcePolicy(selection: selectionStore.load(), now: now)
            }
            return state
        }
        scheduler.stop(sessionID: sessionID)
        return enforcePolicy(selection: selectionStore.load(), now: now)
    }

    /// Ends access and returns the unused reservation to the wallet.
    @discardableResult
    func cancelActiveSession(now: Date = Date()) -> SharedState {
        let selection = selectionStore.load()
        shields.apply(selection)
        store.mutate(now: now) { state in
            state = ScreenTimeSessionEngine.cancelActiveSession(in: state, at: now)
            state.shieldsApplied = true
        }
        scheduler.stopAll()
        return enforcePolicy(selection: selection, now: now)
    }

    /// User-initiated stop. Shields are restored before accounting is settled (fail closed).
    @discardableResult
    func pauseActiveSession(now: Date = Date()) -> SharedState {
        let selection = selectionStore.load()
        shields.apply(selection)
        store.mutate(now: now) { state in
            state = ScreenTimeSessionEngine.pauseActiveSession(in: state, at: now)
            state.shieldsApplied = true
        }
        scheduler.stopAll()
        return enforcePolicy(selection: selection, now: now)
    }

    /// Debug reset that also removes every external side effect from the previous state.
    @discardableResult
    func resetToday() -> SharedState {
        scheduler.stopAll()
        store.reset()
        let selection = selectionStore.load()
        shields.apply(selection)
        return store.mutate { state in
            state.restrictedItemCount = selection.itemCount
            state.shieldsApplied = true
        }
    }
}
