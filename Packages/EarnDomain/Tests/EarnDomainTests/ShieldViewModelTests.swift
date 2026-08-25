import Foundation
import Testing
@testable import EarnDomain

@Suite("Shield presentation")
struct ShieldViewModelTests {
    private let now = Date(timeIntervalSince1970: 1_787_342_400)

    @Test("No activity starts in no-time state")
    func noTime() {
        let viewModel = ShieldViewModel(sharedState: state(steps: 0), now: now)

        #expect(viewModel.state == .noTime)
        #expect(viewModel.stepsRemaining == 1_000)
        #expect(viewModel.estimatedWalkMinutes == 10)
    }

    @Test("Partial activity has a normal progress state")
    func progress() {
        let viewModel = ShieldViewModel(sharedState: state(steps: 420), now: now)

        #expect(viewModel.state == .progress)
        #expect(viewModel.progress == 0.42)
        #expect(viewModel.targetSteps == 1_000)
    }

    @Test("The final quarter is almost there")
    func almostThere() {
        let viewModel = ShieldViewModel(sharedState: state(steps: 780), now: now)

        #expect(viewModel.state == .almostThere)
        #expect(viewModel.stepsRemaining == 220)
        #expect(viewModel.estimatedWalkMinutes == 2)
    }

    @Test("Banked time is presented as a reward")
    func rewardAvailable() {
        var state = state(steps: 1_000)
        state.ledger.wallet = ScreenTimeWallet(earnedSeconds: 900)

        let viewModel = ShieldViewModel(sharedState: state, now: now)

        #expect(viewModel.state == .rewardAvailable)
        #expect(viewModel.availableMinutes == 15)
    }

    @Test("A just-completed session takes precedence over a remaining balance")
    func sessionExpired() {
        var state = state(steps: 1_000)
        state.ledger.wallet = ScreenTimeWallet(earnedSeconds: 1_200, consumedSeconds: 900)
        state.currentSession = ScreenTimeSession(
            startedAt: now.addingTimeInterval(-15 * 60 - 30),
            durationMinutes: 15,
            status: .completed
        )

        let viewModel = ShieldViewModel(sharedState: state, now: now)

        #expect(viewModel.state == .sessionExpired)
        #expect(viewModel.sessionDurationMinutes == 15)
    }

    @Test("A completed daily target remains meaningful after time is spent")
    func dailyGoalCompleted() {
        var state = state(steps: 8_000)
        state.ledger.wallet = ScreenTimeWallet(earnedSeconds: 2_400, consumedSeconds: 2_400)

        let viewModel = ShieldViewModel(sharedState: state, now: now)

        #expect(viewModel.state == .dailyGoalCompleted)
        #expect(viewModel.dailyGoalCompleted)
        #expect(viewModel.earnedMinutesToday == 40)
    }

    private func state(steps: Int) -> SharedState {
        var state = SharedState.initial(day: DayKey(year: 2026, month: 8, day: 22))
        state.ledger.activityAmount = steps
        state.ledger.milestonesRewarded = steps / state.ledger.rule.amountRequired
        state.lastActivitySyncAt = now
        return state
    }
}
