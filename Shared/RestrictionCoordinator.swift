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
        var state = ScreenTimeSessionEngine.recoverExpiredSession(
            in: store.load(now: now),
            at: now
        )
        state.schemaVersion = SharedState.currentSchemaVersion
        state.restrictedItemCount = selection.itemCount

        if selection.isEmpty, state.activeSession(at: now) != nil {
            state = ScreenTimeSessionEngine.cancelActiveSession(in: state)
        }

        if refreshMonitoring {
            do {
                try scheduler.refresh(state: state, selection: selection, now: now)
            } catch {
                // Monitoring is what guarantees re-shielding while Earn is closed. Fail closed.
                state = ScreenTimeSessionEngine.cancelActiveSession(in: state)
                scheduler.stopAll()
            }
        }

        let shouldShield = state.activeSession(at: now) == nil || selection.isEmpty
        if shouldShield {
            shields.apply(selection)
        } else {
            shields.clear()
        }
        state.shieldsApplied = shouldShield
        store.save(state)
        return state
    }

    /// Reserves credit, persists the session, schedules its end, then removes shields.
    func startSession(
        durationMinutes: Int,
        now: Date = Date()
    ) throws -> SharedState {
        let selection = selectionStore.load()
        guard !selection.isEmpty else { throw RestrictionCoordinatorError.noSelection }

        let base = ScreenTimeSessionEngine.recoverExpiredSession(
            in: store.load(now: now),
            at: now
        )
        var sessionState = try ScreenTimeSessionEngine.start(
            durationMinutes: durationMinutes,
            at: now,
            in: base
        )
        sessionState.schemaVersion = SharedState.currentSchemaVersion
        sessionState.restrictedItemCount = selection.itemCount
        sessionState.shieldsApplied = true
        store.save(sessionState)

        do {
            try scheduler.refresh(state: sessionState, selection: selection, now: now)
        } catch {
            scheduler.stopAll()
            shields.apply(selection)
            var rolledBack = base
            rolledBack.shieldsApplied = true
            store.save(rolledBack)
            throw error
        }

        shields.clear()
        sessionState.shieldsApplied = false
        store.save(sessionState)
        return sessionState
    }

    /// Called by the monitor warning/end callbacks. A stale callback cannot finish a newer session.
    @discardableResult
    func completeSession(sessionID: UUID) -> SharedState {
        let current = store.load()
        guard current.currentSession?.id == sessionID,
              current.currentSession?.status == .active else {
            return current
        }

        var state = ScreenTimeSessionEngine.complete(sessionID: sessionID, in: current)
        shields.apply(selectionStore.load())
        state.shieldsApplied = true
        store.save(state)
        scheduler.stop(sessionID: sessionID)
        return state
    }

    /// Ends access without refunding already reserved time.
    @discardableResult
    func cancelActiveSession() -> SharedState {
        var state = ScreenTimeSessionEngine.cancelActiveSession(in: store.load())
        scheduler.stopAll()
        shields.apply(selectionStore.load())
        state.shieldsApplied = true
        store.save(state)
        return state
    }

    /// Debug reset that also removes every external side effect from the previous state.
    @discardableResult
    func resetToday() -> SharedState {
        scheduler.stopAll()
        store.reset()
        let selection = selectionStore.load()
        shields.apply(selection)
        var state = store.load()
        state.restrictedItemCount = selection.itemCount
        state.shieldsApplied = true
        store.save(state)
        return state
    }
}
