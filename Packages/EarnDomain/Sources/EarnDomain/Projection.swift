import Foundation

/// An honest 30-day projection at the recommended daily goal.
///
/// Earnings are calculated independently for each day because unfinished milestones do not carry
/// between daily ledgers. No uplift, adherence, or user-average assumptions are introduced.
public struct Projection: Equatable, Sendable {
    public static let horizonDays = 30
    public static let metresPerStep = 0.75
    public static let marathonKilometres = 42.195

    public let dailySteps: Int
    public let totalSteps: Int
    public let totalKilometres: Int
    public let marathons: Int
    public let earnedMinutes: Int

    public var earnedHours: Int { Int((Double(earnedMinutes) / 60).rounded()) }

    // Compatibility names used by the current onboarding UI. They now describe all projected
    // walking, not an asserted increase over the user's self-reported movement.
    public var extraStepsPerDay: Int { dailySteps }
    public var extraSteps: Int { totalSteps }
    public var extraKilometres: Int { totalKilometres }
    public static let minimumDailyUplift = 500

    public init(profile: OnboardingProfile, rule: EarningRule = .default, days: Int = Projection.horizonDays) {
        self.init(goalDailySteps: profile.dailyStepGoal, rule: rule, days: days)
    }

    public init(
        goalDailySteps: Int,
        rule: EarningRule = .default,
        days: Int = Projection.horizonDays
    ) {
        let horizon = max(1, days)
        dailySteps = max(0, goalDailySteps)
        totalSteps = dailySteps * horizon
        let kilometres = Double(totalSteps) * Self.metresPerStep / 1_000
        totalKilometres = Int(kilometres.rounded())
        marathons = Int((kilometres / Self.marathonKilometres).rounded())
        earnedMinutes = (dailySteps / rule.amountRequired) * rule.rewardMinutes * horizon
    }

    /// Source-compatible initializer; current steps are intentionally irrelevant to the promise.
    public init(
        currentDailySteps: Int,
        goalDailySteps: Int,
        rule: EarningRule = .default,
        days: Int = Projection.horizonDays
    ) {
        self.init(goalDailySteps: goalDailySteps, rule: rule, days: days)
    }
}
