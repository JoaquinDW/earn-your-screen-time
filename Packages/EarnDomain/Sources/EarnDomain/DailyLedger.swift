import Foundation

/// Everything the app knows about a single day: activity, milestones already paid, and balance.
///
/// `baselineAmount` is the key to PRD §16: milestones are counted from the activity level at
/// which the *current* rule started applying, so changing the rule can never retroactively
/// re-award credits for activity that was already paid under the old rule.
public struct DailyLedger: Codable, Equatable, Sendable {
    public var day: DayKey
    public var rule: EarningRule
    /// Latest activity total for the day (e.g. today's step count).
    public var activityAmount: Int
    /// Activity level at which the current rule started counting milestones.
    public var baselineAmount: Int
    /// Milestones already paid since `baselineAmount`.
    public var milestonesRewarded: Int
    public var wallet: ScreenTimeWallet
    /// Optional daily target and one-time reward. Zero disables the bonus.
    public var dailyGoal: Int
    public var goalBonusSeconds: Int
    public var goalBonusAwarded: Bool
    public var transactions: [EarnTransaction]
    public var walletTransactions: [WalletTransaction]
    public var rewardTransactions: [RewardTransaction]

    public init(
        day: DayKey,
        rule: EarningRule = .default,
        activityAmount: Int = 0,
        baselineAmount: Int = 0,
        milestonesRewarded: Int = 0,
        wallet: ScreenTimeWallet = ScreenTimeWallet(),
        dailyGoal: Int = 0,
        goalBonusSeconds: Int = 0,
        goalBonusAwarded: Bool = false,
        transactions: [EarnTransaction] = [],
        walletTransactions: [WalletTransaction] = [],
        rewardTransactions: [RewardTransaction] = []
    ) {
        self.day = day
        self.rule = rule
        self.activityAmount = max(0, activityAmount)
        self.baselineAmount = max(0, baselineAmount)
        self.milestonesRewarded = max(0, milestonesRewarded)
        self.wallet = wallet
        self.dailyGoal = max(0, dailyGoal)
        self.goalBonusSeconds = max(0, goalBonusSeconds)
        self.goalBonusAwarded = goalBonusAwarded
        self.transactions = transactions
        self.walletTransactions = walletTransactions
        self.rewardTransactions = rewardTransactions
    }

    /// Activity that counts toward the current rule.
    public var qualifyingAmount: Int { max(0, activityAmount - baselineAmount) }

    private enum CodingKeys: String, CodingKey {
        case day, rule, activityAmount, baselineAmount, milestonesRewarded, wallet
        case dailyGoal, goalBonusSeconds, goalBonusAwarded, transactions, walletTransactions
        case rewardTransactions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            day: try container.decode(DayKey.self, forKey: .day),
            rule: try container.decodeIfPresent(EarningRule.self, forKey: .rule) ?? .default,
            activityAmount: try container.decodeIfPresent(Int.self, forKey: .activityAmount) ?? 0,
            baselineAmount: try container.decodeIfPresent(Int.self, forKey: .baselineAmount) ?? 0,
            milestonesRewarded: try container.decodeIfPresent(Int.self, forKey: .milestonesRewarded) ?? 0,
            wallet: try container.decodeIfPresent(ScreenTimeWallet.self, forKey: .wallet) ?? ScreenTimeWallet(),
            dailyGoal: try container.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? 0,
            goalBonusSeconds: try container.decodeIfPresent(Int.self, forKey: .goalBonusSeconds) ?? 0,
            goalBonusAwarded: try container.decodeIfPresent(Bool.self, forKey: .goalBonusAwarded) ?? false,
            transactions: try container.decodeIfPresent([EarnTransaction].self, forKey: .transactions) ?? [],
            walletTransactions: try container.decodeIfPresent([WalletTransaction].self, forKey: .walletTransactions) ?? [],
            rewardTransactions: try container.decodeIfPresent([RewardTransaction].self, forKey: .rewardTransactions) ?? []
        )
    }
}

public struct WalletTransaction: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case earned
        case consumed
        case expired
    }

    public enum Source: String, Codable, Sendable {
        case steps
        case study
        case pushups
        case dailyGoalBonus
        case session
        case dayRollover
        case debug

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self = Self(rawValue: try container.decode(String.self)) ?? .debug
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    public let kind: Kind
    public let amountSeconds: Int
    public let source: Source
    public let date: Date
    public let sessionID: UUID?

    public init(kind: Kind, amountSeconds: Int, source: Source, date: Date, sessionID: UUID? = nil) {
        self.kind = kind
        self.amountSeconds = max(0, amountSeconds)
        self.source = source
        self.date = Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
        self.sessionID = sessionID
    }
}

public struct EarnTransaction: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case stepMilestone
        case dailyGoalBonus
    }

    public let kind: Kind
    public let awardedSeconds: Int
    public let activityAmount: Int
    public let milestoneCount: Int

    public init(kind: Kind, awardedSeconds: Int, activityAmount: Int, milestoneCount: Int = 0) {
        self.kind = kind
        self.awardedSeconds = max(0, awardedSeconds)
        self.activityAmount = max(0, activityAmount)
        self.milestoneCount = max(0, milestoneCount)
    }
}
