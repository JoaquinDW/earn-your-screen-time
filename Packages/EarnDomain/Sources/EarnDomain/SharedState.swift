import Foundation

/// The single source of truth shared between the app and its Screen Time extensions.
///
/// Kept deliberately small and dependency-free: the DeviceActivityMonitor extension runs
/// under a very tight memory budget, so it reads/writes this via App Group `UserDefaults`
/// rather than a database.
public struct SharedState: Codable, Equatable, Sendable {
    /// v13 adds persisted daily session and returned-time progress metrics.
    /// v14 adds the latch for the first reward the user earned by doing something (push-ups or
    /// study), as opposed to steps that HealthKit credited in the background.
    /// v15 adds squats as an earning source and files their minutes separately in day history.
    /// v16 adds jumping jacks and lunges (filed together in day history), the blocking schedule
    /// and strict mode.
    public static let currentSchemaVersion = 16

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
    /// Whether the Pushups to Earn announcement has been shown. Users who onboard after the
    /// feature shipped meet it inside onboarding and start with this already true.
    public var pushupsIntroSeen: Bool
    /// How the optional push-up demo inside onboarding ended. A user who skipped it is offered
    /// the feature again from Home, so this has to outlive the onboarding session.
    public var onboardingPushupDemo: OnboardingPushupDemoOutcome
    public var walletCreatedTracked: Bool
    /// One-shot latches for the activation funnel, so `first_app_blocked` and
    /// `first_real_unlock_completed` fire once per install rather than once per launch.
    public var firstAppBlockedTracked: Bool
    public var firstRealUnlockTracked: Bool
    /// Successful screen-time sessions started, kept across day rollover. Feeds the review-prompt
    /// eligibility check: unlike `firstRealUnlockTracked` this keeps counting past the first one.
    public var successfulUnlockCount: Int
    /// One-shot latch: the native review prompt is requested at most once per install.
    public var reviewPromptRequested: Bool
    /// Someone who has not paid gets one camera exercise reward (push-ups or squats; the persisted
    /// name predates squats). The server enforces it per account;
    /// this local copy only decides whether the app offers the challenge or the paywall.
    public var freePushupsRewardClaimed: Bool
    /// One-shot latch for `first_active_reward_earned`. Step rewards arrive on their own whenever
    /// HealthKit syncs, so they say little about whether someone engaged; this one does.
    public var firstActiveRewardTracked: Bool
    /// Successful reward receipts retained across rollover so a server replay cannot credit twice.
    public private(set) var appliedRewardIDs: [UUID]
    /// When the protected apps are shielded. `nil` is around the clock, as before v16.
    public var blockSchedule: BlockSchedule?
    /// Until when blocking cannot be weakened. `nil`, or a past date, is off.
    public var strictModeUntil: Date?
    public var appliedStudyReceiptIDs: [UUID] { appliedRewardIDs }

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
        pushupsIntroSeen: Bool = false,
        onboardingPushupDemo: OnboardingPushupDemoOutcome = .notAttempted,
        walletCreatedTracked: Bool = false,
        firstAppBlockedTracked: Bool = false,
        firstRealUnlockTracked: Bool = false,
        successfulUnlockCount: Int = 0,
        reviewPromptRequested: Bool = false,
        freePushupsRewardClaimed: Bool = false,
        firstActiveRewardTracked: Bool = false,
        appliedRewardIDs: [UUID] = [],
        appliedStudyReceiptIDs: [UUID] = [],
        blockSchedule: BlockSchedule? = nil,
        strictModeUntil: Date? = nil
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
        self.pushupsIntroSeen = pushupsIntroSeen
        self.onboardingPushupDemo = onboardingPushupDemo
        self.walletCreatedTracked = walletCreatedTracked
        self.firstAppBlockedTracked = firstAppBlockedTracked
        self.firstRealUnlockTracked = firstRealUnlockTracked
        self.successfulUnlockCount = successfulUnlockCount
        self.reviewPromptRequested = reviewPromptRequested
        self.freePushupsRewardClaimed = freePushupsRewardClaimed
        self.firstActiveRewardTracked = firstActiveRewardTracked
        self.appliedRewardIDs = appliedRewardIDs + appliedStudyReceiptIDs.filter { !appliedRewardIDs.contains($0) }
        self.blockSchedule = blockSchedule
        self.strictModeUntil = strictModeUntil
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

    /// Whether today's free unlock has been used: a session settled today, or one started today
    /// that the extension has not settled yet. A ledger left over from an earlier day counts for
    /// nothing, so the allowance returns at midnight even before the app rolls the day over.
    public func hasUsedFreeUnlock(on day: DayKey) -> Bool {
        if ledger.day == day, ledger.sessionCount > 0 { return true }
        guard let currentSession else { return false }
        return DayKey(date: currentSession.startedAt) == day
    }

    /// A free user gets one earned unlock a day, with full access through the earning, the
    /// unlock itself and the session it opened. The paywall follows the proof, never interrupts
    /// it. In 1.3.2 the free allowance was one unlock per install, and of 31 people who finished
    /// onboarding, 3 came back on a later day: there was nothing left to come back for unpaid.
    public func isFreePreviewActive(at date: Date = Date()) -> Bool {
        activeSession(at: date) != nil || !hasUsedFreeUnlock(on: DayKey(date: date))
    }

    // MARK: - Serialization

    /// Decoding is deliberately tolerant of missing keys: a state written by an older build
    /// must keep its ledger. Dropping to `.initial` here would silently wipe the day's balance.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, ledger, onboardingCompleted, onboarding, history
        case restrictedItemCount, lastActivitySyncAt, shieldsApplied, currentSession, journey
        case hasEarnedFirstReward, goalProgressionCooldownUntil, adaptiveIntroSeen, pushupsIntroSeen
        case onboardingPushupDemo
        case walletCreatedTracked, firstAppBlockedTracked, firstRealUnlockTracked
        case successfulUnlockCount, reviewPromptRequested, freePushupsRewardClaimed
        case firstActiveRewardTracked
        case appliedRewardIDs
        case blockSchedule, strictModeUntil
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case appliedStudyReceiptIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
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
        // A state written before v10 belongs to someone who has never seen the announcement.
        pushupsIntroSeen = try container.decodeIfPresent(Bool.self, forKey: .pushupsIntroSeen) ?? false
        // A state written before v11 predates the onboarding demo, so nobody has answered it.
        onboardingPushupDemo = (try? container.decodeIfPresent(
            OnboardingPushupDemoOutcome.self,
            forKey: .onboardingPushupDemo
        )) ?? .notAttempted
        walletCreatedTracked = try container.decodeIfPresent(Bool.self, forKey: .walletCreatedTracked) ?? false
        firstAppBlockedTracked = try container.decodeIfPresent(Bool.self, forKey: .firstAppBlockedTracked) ?? false
        firstRealUnlockTracked = try container.decodeIfPresent(Bool.self, forKey: .firstRealUnlockTracked) ?? false
        // No attempt to backfill this from history: an under-count only delays the review prompt
        // a little for existing installs, while an over-count could fire it too early.
        successfulUnlockCount = try container.decodeIfPresent(Int.self, forKey: .successfulUnlockCount) ?? 0
        reviewPromptRequested = try container.decodeIfPresent(Bool.self, forKey: .reviewPromptRequested) ?? false
        // Not backfilled from history: before this field existed push-ups were Pro-only, and the
        // server refuses a second free reward regardless of what this says.
        freePushupsRewardClaimed = try container.decodeIfPresent(Bool.self, forKey: .freePushupsRewardClaimed) ?? false
        let genericIDs = (try? container.decodeIfPresent([UUID].self, forKey: .appliedRewardIDs)) ?? []
        let v8StudyIDs = (try? legacyContainer.decodeIfPresent([UUID].self, forKey: .appliedStudyReceiptIDs)) ?? []
        appliedRewardIDs = genericIDs + v8StudyIDs.filter { !genericIDs.contains($0) }
        // Every server reward (push-ups or study) leaves a receipt ID, so an install that already
        // has one has already earned actively and must not report a "first" after upgrading.
        firstActiveRewardTracked = try container.decodeIfPresent(Bool.self, forKey: .firstActiveRewardTracked)
            ?? (freePushupsRewardClaimed || !appliedRewardIDs.isEmpty)
        // Before v16 the apps were shielded around the clock with no strict mode. A schedule that
        // no longer decodes falls back to that rather than losing the whole state.
        blockSchedule = try? container.decodeIfPresent(BlockSchedule.self, forKey: .blockSchedule)
        strictModeUntil = try container.decodeIfPresent(Date.self, forKey: .strictModeUntil)

        if decodedSchemaVersion < 6,
           let currentSession,
           currentSession.status == .active,
           ledger.wallet.reservedSeconds == 0 {
            ledger.wallet.migrateLegacyReservation(seconds: currentSession.reservedSeconds)
        }
        if decodedSchemaVersion < 6, currentSession?.status != .active {
            currentSession?.settlementAnalyticsReported = true
        }
        // The activation funnel starts at v11. Someone who already blocked apps or already
        // spent earned minutes must not report a "first" the day they upgrade.
        if decodedSchemaVersion < 11 {
            if restrictedItemCount > 0 { firstAppBlockedTracked = true }
            if currentSession != nil || ledger.wallet.consumedSeconds > 0 { firstRealUnlockTracked = true }
        }
    }

    mutating func recordAppliedReward(_ id: UUID) {
        guard !appliedRewardIDs.contains(id) else { return }
        appliedRewardIDs.append(id)
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
