import Foundation

/// An honest 30-day projection at the recommended daily goal.
///
/// Earnings are calculated independently for each day because unfinished milestones do not carry
/// between daily ledgers. No uplift, adherence, or user-average assumptions are introduced.
public struct Projection: Equatable, Sendable {
    public static let horizonDays = 30
    public static let metresPerStep = 0.75
    public static let marathonKilometres = 42.195
    public static let stepsPerWalkingMinute = 100

    public let baselineDailySteps: Int
    public let dailySteps: Int
    public let totalSteps: Int
    public let totalKilometres: Int
    public let marathons: Int
    public let earnedMinutes: Int
    public let walkingMinutes: Int

    public var dailyStepUplift: Int { max(0, dailySteps - baselineDailySteps) }
    public let upliftSteps: Int
    public let upliftKilometres: Int
    public var upliftWalkingMinutes: Int { upliftSteps / Self.stepsPerWalkingMinute }

    public var earnedHours: Int { Int((Double(earnedMinutes) / 60).rounded()) }

    // Compatibility names used by the current onboarding UI. They now describe all projected
    // walking, not an asserted increase over the user's self-reported movement.
    public var extraStepsPerDay: Int { dailyStepUplift }
    public var extraSteps: Int { upliftSteps }
    public var extraKilometres: Int { upliftKilometres }
    public static let minimumDailyUplift = 500

    public init(profile: OnboardingProfile, rule: EarningRule = .default, days: Int = Projection.horizonDays) {
        self.init(currentDailySteps: profile.currentDailySteps, goalDailySteps: profile.dailyStepGoal, rule: rule, days: days)
    }

    public init(
        goalDailySteps: Int,
        rule: EarningRule = .default,
        days: Int = Projection.horizonDays
    ) {
        self.init(currentDailySteps: 0, goalDailySteps: goalDailySteps, rule: rule, days: days)
    }

    public init(
        currentDailySteps: Int,
        goalDailySteps: Int,
        rule: EarningRule = .default,
        days: Int = Projection.horizonDays
    ) {
        let horizon = max(1, days)
        baselineDailySteps = max(0, currentDailySteps)
        dailySteps = max(0, goalDailySteps)
        totalSteps = dailySteps * horizon
        upliftSteps = max(0, dailySteps - baselineDailySteps) * horizon
        let kilometres = Double(totalSteps) * Self.metresPerStep / 1_000
        totalKilometres = Int(kilometres.rounded())
        upliftKilometres = Int((Double(upliftSteps) * Self.metresPerStep / 1_000).rounded())
        marathons = Int((kilometres / Self.marathonKilometres).rounded())
        earnedMinutes = (dailySteps / rule.amountRequired) * rule.rewardMinutes * horizon
        walkingMinutes = totalSteps / Self.stepsPerWalkingMinute
    }
}
