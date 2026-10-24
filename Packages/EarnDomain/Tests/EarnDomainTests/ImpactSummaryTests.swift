import Foundation
import Testing
@testable import EarnDomain

@Suite("Skipped opens and the impact report")
struct ImpactSummaryTests {
    private let day = DayKey(year: 2026, month: 10, day: 20)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test("Skips are counted per day")
    func countsPerDay() {
        var log = SkippedOpenLog()
        log.record(on: day, calendar: calendar)
        log.record(on: day, calendar: calendar)
        let tomorrow = day.adding(days: 1, calendar: calendar)!
        log.record(on: tomorrow, calendar: calendar)

        #expect(log.count(on: day) == 2)
        #expect(log.count(on: tomorrow) == 1)
        #expect(log.total(on: [day, tomorrow, day]) == 3)
        #expect(log.totalRecorded == 3)
    }

    @Test("Old days are pruned but the running total is kept")
    func prunesOldDays() {
        var log = SkippedOpenLog()
        log.record(on: day, calendar: calendar)
        let later = day.adding(days: SkippedOpenLog.retainedDays, calendar: calendar)!
        log.record(on: later, calendar: calendar)

        #expect(log.count(on: day) == 0)
        #expect(log.count(on: later) == 1)
        #expect(log.totalRecorded == 2)
    }

    @Test("A log written without a running total starts from its counts")
    func decodesWithoutTotal() throws {
        let data = Data(#"{"counts":{"2026-10-20":4}}"#.utf8)
        let log = try JSONDecoder().decode(SkippedOpenLog.self, from: data)
        #expect(log.count(on: day) == 4)
        #expect(log.totalRecorded == 4)

        let roundTrip = try JSONDecoder().decode(SkippedOpenLog.self, from: JSONEncoder().encode(log))
        #expect(roundTrip == log)
    }

    @Test("Reclaimed time is the band's lower bound minus recorded use")
    func reclaimedAgainstBaseline() {
        let summaries = [
            DaySummary(day: day, activityAmount: 6_000, stepEarnedSeconds: 1_800, studyEarnedSeconds: 0,
                       consumedSeconds: 1_200),
            DaySummary(day: day.adding(days: 1, calendar: calendar)!, activityAmount: 4_000,
                       stepEarnedSeconds: 600, studyEarnedSeconds: 0, consumedSeconds: 600)
        ]
        let impact = ImpactSummary(summaries: summaries, skippedOpens: 5, scrolling: .twoToFourHours)

        #expect(impact.activityAmount == 10_000)
        #expect(impact.earnedSeconds == 2_400)
        #expect(impact.consumedSeconds == 1_800)
        #expect(impact.skippedOpens == 5)
        #expect(impact.trackedDays == 2)
        // Two hours a day for two days, less half an hour used.
        #expect(impact.reclaimedSeconds == 2 * 7_200 - 1_800)
    }

    @Test("Only the elapsed part of today counts toward the baseline")
    func todayIsPartial() {
        let today = DaySummary(day: day, activityAmount: 0, stepEarnedSeconds: 0, studyEarnedSeconds: 0)
        let impact = ImpactSummary(
            summaries: [today],
            skippedOpens: 0,
            scrolling: .oneToTwoHours,
            today: day,
            todayElapsedFraction: 0.25
        )
        #expect(impact.reclaimedSeconds == 900)
    }

    @Test("No claim without a baseline or tracked days")
    func noBaseline() {
        let tracked = DaySummary(day: day, activityAmount: 0, stepEarnedSeconds: 0, studyEarnedSeconds: 0)
        let gap = DaySummary(day: day, activityAmount: 0, stepEarnedSeconds: 0, studyEarnedSeconds: 0,
                             hasUsageData: false)

        #expect(ImpactSummary(summaries: [tracked], skippedOpens: 0, scrolling: nil).reclaimedSeconds == nil)
        #expect(ImpactSummary(summaries: [tracked], skippedOpens: 0, scrolling: .underOneHour).reclaimedSeconds == nil)
        #expect(ImpactSummary(summaries: [gap], skippedOpens: 0, scrolling: .fourHoursPlus).reclaimedSeconds == nil)
    }

    @Test("Using more than the baseline never reports a negative")
    func neverNegative() {
        let heavy = DaySummary(day: day, activityAmount: 0, stepEarnedSeconds: 0, studyEarnedSeconds: 0,
                               consumedSeconds: 10_000)
        let impact = ImpactSummary(summaries: [heavy], skippedOpens: 0, scrolling: .oneToTwoHours)
        #expect(impact.reclaimedSeconds == 0)
        #expect(!impact.hasContent)
    }

    @Test("The waking day runs from seven to eleven")
    func wakingDay() {
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: hour, minute: minute))!
        }
        #expect(ImpactSummary.wakingDayFraction(at: at(6), calendar: calendar) == 0)
        #expect(ImpactSummary.wakingDayFraction(at: at(15), calendar: calendar) == 0.5)
        #expect(ImpactSummary.wakingDayFraction(at: at(23, 30), calendar: calendar) == 1)
    }
}
