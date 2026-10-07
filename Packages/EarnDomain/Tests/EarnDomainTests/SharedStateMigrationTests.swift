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
        #expect(state.schemaVersion == SharedState.currentSchemaVersion)
        #expect(state.currentSession == nil)
        #expect(state.journey == nil)
        #expect(state.ledger.dailyGoal == 0)
        #expect(state.ledger.goalBonusSeconds == 0)
        #expect(state.ledger.transactions.isEmpty)
        #expect(!state.hasEarnedFirstReward)
        #expect(state.goalProgressionCooldownUntil == nil)
        // An install from before Pushups to Earn must still be owed the announcement.
        #expect(!state.pushupsIntroSeen)
        // A legacy unshielded flag cannot fabricate an access session with no fixed end.
        #expect(state.shieldsApplied == false)
    }

    @Test("A v5 active session becomes a refundable reservation without changing balance")
    func migratesActiveReservation() throws {
        let v5 = """
        {
          "schemaVersion": 5,
          "ledger": {
            "day": { "year": 2027, "month": 1, "day": 15 },
            "wallet": { "earnedSeconds": 900, "consumedSeconds": 300 }
          },
          "currentSession": {
            "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "startedAt": "2027-01-15T08:00:00Z",
            "durationMinutes": 5,
            "endsAt": "2027-01-15T08:05:00Z",
            "status": "active",
            "spentSeconds": 300
          }
        }
        """

        let state = try SharedState.decoded(from: Data(v5.utf8))
        #expect(state.ledger.wallet.availableSeconds == 600)
        #expect(state.ledger.wallet.consumedSeconds == 0)
        #expect(state.ledger.wallet.reservedSeconds == 300)
        #expect(state.currentSession?.reservedSeconds == 300)
    }

    @Test("Adaptive profile, first reward, cooldown, bonus, and audit state survive a round trip")
    func adaptiveStateRoundTrip() throws {
        let day = DayKey(year: 2026, month: 8, day: 20)
        var state = SharedState(
            ledger: CreditEngine.startOfDay(day, rule: .default, dailyGoal: 2_500, goalBonusSeconds: 600),
            onboarding: OnboardingProfile(desiredOutcomes: [.walkMore], baselineDailySteps: 2_000),
            hasEarnedFirstReward: true,
            goalProgressionCooldownUntil: DayKey(year: 2026, month: 8, day: 27)
        )
        state.ledger = CreditEngine.apply(activityAmount: 2_500, to: state.ledger).ledger

        let decoded = try SharedState.decoded(from: state.encoded())
        #expect(decoded == state)
        #expect(decoded.ledger.goalBonusAwarded)
        #expect(decoded.ledger.transactions.count == 2)
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
        #expect(profile.previousAttempt == nil)
    }

    @Test("A profile written before previous-attempt tracking keeps every existing field")
    func profileWithoutPreviousAttempt() throws {
        let json = """
        {
          "desiredOutcomes": ["walkMore", "feelInControl"],
          "scrolling": "oneToTwoHours",
          "movement": "threeToFiveThousand",
          "recommendedDailyStepGoal": 9000,
          "baselineDailySteps": 4200,
          "baselineSource": "selfReported",
          "primaryGoal": "moveMore"
        }
        """

        let profile = try JSONDecoder().decode(OnboardingProfile.self, from: Data(json.utf8))
        #expect(profile.previousAttempt == nil)
        #expect(profile.desiredOutcomes == [.walkMore, .feelInControl])
        #expect(profile.scrolling == .oneToTwoHours)
        #expect(profile.movement == .threeToFiveThousand)
        #expect(profile.recommendedDailyStepGoal == 9_000)
        #expect(profile.baselineDailySteps == 4_200)
        #expect(profile.baselineSource == .selfReported)
        #expect(profile.primaryGoal == .moveMore)
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

    @Test("A v6 state defaults study fields without changing its wallet")
    func migratesV6PreservingWallet() throws {
        let v6 = """
        {
          "schemaVersion": 6,
          "ledger": {
            "day": { "year": 2027, "month": 2, "day": 10 },
            "activityAmount": 2000,
            "milestonesRewarded": 2,
            "wallet": {
              "carriedSeconds": 300,
              "earnedSeconds": 1200,
              "consumedSeconds": 600,
              "reservedSeconds": 300
            }
          },
          "history": {
            "days": [{
              "day": { "year": 2027, "month": 2, "day": 9 },
              "activityAmount": 4000,
              "earnedSeconds": 1200
            }]
          }
        }
        """

        let state = try SharedState.decoded(from: Data(v6.utf8))
        #expect(state.schemaVersion == SharedState.currentSchemaVersion)
        #expect(state.ledger.wallet.carriedSeconds == 300)
        #expect(state.ledger.wallet.earnedSeconds == 1_200)
        #expect(state.ledger.wallet.consumedSeconds == 600)
        #expect(state.ledger.wallet.reservedSeconds == 300)
        #expect(state.ledger.wallet.availableSeconds == 600)
        #expect(state.appliedStudyReceiptIDs.isEmpty)
        #expect(state.ledger.rewardTransactions.isEmpty)
        #expect(state.history.days.first?.stepEarnedSeconds == 1_200)
        #expect(state.history.days.first?.studyEarnedSeconds == 0)
        #expect(state.history.days.first?.pushupEarnedSeconds == 0)
        #expect(state.history.days.first?.hasUsageData == false)
    }

    @Test("A v8 Study receipt list migrates to generic IDs despite malformed optional fields")
    func migratesV8RewardIDsTolerantly() throws {
        let receiptID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let v8 = """
        {
          "schemaVersion": 8,
          "ledger": {
            "day": { "year": 2027, "month": 2, "day": 10 },
            "wallet": { "earnedSeconds": 900 }
          },
          "appliedStudyReceiptIDs": ["\(receiptID.uuidString)"],
          "appliedRewardIDs": "not-an-array"
        }
        """

        let state = try SharedState.decoded(from: Data(v8.utf8))
        #expect(state.schemaVersion == SharedState.currentSchemaVersion)
        #expect(state.ledger.wallet.earnedSeconds == 900)
        #expect(state.appliedRewardIDs == [receiptID])
        #expect(state.appliedStudyReceiptIDs == [receiptID])
    }

    @Test("The onboarding demo outcome survives a round trip")
    func roundTripsTheOnboardingDemoOutcome() throws {
        var state = SharedState.initial(day: DayKey(year: 2026, month: 9, day: 17))
        state.onboardingPushupDemo = .completed
        state.firstAppBlockedTracked = true

        let decoded = try SharedState.decoded(from: state.encoded())

        #expect(decoded.onboardingPushupDemo == .completed)
        #expect(decoded.firstAppBlockedTracked)
        #expect(!decoded.firstRealUnlockTracked)
        #expect(decoded == state)
    }

    /// The activation funnel starts at v11, so an install that already blocks apps and has
    /// already spent minutes must not report either "first" the day it upgrades.
    @Test("A pre-v11 install with apps and spent minutes starts with the funnel latched")
    func migratesV10ActivationLatches() throws {
        let v10 = """
        {
          "schemaVersion": 10,
          "restrictedItemCount": 4,
          "ledger": {
            "day": { "year": 2027, "month": 2, "day": 11 },
            "wallet": { "earnedSeconds": 1200, "consumedSeconds": 300 }
          }
        }
        """

        let state = try SharedState.decoded(from: Data(v10.utf8))

        #expect(state.schemaVersion == SharedState.currentSchemaVersion)
        #expect(state.onboardingPushupDemo == .notAttempted)
        #expect(state.firstAppBlockedTracked)
        #expect(state.firstRealUnlockTracked)
    }

    @Test("The successful-unlock count and review-prompt latch survive a round trip")
    func roundTripsReviewPromptState() throws {
        var state = SharedState.initial(day: DayKey(year: 2026, month: 9, day: 17))
        state.successfulUnlockCount = 3
        state.reviewPromptRequested = true

        let decoded = try SharedState.decoded(from: state.encoded())

        #expect(decoded.successfulUnlockCount == 3)
        #expect(decoded.reviewPromptRequested)
        #expect(decoded == state)
    }

    @Test("The free push-up reward latch survives a round trip and defaults to unused")
    func freePushupsRewardLatch() throws {
        let v13 = """
        {
          "schemaVersion": 13,
          "ledger": {
            "day": { "year": 2026, "month": 9, "day": 28 },
            "wallet": { "earnedSeconds": 300 }
          }
        }
        """
        var state = try SharedState.decoded(from: Data(v13.utf8))
        #expect(!state.freePushupsRewardClaimed)
        #expect(state.ledger.wallet.earnedSeconds == 300)

        state.freePushupsRewardClaimed = true
        let decoded = try SharedState.decoded(from: state.encoded())
        #expect(decoded.freePushupsRewardClaimed)
        #expect(decoded == state)
    }

    @Test("A pre-v14 install that already redeemed a server reward starts with the active-reward latch set")
    func migratesV13ActiveRewardLatch() throws {
        let v13 = """
        {
          "schemaVersion": 13,
          "ledger": {
            "day": { "year": 2027, "month": 2, "day": 11 },
            "wallet": { "earnedSeconds": 300 }
          },
          "appliedRewardIDs": ["7C1A4E0B-2F5D-4B8E-9C3A-1D2E3F4A5B6C"]
        }
        """
        let state = try SharedState.decoded(from: Data(v13.utf8))
        #expect(state.firstActiveRewardTracked)
        #expect(state.ledger.wallet.earnedSeconds == 300)
    }

    @Test("A pre-v14 install with only step rewards can still report its first active reward")
    func migratesV13WithoutActiveReward() throws {
        let v13 = """
        {
          "schemaVersion": 13,
          "ledger": {
            "day": { "year": 2027, "month": 2, "day": 11 },
            "wallet": { "earnedSeconds": 600 }
          },
          "hasEarnedFirstReward": true
        }
        """
        var state = try SharedState.decoded(from: Data(v13.utf8))
        #expect(!state.firstActiveRewardTracked)

        state.firstActiveRewardTracked = true
        let decoded = try SharedState.decoded(from: state.encoded())
        #expect(decoded.firstActiveRewardTracked)
        #expect(decoded == state)
    }

    @Test("A pre-v12 install starts with no unlocks counted and the review prompt not yet requested")
    func migratesV11WithoutReviewPromptState() throws {
        let v11 = """
        {
          "schemaVersion": 11,
          "ledger": {
            "day": { "year": 2027, "month": 2, "day": 11 },
            "wallet": { "earnedSeconds": 600 }
          }
        }
        """

        let state = try SharedState.decoded(from: Data(v11.utf8))

        #expect(state.successfulUnlockCount == 0)
        #expect(!state.reviewPromptRequested)
        #expect(state.ledger.sessionCount == 0)
        #expect(state.ledger.returnedSessionSeconds == 0)
    }

    @Test("A pre-v11 install that never blocked an app can still report its first")
    func migratesV10WithoutFalseLatches() throws {
        let v10 = """
        {
          "schemaVersion": 10,
          "restrictedItemCount": 0,
          "ledger": {
            "day": { "year": 2027, "month": 2, "day": 11 },
            "wallet": { "earnedSeconds": 600 }
          }
        }
        """

        let state = try SharedState.decoded(from: Data(v10.utf8))

        #expect(!state.firstAppBlockedTracked)
        #expect(!state.firstRealUnlockTracked)
    }
}
