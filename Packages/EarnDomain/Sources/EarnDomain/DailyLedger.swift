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

    public init(
        day: DayKey,
        rule: EarningRule = .default,
        activityAmount: Int = 0,
        baselineAmount: Int = 0,
        milestonesRewarded: Int = 0,
        wallet: ScreenTimeWallet = ScreenTimeWallet()
    ) {
        self.day = day
        self.rule = rule
        self.activityAmount = max(0, activityAmount)
        self.baselineAmount = max(0, baselineAmount)
        self.milestonesRewarded = max(0, milestonesRewarded)
        self.wallet = wallet
    }

    /// Activity that counts toward the current rule.
    public var qualifyingAmount: Int { max(0, activityAmount - baselineAmount) }

    public var restrictionState: RestrictionState { wallet.restrictionState }
}
