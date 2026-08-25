import Foundation
import Testing
@testable import EarnDomain

@Suite("Earned time balance")
struct WalletTests {

    @Test("earned 600 − consumed 240 = 360 available")
    func partialConsumption() {
        let wallet = ScreenTimeWallet(earnedSeconds: 600, consumedSeconds: 240)
        #expect(wallet.availableSeconds == 360)
        #expect(wallet.availableMinutes == 6)
    }

    @Test("Reserving the full balance leaves no available time")
    func exhaustion() {
        let wallet = ScreenTimeWallet(earnedSeconds: 600, consumedSeconds: 600)
        #expect(wallet.availableSeconds == 0)
    }

    @Test("Overshooting consumption never produces a negative balance")
    func neverNegative() {
        let wallet = ScreenTimeWallet(earnedSeconds: 600, consumedSeconds: 900)
        #expect(wallet.availableSeconds == 0)
    }

    @Test("A reservation succeeds only when the balance covers it")
    func reservationRequiresBalance() {
        var wallet = ScreenTimeWallet(earnedSeconds: 600)
        let firstReservation = wallet.reserve(seconds: 300)
        let oversizedReservation = wallet.reserve(seconds: 301)
        #expect(firstReservation)
        #expect(!oversizedReservation)
        #expect(wallet.consumedSeconds == 0)
        #expect(wallet.reservedSeconds == 300)
        #expect(wallet.availableSeconds == 300)
    }

    @Test("Settling a reservation consumes elapsed time and saves the rest")
    func settlement() {
        var wallet = ScreenTimeWallet(earnedSeconds: 600)
        let reserved = wallet.reserve(seconds: 300)
        #expect(reserved)
        let saved = wallet.settleReservation(consuming: 120)
        #expect(saved == 180)
        #expect(wallet.consumedSeconds == 120)
        #expect(wallet.reservedSeconds == 0)
        #expect(wallet.availableSeconds == 480)
    }

    @Test("Credits stop at the fixed 180-minute capacity")
    func capacity() {
        var wallet = ScreenTimeWallet(earnedSeconds: 179 * 60)
        #expect(wallet.credit(seconds: 5 * 60) == 60)
        #expect(wallet.remainingValueSeconds == ScreenTimeWallet.maximumSavedSeconds)
        #expect(wallet.isAtCapacity)
    }

    @Test("Earning after a reservation only increases available balance")
    func earningAfterReservation() {
        var ledger = DailyLedger(
            day: DayKey(year: 2026, month: 8, day: 20),
            wallet: ScreenTimeWallet(earnedSeconds: 600, consumedSeconds: 600)
        )
        ledger.activityAmount = 2_000
        ledger.milestonesRewarded = 2
        #expect(ledger.wallet.availableSeconds == 0)

        ledger = CreditEngine.apply(activityAmount: 3_000, to: ledger).ledger
        #expect(ledger.wallet.availableSeconds == 300)
    }

    @Test("A brand-new day starts with an empty balance")
    func newDayStartsEmpty() {
        let ledger = CreditEngine.startOfDay(DayKey(year: 2026, month: 8, day: 20), rule: .default)
        #expect(ledger.wallet.availableSeconds == 0)
    }
}

@Suite("Earning rule validation")
struct EarningRuleTests {

    @Test("The default rule is 1,000 steps = 5 minutes")
    func defaults() {
        #expect(EarningRule.default.amountRequired == 1_000)
        #expect(EarningRule.default.rewardMinutes == 5)
    }

    @Test("Rewards are rounded down to whole minutes")
    func wholeMinuteRewards() {
        #expect(EarningRule(amountRequired: 1_000, rewardSeconds: 90).rewardSeconds == 60)
    }

    @Test("Absurd values are clamped instead of crashing")
    func clamping() {
        let tiny = EarningRule(amountRequired: 0, rewardSeconds: 0)
        #expect(tiny.amountRequired == EarningRule.minimumAmount)
        #expect(tiny.rewardSeconds == EarningRule.minimumReward)

        let huge = EarningRule(amountRequired: 10_000_000, rewardSeconds: 10_000_000)
        #expect(huge.amountRequired == EarningRule.maximumAmount)
        #expect(huge.rewardSeconds == EarningRule.maximumReward)
    }

    @Test("Only steps are implemented for the MVP")
    func implementedSources() {
        #expect(EarningSource.steps.isImplemented)
        #expect(!EarningSource.workout.isImplemented)
    }
}

@Suite("DayKey")
struct DayKeyTests {

    @Test("Days are ordered chronologically")
    func ordering() {
        #expect(DayKey(year: 2026, month: 8, day: 20) < DayKey(year: 2026, month: 8, day: 21))
        #expect(DayKey(year: 2025, month: 12, day: 31) < DayKey(year: 2026, month: 1, day: 1))
    }

    @Test("A day is derived in the user's local calendar")
    func localCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
        // 2026-08-21T01:30:00Z is still 2026-08-20 in Buenos Aires (UTC−3).
        let date = Date(timeIntervalSince1970: 1_787_275_800)
        #expect(DayKey(date: date, calendar: calendar) == DayKey(year: 2026, month: 8, day: 20))
    }

    @Test("Description is a sortable ISO-like string")
    func description() {
        #expect(DayKey(year: 2026, month: 1, day: 5).description == "2026-01-05")
    }
}
