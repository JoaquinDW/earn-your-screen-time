import Foundation
import Testing
@testable import EarnDomain

@Suite("When to ask for an App Store rating")
struct ReviewPromptPolicyTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func state(unlocks: Int, requests: Int = 0, lastRequest: Date? = nil) -> SharedState {
        var state = SharedState.initial(day: DayKey(date: now))
        state.onboardingCompleted = true
        state.successfulUnlockCount = unlocks
        state.reviewPromptRequestCount = requests
        state.lastReviewPromptRequestedAt = lastRequest
        return state
    }

    @Test("Never during onboarding")
    func notDuringOnboarding() {
        var state = state(unlocks: 3)
        state.onboardingCompleted = false
        #expect(!ReviewPromptPolicy.shouldRequest(at: .activeRewardEarned, in: state, now: now))
    }

    @Test("The first unlock is not the moment, the second is")
    func secondUnlockQualifies() {
        #expect(!ReviewPromptPolicy.shouldRequest(at: .unlockStarted, in: state(unlocks: 1), now: now))
        #expect(ReviewPromptPolicy.shouldRequest(at: .unlockStarted, in: state(unlocks: 2), now: now))
    }

    @Test("Earning minutes qualifies once there has been one unlock")
    func earningAfterOneUnlock() {
        #expect(!ReviewPromptPolicy.shouldRequest(at: .activeRewardEarned, in: state(unlocks: 0), now: now))
        #expect(ReviewPromptPolicy.shouldRequest(at: .activeRewardEarned, in: state(unlocks: 1), now: now))
        #expect(ReviewPromptPolicy.shouldRequest(at: .dailyGoalCompleted, in: state(unlocks: 1), now: now))
    }

    @Test("A second request waits two weeks after the first")
    func secondRequestWaits() {
        let thirteenDaysAgo = now.addingTimeInterval(-13 * 24 * 60 * 60)
        let fourteenDaysAgo = now.addingTimeInterval(-14 * 24 * 60 * 60)
        #expect(!ReviewPromptPolicy.shouldRequest(
            at: .unlockStarted,
            in: state(unlocks: 5, requests: 1, lastRequest: thirteenDaysAgo),
            now: now
        ))
        #expect(ReviewPromptPolicy.shouldRequest(
            at: .unlockStarted,
            in: state(unlocks: 5, requests: 1, lastRequest: fourteenDaysAgo),
            now: now
        ))
    }

    @Test("A request migrated without a date may be followed by one more")
    func undatedRequestAllowsOneMore() {
        #expect(ReviewPromptPolicy.shouldRequest(at: .unlockStarted, in: state(unlocks: 5, requests: 1), now: now))
    }

    @Test("Never more than two requests per install")
    func capsAtTwo() {
        let longAgo = now.addingTimeInterval(-90 * 24 * 60 * 60)
        #expect(!ReviewPromptPolicy.shouldRequest(
            at: .unlockStarted,
            in: state(unlocks: 9, requests: 2, lastRequest: longAgo),
            now: now
        ))
    }
}
