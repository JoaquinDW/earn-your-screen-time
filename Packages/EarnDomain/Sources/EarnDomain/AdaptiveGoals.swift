import Foundation

/// A measured daily-steps baseline used to personalize the first goal.
public struct ActivityBaseline: Codable, Equatable, Sendable {
    public let dailySteps: Int

    public init(dailySteps: Int) {
        self.dailySteps = max(0, dailySteps)
    }
}

public enum BaselineSource: String, Codable, Sendable {
    case healthKit
    case selfReported
}

public enum UserPrimaryGoal: String, Codable, CaseIterable, Sendable {
    case moveMore
    case scrollLess
    case feelInControl
    case healthierRoutine
}

/// The compact goal profile produced by adaptive onboarding.
public struct AdaptiveGoalProfile: Codable, Equatable, Sendable {
    public let baseline: ActivityBaseline
    public var dailyStepGoal: Int

    public init(baseline: ActivityBaseline, dailyStepGoal: Int? = nil) {
        self.baseline = baseline
        self.dailyStepGoal = max(
            GoalRecommendationEngine.minimumGoal,
            dailyStepGoal ?? GoalRecommendationEngine.recommend(forBaseline: baseline.dailySteps)
        )
    }
}

/// Chooses a conservative initial goal from an observed baseline.
public enum GoalRecommendationEngine {
    public static let minimumGoal = 2_000
    public static let maximumIncrease = 1_500
    public static let roundingIncrement = 500

    public static func recommend(for baseline: ActivityBaseline) -> Int {
        recommend(forBaseline: baseline.dailySteps)
    }

    public static func recommend(forBaseline baseline: Int) -> Int {
        let baseline = max(0, baseline)
        let increaseCap = min(baseline / 4, maximumIncrease)
        let desiredGoal: Int
        if baseline > 8_000 {
            desiredGoal = baseline + Int((Double(baseline) * 0.1).rounded())
        } else {
            desiredGoal = baseline + 1_000
        }
        let roundedDesired = ((desiredGoal + roundingIncrement / 2) / roundingIncrement) * roundingIncrement
        let maximumRoundedGoal = ((baseline + increaseCap) / roundingIncrement) * roundingIncrement
        let roundedGoal = min(roundedDesired, maximumRoundedGoal)
        return max(minimumGoal, roundedGoal)
    }
}

/// One completed day used to decide whether the current goal should change.
public struct DailyActivity: Codable, Equatable, Sendable {
    public let day: DayKey
    public let activityAmount: Int
    public let goal: Int

    public init(day: DayKey, activityAmount: Int, goal: Int) {
        self.day = day
        self.activityAmount = max(0, activityAmount)
        self.goal = max(0, goal)
    }

    public init(day: DayKey, steps: Int, goal: Int) {
        self.init(day: day, activityAmount: steps, goal: goal)
    }

    public var steps: Int { activityAmount }
    public var reachedGoal: Bool { activityAmount >= goal }
}

/// Adjusts a goal only after a complete seven-day observation window.
public enum GoalProgressionEngine {
    public static let windowDays = 7
    public static let adjustment = 500

    public static func recommendation(currentGoal: Int, activities: [DailyActivity]) -> Int? {
        guard activities.count == windowDays else { return nil }
        let successfulDays = activities.count(where: \.reachedGoal)
        if successfulDays >= 6 { return max(GoalRecommendationEngine.minimumGoal, currentGoal + adjustment) }
        if successfulDays <= 2 { return max(GoalRecommendationEngine.minimumGoal, currentGoal - adjustment) }
        return nil
    }

    public static func recommend(currentGoal: Int, from activities: [DailyActivity]) -> Int? {
        recommendation(currentGoal: currentGoal, activities: activities)
    }
}
