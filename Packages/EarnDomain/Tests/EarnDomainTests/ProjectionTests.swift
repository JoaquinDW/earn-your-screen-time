import Foundation
import Testing
@testable import EarnDomain

@Suite("Outcome-driven onboarding")
struct OnboardingProfileTests {
    @Test("Movement bands produce the approved base recommendations", arguments: [
        (OnboardingProfile.MovementBand.underThreeThousand, 6_000),
        (.threeToFiveThousand, 8_000),
        (.fiveToEightThousand, 10_000),
        (.eightThousandPlus, 10_000),
        (.unsure, 8_000)
    ])
    func baseRecommendations(movement: OnboardingProfile.MovementBand, expected: Int) {
        #expect(OnboardingProfile.recommendDailyStepGoal(movement: movement, outcomes: []) == expected)
    }

    @Test("Walking outcomes raise one tier and cap at ten thousand", arguments: [
        (OnboardingProfile.MovementBand.underThreeThousand, 8_000),
        (.threeToFiveThousand, 10_000),
        (.fiveToEightThousand, 10_000)
    ])
    func walkingOutcomeRaisesTier(movement: OnboardingProfile.MovementBand, expected: Int) {
        #expect(OnboardingProfile.recommendDailyStepGoal(movement: movement, outcomes: [.walkMore]) == expected)
        #expect(OnboardingProfile.recommendDailyStepGoal(movement: movement, outcomes: [.beMoreActive]) == expected)
    }

    @Test("Unrelated outcomes do not raise the movement recommendation")
    func nonWalkingOutcomeKeepsBase() {
        let outcomes: Set<OnboardingProfile.DesiredOutcome> = [.scrollLess, .feelInControl, .stopLosingHours]
        #expect(OnboardingProfile.recommendDailyStepGoal(movement: .underThreeThousand, outcomes: outcomes) == 6_000)
    }

    @Test("The recommendation is persisted and survives a round trip")
    func persistedRecommendation() throws {
        let profile = OnboardingProfile(
            desiredOutcomes: [.walkMore, .beMoreIntentional],
            scrolling: .twoToFourHours,
            movement: .underThreeThousand
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(OnboardingProfile.self, from: data)
        #expect(decoded == profile)
        #expect(decoded.recommendedDailyStepGoal == 8_000)
        #expect(String(decoding: data, as: UTF8.self).contains("twoToFourHours"))
    }

    @Test("Changing an answer refreshes the persisted recommendation")
    func changedAnswerRefreshesRecommendation() {
        var profile = OnboardingProfile(
            desiredOutcomes: [.scrollLess],
            scrolling: .underOneHour,
            movement: .underThreeThousand
        )
        #expect(profile.recommendedDailyStepGoal == 6_000)
        profile.desiredOutcomes.insert(.walkMore)
        #expect(profile.recommendedDailyStepGoal == 8_000)
        profile.movement = .threeToFiveThousand
        #expect(profile.recommendedDailyStepGoal == 10_000)
    }

    @Test("Completion requires all new answers and a recommendation")
    func completion() {
        #expect(OnboardingProfile().isComplete == false)
        #expect(OnboardingProfile(
            desiredOutcomes: [.scrollLess],
            scrolling: .underOneHour,
            movement: .unsure
        ).isComplete)
    }
}

@Suite("The 30-day projection")
struct ProjectionTests {
    @Test("Projection is goal times thirty without an invented uplift")
    func goalTotals() {
        let projection = Projection(currentDailySteps: 11_000, goalDailySteps: 6_000)
        #expect(Projection.horizonDays == 30)
        #expect(projection.dailySteps == 6_000)
        #expect(projection.totalSteps == 180_000)
        #expect(projection.totalKilometres == 135)
        #expect(projection.marathons == 3)
        #expect(projection.earnedMinutes == 900)
    }

    @Test("Milestone remainders do not carry between days")
    func wholeMilestonesPerDay() {
        let rule = EarningRule(source: .steps, amountRequired: 1_000, rewardSeconds: 300)
        let projection = Projection(goalDailySteps: 1_900, rule: rule, days: 3)
        #expect(projection.totalSteps == 5_700)
        #expect(projection.earnedMinutes == 15)
    }

    @Test("A profile uses its persisted recommendation")
    func profileRecommendation() {
        let profile = OnboardingProfile(
            desiredOutcomes: [.walkMore],
            scrolling: .oneToTwoHours,
            movement: .threeToFiveThousand,
            recommendedDailyStepGoal: 9_000
        )
        #expect(Projection(profile: profile) == Projection(currentDailySteps: 4_000, goalDailySteps: 9_000))
    }

    @Test("Compatibility projection properties expose baseline uplift")
    func compatibilityProperties() {
        let projection = Projection(currentDailySteps: 6_000, goalDailySteps: 8_000)
        #expect(projection.extraStepsPerDay == 2_000)
        #expect(projection.extraSteps == 60_000)
        #expect(projection.extraKilometres == 45)
        #expect(projection.walkingMinutes == 2_400)
        #expect(projection.upliftWalkingMinutes == 600)
    }
}

@Suite("Adaptive goal recommendation")
struct GoalRecommendationTests {
    @Test("Observed baselines produce conservative rounded goals", arguments: [
        (1_500, 2_000), (2_500, 3_000), (3_500, 4_000), (5_000, 6_000),
        (7_000, 8_000), (9_000, 10_000), (12_000, 13_000)
    ])
    func recommendations(baseline: Int, expected: Int) {
        let goal = GoalRecommendationEngine.recommend(forBaseline: baseline)
        #expect(goal == expected)
        #expect(goal == GoalRecommendationEngine.minimumGoal || goal - baseline <= min(baseline / 4, 1_500))
        #expect(goal.isMultiple(of: 500))
    }

    @Test("A measured baseline is persisted without breaking legacy profile behavior")
    func profileBaselineRoundTrip() throws {
        let profile = OnboardingProfile(
            desiredOutcomes: [.walkMore],
            scrolling: .oneToTwoHours,
            movement: .underThreeThousand,
            baselineDailySteps: 5_000
        )
        let decoded = try JSONDecoder().decode(OnboardingProfile.self, from: JSONEncoder().encode(profile))
        #expect(decoded == profile)
        #expect(decoded.currentDailySteps == 5_000)
        #expect(decoded.dailyStepGoal == 6_000)
    }
}

@Suite("Seven-day goal progression")
struct GoalProgressionTests {
    @Test("Only six or seven successful days increase and two or fewer decrease", arguments: [
        (7, 8_500 as Int?), (6, 8_500), (5, nil), (3, nil), (2, 7_500), (0, 7_500)
    ])
    func progression(successes: Int, expected: Int?) {
        let activities = (0..<7).map { offset in
            DailyActivity(
                day: DayKey(year: 2026, month: 8, day: offset + 1),
                steps: offset < successes ? 8_000 : 7_999,
                goal: 8_000
            )
        }
        #expect(GoalProgressionEngine.recommendation(currentGoal: 8_000, activities: activities) == expected)
    }

    @Test("Anything other than exactly seven days is ignored and decreases stop at two thousand")
    func exactWindowAndFloor() {
        let missed = (0..<7).map {
            DailyActivity(day: DayKey(year: 2026, month: 8, day: $0 + 1), steps: 0, goal: 2_000)
        }
        #expect(GoalProgressionEngine.recommendation(currentGoal: 2_000, activities: Array(missed.dropLast())) == nil)
        #expect(GoalProgressionEngine.recommendation(currentGoal: 2_000, activities: missed) == 2_000)
    }
}
