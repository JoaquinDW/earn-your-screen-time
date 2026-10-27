import Foundation

/// What friends see of one day: whether the movement goal was reached, and the totals behind it.
///
/// BePresent tells your buddy when you miss your goal and Jomo puts friends in squads. Both work
/// because someone else notices. Only these numbers ever leave the phone: never which apps are
/// protected, how the minutes were spent, or anything Screen Time reports.
public struct AccountabilityDay: Codable, Equatable, Sendable {
    public let day: DayKey
    public let dailyGoal: Int
    public let activityAmount: Int
    public let earnedSeconds: Int
    public let streakDays: Int
    /// The day is over. A final day short of its goal is the one friends are told about.
    public let isFinal: Bool

    public init(day: DayKey, dailyGoal: Int, activityAmount: Int, earnedSeconds: Int, streakDays: Int, isFinal: Bool) {
        self.day = day
        self.dailyGoal = max(0, dailyGoal)
        self.activityAmount = max(0, activityAmount)
        self.earnedSeconds = max(0, earnedSeconds)
        self.streakDays = max(0, streakDays)
        self.isFinal = isFinal
    }

    public var goalMet: Bool { dailyGoal > 0 && activityAmount >= dailyGoal }

    /// Today so far, and yesterday as a finished day when history has it.
    ///
    /// Yesterday is what drives the "missed their goal" message, so it is sent as final as soon
    /// as the day has rolled over. A day with no history (the app never ran) is not sent at all:
    /// friends are told about a miss, never about silence.
    public static func recent(in state: SharedState, calendar: Calendar = .current) -> [AccountabilityDay] {
        let today = state.ledger.day
        let goal = state.ledger.dailyGoal > 0 ? state.ledger.dailyGoal : state.dailyStepGoal
        var days = [
            AccountabilityDay(
                day: today,
                dailyGoal: goal,
                activityAmount: state.ledger.activityAmount,
                earnedSeconds: state.ledger.wallet.earnedSeconds,
                streakDays: state.history.streak(endingOn: today, including: state.ledger, calendar: calendar),
                isFinal: false
            )
        ]
        if let yesterday = today.adding(days: -1, calendar: calendar),
           let summary = state.history.days.first(where: { $0.day == yesterday }),
           summary.hasUsageData {
            days.append(AccountabilityDay(
                day: yesterday,
                // Days filed before the goal was kept fall back to today's goal.
                dailyGoal: summary.dailyGoal > 0 ? summary.dailyGoal : goal,
                activityAmount: summary.activityAmount,
                earnedSeconds: summary.earnedSeconds,
                streakDays: state.history.streak(endingOn: yesterday, calendar: calendar),
                isFinal: true
            ))
        }
        return days
    }
}
