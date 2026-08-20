import Foundation

/// The single source of truth shared between the app and its Screen Time extensions.
///
/// Kept deliberately small and dependency-free: the DeviceActivityMonitor extension runs
/// under a very tight memory budget, so it reads/writes this via App Group `UserDefaults`
/// rather than a database.
public struct SharedState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var ledger: DailyLedger
    public var onboardingCompleted: Bool
    /// Number of apps/categories the user chose to restrict (tokens themselves are opaque
    /// and live in a separate, FamilyControls-encoded blob).
    public var restrictedItemCount: Int
    /// Last time the app successfully refreshed activity data.
    public var lastActivitySyncAt: Date?
    /// Whether shields are currently believed to be applied.
    public var shieldsApplied: Bool

    public init(
        schemaVersion: Int = SharedState.currentSchemaVersion,
        ledger: DailyLedger,
        onboardingCompleted: Bool = false,
        restrictedItemCount: Int = 0,
        lastActivitySyncAt: Date? = nil,
        shieldsApplied: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.ledger = ledger
        self.onboardingCompleted = onboardingCompleted
        self.restrictedItemCount = restrictedItemCount
        self.lastActivitySyncAt = lastActivitySyncAt
        self.shieldsApplied = shieldsApplied
    }

    public static func initial(day: DayKey = .today(), rule: EarningRule = .default) -> SharedState {
        SharedState(ledger: CreditEngine.startOfDay(day, rule: rule))
    }

    public var hasRestrictedApps: Bool { restrictedItemCount > 0 }

    // MARK: - Serialization

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> SharedState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SharedState.self, from: data)
    }
}
