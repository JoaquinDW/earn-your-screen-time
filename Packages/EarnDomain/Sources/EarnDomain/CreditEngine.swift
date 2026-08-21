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

        public var didAward: Bool { awardedSeconds > 0 }
    }

    /// Applies a new activity reading, awarding credits for any milestone crossed for the first time.
    ///
    /// Safe to call repeatedly with the same or lower readings: credits are awarded exactly once
    /// per milestone (PRD §9).
    public static func apply(activityAmount: Int, to ledger: DailyLedger) -> Outcome {
        var updated = ledger
        // Activity totals for a day only ever grow; ignore transient lower readings.
        updated.activityAmount = max(ledger.activityAmount, max(0, activityAmount))

        let reachable = updated.qualifyingAmount / updated.rule.amountRequired
        let newMilestones = max(0, reachable - updated.milestonesRewarded)
        guard newMilestones > 0 else {
            return Outcome(ledger: updated, awardedSeconds: 0, awardedMilestones: 0)
        }

        let seconds = newMilestones * updated.rule.rewardSeconds
        updated.milestonesRewarded += newMilestones
        updated.wallet.credit(seconds: seconds)
        return Outcome(ledger: updated, awardedSeconds: seconds, awardedMilestones: newMilestones)
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
    /// MVP: unused credits do not carry over (PRD §17). `carryOverSeconds` exists so
    /// carry-over can become a premium feature without changing call sites.
    public static func startOfDay(_ day: DayKey, rule: EarningRule, carryOverSeconds: Int = 0) -> DailyLedger {
        DailyLedger(
            day: day,
            rule: rule,
            activityAmount: 0,
            baselineAmount: 0,
            milestonesRewarded: 0,
            wallet: ScreenTimeWallet(earnedSeconds: max(0, carryOverSeconds), consumedSeconds: 0)
        )
    }

    /// Returns a ledger valid for `day`, rolling over if the stored one belongs to an earlier day.
    public static func rollOverIfNeeded(_ ledger: DailyLedger, to day: DayKey, carryOverSeconds: Int = 0) -> DailyLedger {
        guard ledger.day != day else { return ledger }
        return startOfDay(day, rule: ledger.rule, carryOverSeconds: carryOverSeconds)
    }
}
