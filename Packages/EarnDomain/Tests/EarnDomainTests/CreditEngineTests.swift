import Testing
@testable import EarnDomain

private let today = DayKey(year: 2026, month: 8, day: 20)
private func freshLedger(rule: EarningRule = .default) -> DailyLedger {
    CreditEngine.startOfDay(today, rule: rule)
}

@Suite("Credit calculation (PRD §22)")
struct CreditCalculationTests {

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

    @Test("Unused credits do not carry over by default")
    func noCarryOver() {
        let yesterday = CreditEngine.apply(activityAmount: 4_000, to: freshLedger()).ledger
        let rolled = CreditEngine.rollOverIfNeeded(yesterday, to: DayKey(year: 2026, month: 8, day: 21))
        #expect(rolled.wallet.availableSeconds == 0)
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
