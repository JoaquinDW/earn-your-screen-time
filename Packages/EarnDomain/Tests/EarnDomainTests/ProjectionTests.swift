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
        #expect(Projection(profile: profile) == Projection(goalDailySteps: 9_000))
    }

    @Test("Compatibility projection properties expose the new totals")
    func compatibilityProperties() {
        let projection = Projection(goalDailySteps: 8_000)
        #expect(projection.extraStepsPerDay == projection.dailySteps)
        #expect(projection.extraSteps == projection.totalSteps)
        #expect(projection.extraKilometres == projection.totalKilometres)
    }
}
