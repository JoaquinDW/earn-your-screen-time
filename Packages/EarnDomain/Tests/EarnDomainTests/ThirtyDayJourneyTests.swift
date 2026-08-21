import Foundation
import Testing
@testable import EarnDomain

@Suite("Thirty-day journey")
struct ThirtyDayJourneyTests {
    private let start = DayKey(year: 2026, month: 8, day: 1)

    @Test("A finished day is incorporated once")
    func idempotentIncorporation() {
        let summary = DaySummary(day: start, activityAmount: 8_200, earnedSeconds: 2_400)
        let once = ThirtyDayJourney(startDay: start, dailyGoal: 8_000).incorporating(summary)
        let twice = once.incorporating(summary)
        #expect(twice == once)
        #expect(twice.cumulativeSteps == 8_200)
        #expect(twice.activeDays == 1)
        #expect(twice.goalHitDays == 1)
    }

    @Test("Days outside the fixed window are ignored")
    func ignoresOutsideWindow() {
        let before = DaySummary(day: start.adding(days: -1)!, activityAmount: 10_000, earnedSeconds: 3_000)
        let after = DaySummary(day: start.adding(days: 30)!, activityAmount: 10_000, earnedSeconds: 3_000)
        let journey = ThirtyDayJourney(startDay: start, dailyGoal: 8_000)
            .incorporating(before)
            .incorporating(after)
        #expect(journey.cumulativeSteps == 0)
    }

    @Test("Elapsed day is one-based and capped")
    func elapsedDay() {
        let journey = ThirtyDayJourney(startDay: start, dailyGoal: 8_000)
        #expect(journey.elapsedDay(asOf: start.adding(days: -1)!) == 0)
        #expect(journey.elapsedDay(asOf: start) == 1)
        #expect(journey.elapsedDay(asOf: start.adding(days: 29)!) == 30)
        #expect(journey.elapsedDay(asOf: start.adding(days: 40)!) == 30)
    }

    @Test("Today's display is included without changing or double counting persisted totals")
    func displayIncludesTodayOnce() {
        let today = start.adding(days: 1)!
        let finished = DaySummary(day: start, activityAmount: 8_000, earnedSeconds: 2_400)
        let live = DaySummary(day: today, activityAmount: 4_000, earnedSeconds: 1_200)
        let journey = ThirtyDayJourney(startDay: start, dailyGoal: 8_000).incorporating(finished)

        #expect(journey.progress(includingToday: live).cumulativeSteps == 12_000)
        #expect(journey.cumulativeSteps == 8_000)
        let filedToday = journey.incorporating(live)
        #expect(filedToday.progress(includingToday: live).cumulativeSteps == 12_000)
    }

    @Test("Finalization and completion acknowledgment are idempotent")
    func finalization() {
        let summary = DaySummary(day: start, activityAmount: 10_000, earnedSeconds: 3_000)
        let journey = ThirtyDayJourney(startDay: start, dailyGoal: 8_000, target: 10_000)
            .incorporating(summary)
        #expect(journey.finalizing(asOf: start.adding(days: 29)!).finalizedResult == nil)
        let final = journey.finalizing(asOf: start.adding(days: 30)!)
        #expect(final.finalizedResult?.reachedTarget == true)
        #expect(final.finalizing(asOf: start.adding(days: 40)!) == final)
        #expect(final.acknowledgingCompletion().completionAcknowledged)
        #expect(journey.acknowledgingCompletion().completionAcknowledged == false)
    }
}
