import Foundation
import Testing
@testable import EarnDomain

@Suite("Shared state schema migration")
struct SharedStateMigrationTests {

    @Test("The onboarding answers and history survive a round trip")
    func roundTripKeepsNewFields() throws {
        var state = SharedState.initial(day: DayKey(year: 2026, month: 8, day: 20))
        state.onboarding = OnboardingProfile(goal: .scrollLess, scrolling: .twoToThreeHours,
                                             walking: .fiveToSevenFiveThousand, target: .tenThousand)
        state.history.record(DaySummary(day: DayKey(year: 2026, month: 8, day: 19),
                                        activityAmount: 5_000, earnedSeconds: 1_500))
        state.onboardingCompleted = true

        let decoded = try SharedState.decoded(from: state.encoded())
        #expect(decoded == state)
        #expect(decoded.dailyStepGoal == 10_000)
    }

    /// The upgrade path that matters: a user mid-day on the old build must not lose their balance.
    @Test("State written before the onboarding answers existed still decodes, ledger intact")
    func decodesV1() throws {
        let v1 = """
        {
          "schemaVersion": 1,
          "onboardingCompleted": true,
          "restrictedItemCount": 3,
          "shieldsApplied": false,
          "ledger": {
            "day": { "year": 2026, "month": 8, "day": 20 },
            "rule": { "source": "steps", "amountRequired": 1000, "rewardSeconds": 300 },
            "activityAmount": 3842,
            "baselineAmount": 0,
            "milestonesRewarded": 3,
            "wallet": { "earnedSeconds": 900, "consumedSeconds": 300 }
          }
        }
        """

        let state = try SharedState.decoded(from: Data(v1.utf8))
        #expect(state.ledger.wallet.availableSeconds == 600)
        #expect(state.ledger.milestonesRewarded == 3)
        #expect(state.restrictedItemCount == 3)
        #expect(state.onboarding == OnboardingProfile())
        #expect(state.history.days.isEmpty)
        #expect(state.dailyStepGoal == 8_000)
        #expect(state.schemaVersion == 4)
        #expect(state.currentSession == nil)
        #expect(state.journey == nil)
        // A legacy unshielded flag cannot fabricate an access session with no fixed end.
        #expect(state.shieldsApplied == false)
    }

    @Test("Legacy profile raw values map to outcomes, movement, and StepTarget")
    func mapsLegacyProfile() throws {
        let json = """
        {
          "goal": "healthierHabits",
          "scrolling": "threeToFourHours",
          "walking": "fiveToSevenFiveThousand",
          "target": "somethingElse"
        }
        """
        let profile = try JSONDecoder().decode(OnboardingProfile.self, from: Data(json.utf8))
        #expect(profile.desiredOutcomes == [.beMoreActive])
        #expect(profile.scrolling == .twoToFourHours)
        #expect(profile.movement == .fiveToEightThousand)
        #expect(profile.recommendedDailyStepGoal == 9_000)
    }

    @Test("Every legacy StepTarget keeps its old numeric meaning", arguments: [
        ("sixThousand", 6_000),
        ("eightThousand", 8_000),
        ("tenThousand", 10_000),
        ("somethingElse", 9_000)
    ])
    func mapsLegacyTargets(raw: String, expected: Int) throws {
        let json = "{\"walking\":\"twoToFiveThousand\",\"target\":\"\(raw)\"}"
        let profile = try JSONDecoder().decode(OnboardingProfile.self, from: Data(json.utf8))
        #expect(profile.recommendedDailyStepGoal == expected)
    }

    @Test("Every old single goal maps without rejecting persisted JSON", arguments: [
        ("walkMore", Set([OnboardingProfile.DesiredOutcome.walkMore])),
        ("scrollLess", Set([.scrollLess])),
        ("intentional", Set([.beMoreIntentional])),
        ("healthierHabits", Set([.beMoreActive])),
        ("everything", Set(OnboardingProfile.DesiredOutcome.allCases))
    ])
    func mapsLegacyGoals(raw: String, expected: Set<OnboardingProfile.DesiredOutcome>) throws {
        let profile = try JSONDecoder().decode(OnboardingProfile.self, from: Data("{\"goal\":\"\(raw)\"}".utf8))
        #expect(profile.desiredOutcomes == expected)
    }

    @Test("A v4 journey round trip remains optional and preserves the ledger")
    func journeyRoundTrip() throws {
        var state = SharedState.initial(day: DayKey(year: 2026, month: 8, day: 20))
        state.ledger.wallet = ScreenTimeWallet(earnedSeconds: 1_200, consumedSeconds: 300)
        state.journey = ThirtyDayJourney(startDay: state.ledger.day, dailyGoal: 8_000)
            .incorporating(DaySummary(day: state.ledger.day, activityAmount: 8_100, earnedSeconds: 2_400))

        let decoded = try SharedState.decoded(from: state.encoded())
        #expect(decoded == state)
        #expect(decoded.ledger.wallet.availableSeconds == 900)
    }
}
