import EarnDomain
import FamilyControls
import Foundation

enum RestrictionCoordinatorError: LocalizedError {
    case noSelection

    var errorDescription: String? {
        switch self {
        case .noSelection:
            String(localized: "session.error.noSelection")
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
        }

        state = store.mutate(now: now) { latest in
            let shouldShield = latest.activeSession(at: now) == nil
            if shouldShield {
                shields.apply(selection)
            } else {
                shields.clear()
            }
            latest.shieldsApplied = shouldShield
        }
        return state
    }

    /// Reserves credit, persists the session, schedules its end, then removes shields.
    func startSession(
        durationMinutes: Int,
        now: Date = Date()
    ) throws -> SharedState {
        let selection = selectionStore.load()
        guard !selection.isEmpty else { throw RestrictionCoordinatorError.noSelection }

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
                shields.apply(selectionStore.load())
                scheduler.stop(sessionID: sessionID)
            }
            return state
        }
        shields.apply(selectionStore.load())
        scheduler.stop(sessionID: sessionID)
        return state
    }

    /// Ends access and returns the unused reservation to the wallet.
    @discardableResult
    func cancelActiveSession(now: Date = Date()) -> SharedState {
        let selection = selectionStore.load()
        shields.apply(selection)
        let state = store.mutate(now: now) { state in
            state = ScreenTimeSessionEngine.cancelActiveSession(in: state, at: now)
            state.shieldsApplied = true
        }
        scheduler.stopAll()
        return state
    }

    /// User-initiated stop. Shields are restored before accounting is settled (fail closed).
    @discardableResult
    func pauseActiveSession(now: Date = Date()) -> SharedState {
        let selection = selectionStore.load()
        shields.apply(selection)
        let state = store.mutate(now: now) { state in
            state = ScreenTimeSessionEngine.pauseActiveSession(in: state, at: now)
            state.shieldsApplied = true
        }
        scheduler.stopAll()
        return state
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
