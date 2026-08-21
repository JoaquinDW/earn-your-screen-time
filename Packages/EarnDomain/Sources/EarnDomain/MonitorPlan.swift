import Foundation

/// DeviceActivity-independent plan for carrying a short access session in Apple's minimum
/// 15-minute schedule. Five- and ten-minute sessions finish through the end-warning callback.
public enum SessionMonitorPlan {
    public static let activityPrefix = "accessSession_"
    public static let carrierSeconds = 15 * 60

    public struct Plan: Equatable, Sendable {
        public let sessionID: UUID
        public let activityName: String
        public let remainingSeconds: Int
        /// Seconds before the carrier interval ends. `nil` means completion at interval end.
        public let warningSeconds: Int?
    }

    public static func make(
        for session: ScreenTimeSession,
        at date: Date
    ) -> Plan? {
        let remaining = min(carrierSeconds, session.remainingSeconds(at: date))
        guard remaining > 0 else { return nil }
        let warning = carrierSeconds - remaining
        return Plan(
            sessionID: session.id,
            activityName: activityName(for: session.id),
            remainingSeconds: remaining,
            warningSeconds: warning > 0 ? warning : nil
        )
    }

    public static func activityName(for sessionID: UUID) -> String {
        activityPrefix + sessionID.uuidString.lowercased()
    }

    public static func sessionID(fromActivityName name: String) -> UUID? {
        guard name.hasPrefix(activityPrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(activityPrefix.count)))
    }
}
