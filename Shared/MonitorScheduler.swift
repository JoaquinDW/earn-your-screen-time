import DeviceActivity
import EarnDomain
import FamilyControls
import Foundation

/// Registers the DeviceActivity thresholds that measure real usage of the restricted apps.
///
/// ## Why thresholds are cumulative from midnight
///
/// The schedule covers the whole day and every event is created with
/// `includesPastActivity: true`, so a threshold of *N minutes* means "N minutes of restricted-app
/// usage since midnight". That matters because monitoring has to be restarted every time the user
/// earns more credits, and restarting resets relative counters — cumulative thresholds survive it.
///
/// The last threshold equals the total minutes earned today, so it fires exactly when the balance
/// hits zero. The earlier ones only keep the displayed balance roughly in sync.
struct MonitorScheduler {
    static let shared = MonitorScheduler()

    static let activityName = DeviceActivityName("earnYourScreenTimeDaily")

    private var center: DeviceActivityCenter { DeviceActivityCenter() }

    /// A full day, which also gives us a midnight `intervalDidStart` callback for the daily reset.
    /// (DeviceActivity requires intervals of at least 15 minutes.)
    private var dailySchedule: DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
    }

    /// Restarts monitoring so the thresholds match the current balance.
    /// Call this every time credits are earned or the app selection changes.
    func refresh(state: SharedState, selection: FamilyActivitySelection) throws {
        stop()
        guard !selection.isEmpty else { return }

        let thresholds = MonitorPlan.thresholds(totalEarnedSeconds: state.ledger.wallet.earnedSeconds)
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for threshold in thresholds {
            events[DeviceActivityEvent.Name(threshold.eventName)] = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: threshold.minute),
                includesPastActivity: true
            )
        }

        try center.startMonitoring(Self.activityName, during: dailySchedule, events: events)
    }

    func stop() {
        center.stopMonitoring([Self.activityName])
    }

    var isMonitoring: Bool {
        center.activities.contains(Self.activityName)
    }
}
