import Foundation
import Testing
@testable import EarnDomain

private let today = DayKey(year: 2026, month: 8, day: 20)
private func freshLedger(rule: EarningRule = .default) -> DailyLedger {
    CreditEngine.startOfDay(today, rule: rule)
}

@Suite("Credit calculation (PRD §22)")
struct CreditCalculationTests {

    @Test("Five-hundred-step milestones award only at exact boundaries")
    func fiveHundredStepBoundaries() {
        let rule = EarningRule(amountRequired: 500, rewardSeconds: 300)
        var ledger = freshLedger(rule: rule)
        let readings = [499, 500, 999, 1_000, 1_499, 1_500]
        var milestoneAwards: [Int] = []
        for reading in readings {
            let outcome = CreditEngine.apply(activityAmount: reading, to: ledger)
            ledger = outcome.ledger
            milestoneAwards.append(outcome.awardedMilestones)
        }
        #expect(milestoneAwards == [0, 1, 0, 1, 0, 1])
        #expect(ledger.wallet.earnedSeconds == 900)
    }

    @Test("999 steps earn nothing")
    func belowFirstMilestone() {
        let outcome = CreditEngine.apply(activityAmount: 999, to: freshLedger())
        #expect(outcome.awardedSeconds == 0)
        #expect(outcome.ledger.wallet.earnedSeconds == 0)
    }

    @Test("1,000 steps earn 5 minutes")
    func firstMilestone() {
        let outcome = CreditEngine.apply(activityAmount: 1_000, to: freshLedger())
        #expect(outcome.awardedMilestones == 1)
        #expect(outcome.ledger.wallet.earnedSeconds == 300)
    }

    @Test("1,999 steps still earn only 5 minutes")
    func betweenMilestones() {
        let outcome = CreditEngine.apply(activityAmount: 1_999, to: freshLedger())
        #expect(outcome.ledger.wallet.earnedSeconds == 300)
    }

    @Test("2,000 steps earn 10 minutes")
    func secondMilestone() {
        let outcome = CreditEngine.apply(activityAmount: 2_000, to: freshLedger())
        #expect(outcome.ledger.wallet.earnedSeconds == 600)
    }

    @Test("5,000 steps earn 25 minutes")
    func fifthMilestone() {
        let outcome = CreditEngine.apply(activityAmount: 5_000, to: freshLedger())
        #expect(outcome.awardedMilestones == 5)
        #expect(outcome.ledger.wallet.earnedSeconds == 1_500)
    }

    @Test("Incremental readings award the same total as one big reading")
    func incrementalMatchesBulk() {
        var ledger = freshLedger()
        for steps in stride(from: 250, through: 5_000, by: 250) {
            ledger = CreditEngine.apply(activityAmount: steps, to: ledger).ledger
        }
        #expect(ledger.wallet.earnedSeconds == 1_500)
    }

    @Test("A custom rule of 500 steps = 5 min earns twice as fast")
    func customRule() {
        let rule = EarningRule(source: .steps, amountRequired: 500, rewardSeconds: 300)
        let outcome = CreditEngine.apply(activityAmount: 1_000, to: freshLedger(rule: rule))
        #expect(outcome.ledger.wallet.earnedSeconds == 600)
    }
}

@Suite("Daily goal bonus")
struct DailyGoalBonusTests {
    private func bonusLedger(day: DayKey = today) -> DailyLedger {
        CreditEngine.startOfDay(day, rule: .default, dailyGoal: 1_500, goalBonusSeconds: 600)
    }

    @Test("Goal crossing is independent from step milestones and outcome separates both awards")
    func crossingBetweenMilestones() {
        var ledger = CreditEngine.apply(activityAmount: 1_499, to: bonusLedger()).ledger
        let outcome = CreditEngine.apply(activityAmount: 1_500, to: ledger)
        ledger = outcome.ledger
        #expect(outcome.awardedStepSeconds == 0)
        #expect(outcome.awardedGoalBonusSeconds == 600)
        #expect(outcome.awardedSeconds == 600)
        #expect(ledger.transactions.map(\.kind) == [.stepMilestone, .dailyGoalBonus])
    }

    @Test("Repeated readings and an encoded restart award the bonus exactly once")
    func idempotentAcrossRestart() throws {
        var ledger = CreditEngine.apply(activityAmount: 1_500, to: bonusLedger()).ledger
        ledger = try JSONDecoder().decode(DailyLedger.self, from: JSONEncoder().encode(ledger))
        let repeated = CreditEngine.apply(activityAmount: 2_000, to: ledger)
        #expect(repeated.awardedGoalBonusSeconds == 0)
        #expect(repeated.ledger.wallet.earnedSeconds == 1_200)
        #expect(repeated.ledger.transactions.count(where: { $0.kind == .dailyGoalBonus }) == 1)
    }

    @Test("A new day resets wallet, transactions, and bonus eligibility while retaining configuration")
    func newDay() {
        let earned = CreditEngine.apply(activityAmount: 1_500, to: bonusLedger()).ledger
        let tomorrow = DayKey(year: 2026, month: 8, day: 21)
        var rolled = CreditEngine.rollOverIfNeeded(earned, to: tomorrow)
        #expect(rolled.wallet.earnedSeconds == 0)
        #expect(rolled.transactions.isEmpty)
        #expect(!rolled.goalBonusAwarded)
        rolled = CreditEngine.apply(activityAmount: 1_500, to: rolled).ledger
        #expect(rolled.goalBonusAwarded)
        #expect(rolled.wallet.earnedSeconds == 900)
    }
}

@Suite("Duplicate protection (PRD §22)")
struct DuplicateProtectionTests {

    @Test("Repeated readings of 2,000 steps award 10 minutes exactly once")
    func repeatedReadings() {
        var ledger = freshLedger()
        for _ in 0..<25 {
            ledger = CreditEngine.apply(activityAmount: 2_000, to: ledger).ledger
        }
        #expect(ledger.wallet.earnedSeconds == 600)
        #expect(ledger.milestonesRewarded == 2)
    }

    @Test("HealthKit updates around one threshold emit one legitimate award")
    func thresholdCrossingIsAwardedOnce() {
        var ledger = freshLedger()
        let readings = [995, 1_003, 1_012, 1_020]
        var awards: [Int] = []

        for steps in readings {
            let outcome = CreditEngine.apply(activityAmount: steps, to: ledger)
            ledger = outcome.ledger
            if outcome.didAward { awards.append(outcome.awardedSeconds) }
        }

        #expect(awards == [300])
        #expect(ledger.wallet.earnedSeconds == 300)
        #expect(ledger.milestonesRewarded == 1)
    }

    @Test("A lower reading never removes credits or re-awards them")
    func decreasingReading() {
        var ledger = CreditEngine.apply(activityAmount: 3_000, to: freshLedger()).ledger
        let outcome = CreditEngine.apply(activityAmount: 1_200, to: ledger)
        ledger = outcome.ledger
        #expect(outcome.awardedSeconds == 0)
        #expect(ledger.activityAmount == 3_000)
        #expect(ledger.wallet.earnedSeconds == 900)
    }
}

@Suite("Rule changes (PRD §16)")
struct RuleChangeTests {

    @Test("Changing the rule does not retroactively award credits")
    func noRetroactiveAward() {
        var ledger = CreditEngine.apply(activityAmount: 3_000, to: freshLedger()).ledger
        #expect(ledger.wallet.earnedSeconds == 900)

        // Switch to a far easier rule: 500 steps = 10 minutes.
        ledger = CreditEngine.changeRule(
            to: EarningRule(source: .steps, amountRequired: 500, rewardSeconds: 600),
            in: ledger
        )
        let outcome = CreditEngine.apply(activityAmount: 3_000, to: ledger)
        #expect(outcome.awardedSeconds == 0, "Steps already paid must not be paid again")
        #expect(outcome.ledger.wallet.earnedSeconds == 900)
    }

    @Test("Only activity after the rule change earns under the new rule")
    func futureActivityUsesNewRule() {
        var ledger = CreditEngine.apply(activityAmount: 3_000, to: freshLedger()).ledger
        ledger = CreditEngine.changeRule(
            to: EarningRule(source: .steps, amountRequired: 500, rewardSeconds: 600),
            in: ledger
        )
        let outcome = CreditEngine.apply(activityAmount: 3_500, to: ledger)
        #expect(outcome.awardedMilestones == 1)
        #expect(outcome.ledger.wallet.earnedSeconds == 900 + 600)
    }

    @Test("Next milestone is measured from the rule-change baseline")
    func nextMilestoneAfterRuleChange() {
        var ledger = CreditEngine.apply(activityAmount: 3_842, to: freshLedger()).ledger
        var next = CreditEngine.nextMilestone(in: ledger)
        #expect(next.targetAmount == 4_000)
        #expect(next.remainingAmount == 158)

        ledger = CreditEngine.changeRule(
            to: EarningRule(source: .steps, amountRequired: 1_000, rewardSeconds: 600),
            in: ledger
        )
        next = CreditEngine.nextMilestone(in: ledger)
        #expect(next.targetAmount == 4_842)
        #expect(next.rewardMinutes == 10)
    }
}

@Suite("Daily reset (PRD §17)")
struct DailyResetTests {

    @Test("Yesterday's milestones do not block today's")
    func newDayEarnsAgain() {
        let yesterday = CreditEngine.apply(activityAmount: 5_000, to: freshLedger()).ledger
        #expect(yesterday.wallet.earnedSeconds == 1_500)

        let tomorrow = DayKey(year: 2026, month: 8, day: 21)
        var todayLedger = CreditEngine.rollOverIfNeeded(yesterday, to: tomorrow)
        #expect(todayLedger.wallet.earnedSeconds == 0)
        #expect(todayLedger.milestonesRewarded == 0)

        todayLedger = CreditEngine.apply(activityAmount: 1_000, to: todayLedger).ledger
        #expect(todayLedger.wallet.earnedSeconds == 300)
    }

    @Test("At most twenty unused minutes carry over")
    func cappedCarryOver() {
        let yesterday = CreditEngine.apply(activityAmount: 4_000, to: freshLedger()).ledger
        let rolled = CreditEngine.rollOverIfNeeded(yesterday, to: DayKey(year: 2026, month: 8, day: 21))
        #expect(rolled.wallet.availableSeconds == 1_200)
        #expect(rolled.wallet.carriedSeconds == 1_200)
        #expect(rolled.wallet.earnedSeconds == 0)
    }

    @Test("Milestones reached at capacity are not awarded later")
    func capacityDoesNotDeferRewards() {
        var ledger = freshLedger()
        ledger.wallet = ScreenTimeWallet(earnedSeconds: ScreenTimeWallet.maximumSavedSeconds)
        let full = CreditEngine.apply(activityAmount: 1_000, to: ledger)
        #expect(full.awardedSeconds == 0)
        #expect(full.uncreditedSeconds == 300)
        #expect(full.didReachWalletCapacity)
        #expect(full.ledger.milestonesRewarded == 1)
    }

    @Test("Filling the final available minutes reports that capacity was reached")
    func reachingCapacityExactly() {
        var ledger = freshLedger()
        ledger.wallet = ScreenTimeWallet(earnedSeconds: 175 * 60)
        let outcome = CreditEngine.apply(activityAmount: 1_000, to: ledger)
        #expect(outcome.awardedSeconds == 300)
        #expect(outcome.uncreditedSeconds == 0)
        #expect(outcome.didReachWalletCapacity)
        #expect(outcome.ledger.wallet.isAtCapacity)
    }

    @Test("Carry-over hook is available for a future premium feature")
    func optInCarryOver() {
        let yesterday = CreditEngine.apply(activityAmount: 4_000, to: freshLedger()).ledger
        let rolled = CreditEngine.rollOverIfNeeded(
            yesterday,
            to: DayKey(year: 2026, month: 8, day: 21),
            carryOverSeconds: yesterday.wallet.availableSeconds
        )
        #expect(rolled.wallet.availableSeconds == 1_200)
    }

    @Test("Rolling over on the same day is a no-op")
    func sameDayIsNoop() {
        let ledger = CreditEngine.apply(activityAmount: 2_500, to: freshLedger()).ledger
        #expect(CreditEngine.rollOverIfNeeded(ledger, to: today) == ledger)
    }
}
