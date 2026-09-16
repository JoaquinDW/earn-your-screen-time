import Foundation
import Testing
@testable import EarnDomain

@Suite("Activity history")
struct ActivityHistoryTests {

    private let today = DayKey(year: 2026, month: 8, day: 20)

    private func day(_ offset: Int) -> DayKey {
        today.adding(days: offset)!
    }

    private func earning(_ offset: Int, minutes: Int, steps: Int = 4_000) -> DaySummary {
        DaySummary(day: day(offset), activityAmount: steps, earnedSeconds: minutes * 60)
    }

    @Test("A run of earning days counts back from today")
    func streakCountsBack() {
        var history = ActivityHistory()
        for offset in -5...(-1) { history.record(earning(offset, minutes: 20)) }
        let ledger = DailyLedger(day: today, activityAmount: 4_000, milestonesRewarded: 4,
                                 wallet: ScreenTimeWallet(earnedSeconds: 1_200))
        #expect(history.streak(endingOn: today, including: ledger) == 6)
    }

    @Test("A day that earned nothing breaks the run")
    func gapBreaksStreak() {
        var history = ActivityHistory()
        history.record(earning(-1, minutes: 20))
        history.record(earning(-2, minutes: 0, steps: 300))   // did not earn
        history.record(earning(-3, minutes: 25))
        #expect(history.streak(endingOn: today) == 1)
    }

    @Test("A streak the user has not extended yet today still stands at yesterday's number")
    func todayNotYetEarned() {
        var history = ActivityHistory()
        for offset in -3...(-1) { history.record(earning(offset, minutes: 15)) }
        let ledger = DailyLedger(day: today, activityAmount: 200)   // nothing earned yet
        #expect(history.streak(endingOn: today, including: ledger) == 3)
    }

    @Test("No history at all is a streak of zero")
    func emptyHistory() {
        #expect(ActivityHistory().streak(endingOn: today) == 0)
    }

    @Test("The week is always seven days, oldest first, gaps zero-filled")
    func weekIsAlwaysSeven() {
        var history = ActivityHistory()
        history.record(earning(-1, minutes: 34))
        history.record(earning(-4, minutes: 15))

        let week = history.week(endingOn: today)
        #expect(week.count == 7)
        #expect(week.first?.day == day(-6))
        #expect(week.last?.day == today)
        #expect(week[5].earnedMinutes == 34)
        #expect(week[2].earnedMinutes == 15)
        #expect(week[0].earnedMinutes == 0)
    }

    @Test("Today's live ledger shows in the week before the day is over")
    func todayComesFromTheLedger() {
        let ledger = DailyLedger(day: today, activityAmount: 3_842,
                                 wallet: ScreenTimeWallet(earnedSeconds: 34 * 60))
        let week = ActivityHistory().week(endingOn: today, including: ledger)
        #expect(week.last?.earnedMinutes == 34)
        #expect(week.last?.activityAmount == 3_842)
    }

    @Test("Re-recording a day replaces it instead of duplicating it")
    func recordIsIdempotent() {
        var history = ActivityHistory()
        history.record(earning(-1, minutes: 10))
        history.record(earning(-1, minutes: 40))
        #expect(history.days.count == 1)
        #expect(history.days.first?.earnedMinutes == 40)
    }

    @Test("History stays bounded — the extension cannot afford an unbounded array")
    func bounded() {
        var history = ActivityHistory()
        for offset in -60...(-1) { history.record(earning(offset, minutes: 5)) }
        #expect(history.days.count == ActivityHistory.maxDays)
        #expect(history.days.first?.day == day(-ActivityHistory.maxDays))
    }

    @Test("Inclusive range totals replace a stored day with the live summary")
    func rangeTotals() {
        var history = ActivityHistory()
        history.record(earning(-3, minutes: 10, steps: 1_000))
        history.record(earning(-2, minutes: 20, steps: 2_000))
        history.record(earning(-1, minutes: 30, steps: 3_000))
        let replacement = DaySummary(day: day(-1), activityAmount: 4_000, earnedSeconds: 40 * 60)

        let totals = history.totals(in: day(-2)...day(-1), including: replacement)
        #expect(totals.steps == 6_000)
        #expect(totals.earnedMinutes == 60)
        #expect(totals.activeDays == 2)
    }

    @Test("Calendar month totals do not leak across month boundaries")
    func monthTotals() {
        var history = ActivityHistory()
        history.record(DaySummary(day: DayKey(year: 2026, month: 7, day: 31), activityAmount: 9_000, earnedSeconds: 600))
        history.record(DaySummary(day: DayKey(year: 2026, month: 8, day: 1), activityAmount: 1_000, earnedSeconds: 300))
        history.record(DaySummary(day: DayKey(year: 2026, month: 8, day: 20), activityAmount: 2_000, earnedSeconds: 600))

        let totals = history.totals(forMonthContaining: today)
        #expect(totals.steps == 3_000)
        #expect(totals.earnedSeconds == 900)
        #expect(totals.activeDays == 2)
    }

    @Test("Day summaries round-trip Pushups without classifying them as steps")
    func pushupCodableRoundTrip() throws {
        let summary = DaySummary(
            day: today,
            activityAmount: 2_000,
            stepEarnedSeconds: 600,
            studyEarnedSeconds: 300,
            pushupEarnedSeconds: 900
        )

        let decoded = try JSONDecoder().decode(DaySummary.self, from: JSONEncoder().encode(summary))
        #expect(decoded == summary)
        #expect(decoded.earnedSeconds == 1_800)
        #expect(decoded.stepEarnedSeconds == 600)
        #expect(decoded.pushupEarnedSeconds == 900)
    }
}
