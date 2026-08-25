import Foundation

/// How much more activity is needed for the next reward.
public struct NextMilestone: Equatable, Sendable {
    /// Activity total the user must reach (e.g. 4_000 steps).
    public let targetAmount: Int
    /// How much is still missing (0 once reached).
    public let remainingAmount: Int
    /// Seconds that will be granted on arrival.
    public let rewardSeconds: Int

    public var rewardMinutes: Int { rewardSeconds / 60 }
}

/// Turns activity into screen-time credits. Pure logic — no HealthKit, no Screen Time, no I/O.
public enum CreditEngine {

    public struct Outcome: Equatable, Sendable {
        public let ledger: DailyLedger
        public let awardedSeconds: Int
        public let awardedMilestones: Int
        public let awardedStepSeconds: Int
        public let awardedGoalBonusSeconds: Int
        public let uncreditedSeconds: Int
        public let didReachWalletCapacity: Bool

        public var didAward: Bool { awardedSeconds > 0 }
        public var didAwardSteps: Bool { awardedStepSeconds > 0 }
        public var didAwardGoalBonus: Bool { awardedGoalBonusSeconds > 0 }
    }

    /// Applies a new activity reading, awarding credits for any milestone crossed for the first time.
    ///
    /// Safe to call repeatedly with the same or lower readings: credits are awarded exactly once
    /// per milestone (PRD §9).
    public static func apply(activityAmount: Int, to ledger: DailyLedger, at date: Date = Date()) -> Outcome {
        var updated = ledger
        // Activity totals for a day only ever grow; ignore transient lower readings.
        let previousActivity = ledger.activityAmount
        updated.activityAmount = max(ledger.activityAmount, max(0, activityAmount))

        let reachable = updated.qualifyingAmount / updated.rule.amountRequired
        let newMilestones = max(0, reachable - updated.milestonesRewarded)
        let requestedStepSeconds = newMilestones * updated.rule.rewardSeconds
        var stepSeconds = 0
        if newMilestones > 0 {
            updated.milestonesRewarded += newMilestones
            stepSeconds = updated.wallet.credit(seconds: requestedStepSeconds)
            updated.transactions.append(EarnTransaction(
                kind: .stepMilestone,
                awardedSeconds: stepSeconds,
                activityAmount: updated.activityAmount,
                milestoneCount: newMilestones
            ))
            if stepSeconds > 0 {
                updated.walletTransactions.append(WalletTransaction(
                    kind: .earned,
                    amountSeconds: stepSeconds,
                    source: .steps,
                    date: date
                ))
            }
        }

        let crossedGoal = updated.dailyGoal > 0
            && previousActivity < updated.dailyGoal
            && updated.activityAmount >= updated.dailyGoal
        let requestedBonusSeconds = crossedGoal && !updated.goalBonusAwarded ? updated.goalBonusSeconds : 0
        var bonusSeconds = 0
        if crossedGoal && !updated.goalBonusAwarded {
            updated.goalBonusAwarded = true
            bonusSeconds = updated.wallet.credit(seconds: requestedBonusSeconds)
            if bonusSeconds > 0 {
                updated.transactions.append(EarnTransaction(
                    kind: .dailyGoalBonus,
                    awardedSeconds: bonusSeconds,
                    activityAmount: updated.activityAmount
                ))
                updated.walletTransactions.append(WalletTransaction(
                    kind: .earned,
                    amountSeconds: bonusSeconds,
                    source: .dailyGoalBonus,
                    date: date
                ))
            }
        }

        let uncreditedSeconds = max(
            0,
            requestedStepSeconds + requestedBonusSeconds - stepSeconds - bonusSeconds
        )
        return Outcome(
            ledger: updated,
            awardedSeconds: stepSeconds + bonusSeconds,
            awardedMilestones: newMilestones,
            awardedStepSeconds: stepSeconds,
            awardedGoalBonusSeconds: bonusSeconds,
            uncreditedSeconds: uncreditedSeconds,
            didReachWalletCapacity: uncreditedSeconds > 0
                || (!ledger.wallet.isAtCapacity && updated.wallet.isAtCapacity)
        )
    }

    /// Switches to a new earning rule without re-awarding anything already paid.
    ///
    /// The new rule starts counting from the current activity level, so only *future*
    /// activity produces milestones (PRD §16).
    public static func changeRule(to newRule: EarningRule, in ledger: DailyLedger) -> DailyLedger {
        guard newRule != ledger.rule else { return ledger }
        var updated = ledger
        updated.rule = newRule
        updated.baselineAmount = updated.activityAmount
        updated.milestonesRewarded = 0
        return updated
    }

    public static func nextMilestone(in ledger: DailyLedger) -> NextMilestone {
        let target = ledger.baselineAmount + (ledger.milestonesRewarded + 1) * ledger.rule.amountRequired
        return NextMilestone(
            targetAmount: target,
            remainingAmount: max(0, target - ledger.activityAmount),
            rewardSeconds: ledger.rule.rewardSeconds
        )
    }

    /// Builds the ledger for a new calendar day.
    ///
    /// A new day keeps at most twenty minutes, while daily earning and consumption restart at zero.
    public static func startOfDay(
        _ day: DayKey,
        rule: EarningRule,
        carryOverSeconds: Int = 0,
        dailyGoal: Int = 0,
        goalBonusSeconds: Int = 0
    ) -> DailyLedger {
        DailyLedger(
            day: day,
            rule: rule,
            activityAmount: 0,
            baselineAmount: 0,
            milestonesRewarded: 0,
            wallet: ScreenTimeWallet(
                carriedSeconds: min(max(0, carryOverSeconds), ScreenTimeWallet.maximumCarryOverSeconds)
            ),
            dailyGoal: dailyGoal,
            goalBonusSeconds: goalBonusSeconds
        )
    }

    /// Returns a ledger valid for `day`, rolling over if the stored one belongs to an earlier day.
    public static func rollOverIfNeeded(
        _ ledger: DailyLedger,
        to day: DayKey,
        carryOverSeconds: Int? = nil,
        dailyGoal: Int? = nil,
        goalBonusSeconds: Int? = nil
    ) -> DailyLedger {
        guard ledger.day != day else { return ledger }
        return startOfDay(
            day,
            rule: ledger.rule,
            carryOverSeconds: carryOverSeconds
                ?? min(ledger.availableAfterSettlingReservation, ScreenTimeWallet.maximumCarryOverSeconds),
            dailyGoal: dailyGoal ?? ledger.dailyGoal,
            goalBonusSeconds: goalBonusSeconds ?? ledger.goalBonusSeconds
        )
    }
}

private extension DailyLedger {
    var availableAfterSettlingReservation: Int {
        wallet.availableSeconds + wallet.reservedSeconds
    }
}
