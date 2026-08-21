import DeviceActivity
import EarnDomain
import Foundation
import OSLog

/// Runs outside the app, so blocking keeps working when Earn Your Screen Time is closed.
///
/// Keep this file cheap: the extension has a very small memory budget and is terminated
/// if it exceeds it. No SwiftData, no networking, no heavy frameworks.
final class MonitorExtension: DeviceActivityMonitor {
    private let logger = Logger(
        subsystem: "com.balthasardeweert.earnyourscreentime",
        category: "DeviceActivityMonitor"
    )

    /// The session was persisted before monitoring starts, so this is safe after app termination.
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        logger.notice("Session interval started: \(activity.rawValue, privacy: .public)")
        RestrictionCoordinator.shared.reconcile(refreshMonitoring: false)
    }

    /// Five- and ten-minute sessions end through the warning of a 15-minute carrier interval.
    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        finishSession(for: activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        finishSession(for: activity)
    }

    private func finishSession(for activity: DeviceActivityName) {
        guard let sessionID = SessionMonitorPlan.sessionID(fromActivityName: activity.rawValue) else {
            logger.error("Ignoring unknown session activity: \(activity.rawValue, privacy: .public)")
            return
        }
        logger.notice("Completing session: \(sessionID.uuidString, privacy: .public)")
        RestrictionCoordinator.shared.completeSession(sessionID: sessionID)
    }
}
