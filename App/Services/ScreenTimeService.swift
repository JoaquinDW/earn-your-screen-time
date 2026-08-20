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
    /// Applies or removes shields to match the current balance, and refreshes usage thresholds.
    @discardableResult func reconcile() -> SharedState
    /// Forces shields on, regardless of balance (debug / spike).
    func shieldNow()
    /// Forces shields off, regardless of balance (debug / spike).
    func unshieldNow()
    var isMonitoring: Bool { get }
}

/// The real implementation, backed by FamilyControls + ManagedSettings + DeviceActivity.
@MainActor
final class LiveScreenTimeService: ScreenTimeServing {
    private let selectionStore = SelectionStore.shared
    private let coordinator = RestrictionCoordinator.shared
    private let shields = ShieldController.shared
    private let scheduler = MonitorScheduler.shared

    var authorizationStatus: AuthorizationStatus {
        AuthorizationCenter.shared.authorizationStatus
    }

    var selection: FamilyActivitySelection {
        get { selectionStore.load() }
        set {
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

    func shieldNow() {
        shields.apply(selectionStore.load())
        SharedStore.shared.mutate { $0.shieldsApplied = true }
    }

    func unshieldNow() {
        shields.clear()
        SharedStore.shared.mutate { $0.shieldsApplied = false }
    }

    var isMonitoring: Bool { scheduler.isMonitoring }
}

/// Simulator/preview stand-in: remembers what it was told, blocks nothing.
@MainActor
final class MockScreenTimeService: ScreenTimeServing {
    private(set) var status: AuthorizationStatus
    var selection = FamilyActivitySelection()
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
        let state = SharedStore.shared.load()
        shieldsApplied = state.ledger.restrictionState == .locked
        return state
    }

    func shieldNow() { shieldsApplied = true }
    func unshieldNow() { shieldsApplied = false }
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
