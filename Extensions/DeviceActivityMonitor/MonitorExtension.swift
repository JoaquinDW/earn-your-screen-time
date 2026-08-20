import DeviceActivity
import EarnDomain
import Foundation

/// Runs outside the app, so blocking keeps working when Earn Your Screen Time is closed.
///
/// Keep this file cheap: the extension has a very small memory budget and is terminated
/// if it exceeds it. No SwiftData, no networking, no heavy frameworks.
final class MonitorExtension: DeviceActivityMonitor {

    /// Fired when cumulative usage of the restricted apps crosses one of our thresholds.
    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        guard let minute = MonitorPlan.minute(fromEventName: event.rawValue) else { return }
        RestrictionCoordinator.shared.recordUsage(totalSeconds: minute * 60)
    }

    /// Fired at midnight: new day, balance back to zero, apps shielded again.
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        RestrictionCoordinator.shared.startNewDay()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        RestrictionCoordinator.shared.startNewDay()
    }
}
