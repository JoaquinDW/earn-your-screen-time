import EarnDomain
import FamilyControls
import Foundation

/// Everything the app needs from Apple's Screen Time frameworks.
///
/// It is a protocol so the UI can run in the Simulator and in previews, where FamilyControls
/// authorization always fails and shields do not exist.
@MainActor
protocol ScreenTimeServing: AnyObject {
    var authorizationStatus: AuthorizationStatus { get }
    var selection: FamilyActivitySelection { get set }

    func requestAuthorization() async throws
    /// Applies or removes shields to match the current explicit access session.
    @discardableResult func reconcile() -> SharedState
    @discardableResult func startSession(durationMinutes: Int) throws -> SharedState
    @discardableResult func pauseSession() -> SharedState
    @discardableResult func resetToday() -> SharedState
    var isMonitoring: Bool { get }
}

/// The real implementation, backed by FamilyControls + ManagedSettings + DeviceActivity.
@MainActor
final class LiveScreenTimeService: ScreenTimeServing {
    private let selectionStore = SelectionStore.shared
    private let coordinator = RestrictionCoordinator.shared
    private let scheduler = MonitorScheduler.shared

    var authorizationStatus: AuthorizationStatus {
        AuthorizationCenter.shared.authorizationStatus
    }

    var selection: FamilyActivitySelection {
        get { selectionStore.load() }
        set {
            coordinator.cancelActiveSession()
            selectionStore.save(newValue)
            reconcile()
        }
    }

    /// Asks the user for Screen Time access for their own device (`.individual`).
    /// Throws `FamilyControlsError` when denied, unavailable, or run in the Simulator.
    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    @discardableResult
    func reconcile() -> SharedState {
        coordinator.reconcile()
    }

    @discardableResult
    func startSession(durationMinutes: Int) throws -> SharedState {
        try coordinator.startSession(durationMinutes: durationMinutes)
    }

    @discardableResult
    func pauseSession() -> SharedState {
        coordinator.pauseActiveSession()
    }

    @discardableResult
    func resetToday() -> SharedState {
        coordinator.resetToday()
    }

    var isMonitoring: Bool { scheduler.isMonitoring }
}

/// Simulator/preview stand-in: remembers what it was told, blocks nothing.
@MainActor
final class MockScreenTimeService: ScreenTimeServing {
    private(set) var status: AuthorizationStatus
    var selection = FamilyActivitySelection() {
        didSet {
            SharedStore.shared.mutate { state in
                state = ScreenTimeSessionEngine.cancelActiveSession(in: state)
            }
            _ = reconcile()
        }
    }
    private(set) var shieldsApplied = true

    init(status: AuthorizationStatus = .notDetermined) {
        self.status = status
    }

    var authorizationStatus: AuthorizationStatus { status }

    func requestAuthorization() async throws {
        try? await Task.sleep(for: .milliseconds(400))
        status = .approved
    }

    @discardableResult
    func reconcile() -> SharedState {
        // Mirrors the live service: reconciling persists the resulting state, so the
        // Simulator exercises the same read/write path the device uses.
        SharedStore.shared.mutate { state in
            state.restrictedItemCount = selection.itemCount
            state = ScreenTimeSessionEngine.recoverExpiredSession(in: state, at: Date())
            shieldsApplied = state.activeSession() == nil || selection.isEmpty
            state.shieldsApplied = shieldsApplied
        }
    }

    @discardableResult
    func startSession(durationMinutes: Int) throws -> SharedState {
        guard !selection.isEmpty else { throw RestrictionCoordinatorError.noSelection }
        return try SharedStore.shared.mutateThrowing { state in
            state = try ScreenTimeSessionEngine.start(
                durationMinutes: durationMinutes,
                at: Date(),
                in: state
            )
            shieldsApplied = false
            state.shieldsApplied = false
        }
    }

    @discardableResult
    func pauseSession() -> SharedState {
        SharedStore.shared.mutate { state in
            state = ScreenTimeSessionEngine.pauseActiveSession(in: state, at: Date())
            shieldsApplied = true
            state.shieldsApplied = true
        }
    }

    @discardableResult
    func resetToday() -> SharedState {
        SharedStore.shared.reset()
        shieldsApplied = true
        return reconcile()
    }

    var isMonitoring: Bool { false }
}

extension AuthorizationStatus {
    /// Treats every "granted" variant as approved.
    ///
    /// iOS keeps adding approval flavours (iOS 26 introduced `.approvedWithDataAccess`), so this
    /// is written as "not explicitly refused or pending" instead of matching a fixed list of cases.
    var isApproved: Bool {
        self != .notDetermined && self != .denied
    }
}
