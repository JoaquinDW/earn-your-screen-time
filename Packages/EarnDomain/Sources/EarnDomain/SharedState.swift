import Foundation

/// The single source of truth shared between the app and its Screen Time extensions.
///
/// Kept deliberately small and dependency-free: the DeviceActivityMonitor extension runs
/// under a very tight memory budget, so it reads/writes this via App Group `UserDefaults`
/// rather than a database.
public struct SharedState: Codable, Equatable, Sendable {
    /// v6 adds persistent carry-over, refundable reservations, and wallet transactions.
    public static let currentSchemaVersion = 6

    public var schemaVersion: Int
    public var ledger: DailyLedger
    public var onboardingCompleted: Bool
    /// What the user answered during onboarding. Drives the daily step goal and the projection.
    public var onboarding: OnboardingProfile
    /// Finished days, for the streak and the week chart.
    public var history: ActivityHistory
    /// Number of apps/categories the user chose to restrict (tokens themselves are opaque
    /// and live in a separate, FamilyControls-encoded blob).
    public var restrictedItemCount: Int
    /// Last time the app successfully refreshed activity data.
    public var lastActivitySyncAt: Date?
    /// Whether shields are currently believed to be applied.
    public var shieldsApplied: Bool
    /// The latest access session. Only an active, unexpired session may remove shields.
    public var currentSession: ScreenTimeSession?
    public var journey: ThirtyDayJourney?
    public var hasEarnedFirstReward: Bool
    public var goalProgressionCooldownUntil: DayKey?
    public var adaptiveIntroSeen: Bool
    public var walletCreatedTracked: Bool

    public init(
        schemaVersion: Int = SharedState.currentSchemaVersion,
        ledger: DailyLedger,
        onboardingCompleted: Bool = false,
        onboarding: OnboardingProfile = OnboardingProfile(),
        history: ActivityHistory = ActivityHistory(),
        restrictedItemCount: Int = 0,
        lastActivitySyncAt: Date? = nil,
        shieldsApplied: Bool = true,
        currentSession: ScreenTimeSession? = nil,
        journey: ThirtyDayJourney? = nil,
        hasEarnedFirstReward: Bool = false,
        goalProgressionCooldownUntil: DayKey? = nil,
        adaptiveIntroSeen: Bool = false,
        walletCreatedTracked: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.ledger = ledger
        self.onboardingCompleted = onboardingCompleted
        self.onboarding = onboarding
        self.history = history
        self.restrictedItemCount = restrictedItemCount
        self.lastActivitySyncAt = lastActivitySyncAt
        self.shieldsApplied = shieldsApplied
        self.currentSession = currentSession
        self.journey = journey
        self.hasEarnedFirstReward = hasEarnedFirstReward
        self.goalProgressionCooldownUntil = goalProgressionCooldownUntil
        self.adaptiveIntroSeen = adaptiveIntroSeen
        self.walletCreatedTracked = walletCreatedTracked
    }

    public static func initial(day: DayKey = .today(), rule: EarningRule = .default) -> SharedState {
        SharedState(ledger: CreditEngine.startOfDay(day, rule: rule))
    }

    public var hasRestrictedApps: Bool { restrictedItemCount > 0 }

    public func activeSession(at date: Date = Date()) -> ScreenTimeSession? {
        guard let currentSession, currentSession.isActive(at: date) else { return nil }
        return currentSession
    }

    /// Steps a day the user is aiming for.
    public var dailyStepGoal: Int { onboarding.dailyStepGoal }

    // MARK: - Serialization

    /// Decoding is deliberately tolerant of missing keys: a state written by an older build
    /// must keep its ledger. Dropping to `.initial` here would silently wipe the day's balance.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, ledger, onboardingCompleted, onboarding, history
        case restrictedItemCount, lastActivitySyncAt, shieldsApplied, currentSession, journey
        case hasEarnedFirstReward, goalProgressionCooldownUntil, adaptiveIntroSeen, walletCreatedTracked
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        schemaVersion = SharedState.currentSchemaVersion
        ledger = try container.decode(DailyLedger.self, forKey: .ledger)
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        onboarding = try container.decodeIfPresent(OnboardingProfile.self, forKey: .onboarding) ?? OnboardingProfile()
        history = try container.decodeIfPresent(ActivityHistory.self, forKey: .history) ?? ActivityHistory()
        restrictedItemCount = try container.decodeIfPresent(Int.self, forKey: .restrictedItemCount) ?? 0
        lastActivitySyncAt = try container.decodeIfPresent(Date.self, forKey: .lastActivitySyncAt)
        shieldsApplied = try container.decodeIfPresent(Bool.self, forKey: .shieldsApplied) ?? true
        currentSession = try container.decodeIfPresent(ScreenTimeSession.self, forKey: .currentSession)
        journey = try container.decodeIfPresent(ThirtyDayJourney.self, forKey: .journey)
        hasEarnedFirstReward = try container.decodeIfPresent(Bool.self, forKey: .hasEarnedFirstReward) ?? false
        goalProgressionCooldownUntil = try container.decodeIfPresent(DayKey.self, forKey: .goalProgressionCooldownUntil)
        adaptiveIntroSeen = try container.decodeIfPresent(Bool.self, forKey: .adaptiveIntroSeen) ?? false
        walletCreatedTracked = try container.decodeIfPresent(Bool.self, forKey: .walletCreatedTracked) ?? false

        if decodedSchemaVersion < 6,
           let currentSession,
           currentSession.status == .active,
           ledger.wallet.reservedSeconds == 0 {
            ledger.wallet.migrateLegacyReservation(seconds: currentSession.reservedSeconds)
        }
        if decodedSchemaVersion < 6, currentSession?.status != .active {
            currentSession?.settlementAnalyticsReported = true
        }
    }

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
