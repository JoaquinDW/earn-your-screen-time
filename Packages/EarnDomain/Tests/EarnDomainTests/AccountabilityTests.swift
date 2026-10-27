import Foundation
import Testing
@testable import EarnDomain

@Suite("Accountability days")
struct AccountabilityTests {
    private let today = DayKey(year: 2026, month: 10, day: 27)
    private let yesterday = DayKey(year: 2026, month: 10, day: 26)

    private func state(history: [DaySummary]) -> SharedState {
        var state = SharedState.initial(day: today)
        state.ledger.dailyGoal = 8_000
        state.ledger.activityAmount = 3_200
        state.history = ActivityHistory(days: history)
        return state
    }

    @Test("Today is sent as a day in progress")
    func todayInProgress() throws {
        let days = AccountabilityDay.recent(in: state(history: []))
        let day = try #require(days.first)
        #expect(days.count == 1)
        #expect(day.day == today)
        #expect(!day.isFinal)
        #expect(!day.goalMet)
        #expect(day.dailyGoal == 8_000)
    }

    @Test("Yesterday is sent as final, with its own goal")
    func yesterdayFinal() throws {
        let summary = DaySummary(
            day: yesterday,
            activityAmount: 6_500,
            stepEarnedSeconds: 600,
            studyEarnedSeconds: 0,
            dailyGoal: 6_000
        )
        let days = AccountabilityDay.recent(in: state(history: [summary]))
        let final = try #require(days.first { $0.isFinal })
        #expect(final.day == yesterday)
        #expect(final.goalMet)
        #expect(final.earnedSeconds == 600)
        #expect(final.streakDays == 1)
    }

    @Test("A day filed before goals were kept borrows today's goal")
    func legacyGoal() throws {
        let summary = DaySummary(day: yesterday, activityAmount: 7_000, earnedSeconds: 300)
        let final = try #require(AccountabilityDay.recent(in: state(history: [summary])).first { $0.isFinal })
        #expect(final.dailyGoal == 8_000)
        #expect(!final.goalMet)
    }

    @Test("A gap in history is never reported as a miss")
    func gapNotSent() {
        let gap = DaySummary(day: yesterday, activityAmount: 0, stepEarnedSeconds: 0, studyEarnedSeconds: 0, hasUsageData: false)
        #expect(AccountabilityDay.recent(in: state(history: [gap])).allSatisfy { !$0.isFinal })
    }

    @Test("The goal survives a round trip through history")
    func goalCodable() throws {
        let summary = DaySummary(day: yesterday, activityAmount: 1, stepEarnedSeconds: 0, studyEarnedSeconds: 0, dailyGoal: 9_000)
        let decoded = try JSONDecoder().decode(DaySummary.self, from: JSONEncoder().encode(summary))
        #expect(decoded.dailyGoal == 9_000)
    }
}
