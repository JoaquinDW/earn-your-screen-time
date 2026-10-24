import Foundation
import Testing
@testable import EarnDomain

@Suite("Free daily unlock before the paywall")
struct FreePreviewTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var nextDay: Date { Calendar.current.date(byAdding: .day, value: 1, to: start)! }

    @Test("A new install is in the preview until it unlocks once")
    func newInstallIsPreviewing() {
        let state = SharedState.initial(day: DayKey(date: start))
        #expect(!state.hasUsedFreeUnlock(on: DayKey(date: start)))
        #expect(state.isFreePreviewActive(at: start))
    }

    @Test("The day's session keeps the preview open until it ends")
    func firstSessionRunsToTheEnd() {
        var state = SharedState.initial(day: DayKey(date: start))
        state.firstRealUnlockTracked = true
        state.successfulUnlockCount = 1
        state.currentSession = ScreenTimeSession(startedAt: start, durationMinutes: 5)

        #expect(state.isFreePreviewActive(at: start.addingTimeInterval(4 * 60)))
        #expect(!state.isFreePreviewActive(at: start.addingTimeInterval(5 * 60)))
    }

    @Test("A session ended early closes the preview for the day")
    func endedSessionClosesPreview() {
        var state = SharedState.initial(day: DayKey(date: start))
        state.successfulUnlockCount = 1
        state.ledger.sessionCount = 1
        state.currentSession = ScreenTimeSession(startedAt: start, durationMinutes: 15, status: .completed)

        #expect(!state.isFreePreviewActive(at: start.addingTimeInterval(60)))
    }

    @Test("The free unlock comes back the next day")
    func unlockReturnsTomorrow() {
        var state = SharedState.initial(day: DayKey(date: start))
        state.successfulUnlockCount = 1
        state.ledger.sessionCount = 1
        state.currentSession = ScreenTimeSession(startedAt: start, durationMinutes: 5, status: .completed)

        #expect(!state.isFreePreviewActive(at: start.addingTimeInterval(60)))
        // The ledger still holds yesterday until the app rolls the day over.
        #expect(state.isFreePreviewActive(at: nextDay))

        state.ledger = CreditEngine.startOfDay(DayKey(date: nextDay), rule: state.ledger.rule)
        #expect(state.isFreePreviewActive(at: nextDay))
    }

    /// The extension settles an expired session on its own schedule. Until it does, the
    /// session's start date alone must stop a second free unlock the same day.
    @Test("An expired, unsettled session still uses the day's unlock")
    func unsettledSessionCounts() {
        var state = SharedState.initial(day: DayKey(date: start))
        state.currentSession = ScreenTimeSession(startedAt: start, durationMinutes: 5)

        #expect(state.ledger.sessionCount == 0)
        #expect(!state.isFreePreviewActive(at: start.addingTimeInterval(10 * 60)))
    }
}
