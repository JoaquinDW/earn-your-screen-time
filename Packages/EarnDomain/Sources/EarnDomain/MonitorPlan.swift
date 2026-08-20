import Foundation

/// The set of usage thresholds to register with DeviceActivity for a given balance.
///
/// Thresholds are **cumulative restricted-app usage since midnight**, which is what lets the
/// app restart monitoring (every time credits are earned) without losing the usage already
/// accumulated — see docs/ARQUITECTURA.md.
public enum MonitorPlan {

    public struct Threshold: Equatable, Sendable {
        /// Cumulative minutes of restricted-app usage at which this event fires.
        public let minute: Int
        /// `true` for the final event: the balance is spent and shields must be applied.
        public let isExhaustion: Bool

        public var eventName: String { MonitorPlan.eventName(forMinute: minute) }
    }

    /// Registering too many events per activity is untested territory on Apple's side; keep it modest.
    public static let defaultMaxEvents = 20
    public static let eventPrefix = "tick_"

    public static func eventName(forMinute minute: Int) -> String { "\(eventPrefix)\(minute)" }

    /// Recovers the cumulative-minute value encoded in an event name.
    public static func minute(fromEventName name: String) -> Int? {
        guard name.hasPrefix(eventPrefix) else { return nil }
        return Int(name.dropFirst(eventPrefix.count))
    }

    /// Builds the thresholds for a wallet that has earned `totalEarnedSeconds` today.
    ///
    /// Intermediate ticks exist only to keep the displayed balance roughly live; the last
    /// threshold is the one that re-applies the shields.
    public static func thresholds(totalEarnedSeconds: Int, maxEvents: Int = defaultMaxEvents) -> [Threshold] {
        let totalMinutes = max(0, totalEarnedSeconds) / 60
        guard totalMinutes > 0, maxEvents > 0 else { return [] }

        let granularity = max(1, Int((Double(totalMinutes) / Double(maxEvents)).rounded(.up)))
        var result: [Threshold] = []
        var minute = granularity
        while minute < totalMinutes {
            result.append(Threshold(minute: minute, isExhaustion: false))
            minute += granularity
        }
        result.append(Threshold(minute: totalMinutes, isExhaustion: true))
        return result
    }
}
