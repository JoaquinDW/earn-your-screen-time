import Foundation
import Testing
@testable import EarnDomain

@Suite("Free preview before the paywall")
struct FreePreviewTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("A new install is in the preview until it unlocks once")
    func newInstallIsPreviewing() {
        let state = SharedState.initial(day: DayKey(date: start))
        #expect(!state.hasSpentFreeUnlock)
        #expect(state.isFreePreviewActive(at: start))
    }

    @Test("The first session keeps the preview open until it ends")
    func firstSessionRunsToTheEnd() {
        var state = SharedState.initial(day: DayKey(date: start))
        state.firstRealUnlockTracked = true
        state.successfulUnlockCount = 1
        state.currentSession = ScreenTimeSession(startedAt: start, durationMinutes: 5)

        #expect(state.isFreePreviewActive(at: start.addingTimeInterval(4 * 60)))
        #expect(!state.isFreePreviewActive(at: start.addingTimeInterval(5 * 60)))
    }

    @Test("A session ended early closes the preview")
    func endedSessionClosesPreview() {
        var state = SharedState.initial(day: DayKey(date: start))
        state.successfulUnlockCount = 1
        state.currentSession = ScreenTimeSession(startedAt: start, durationMinutes: 15, status: .completed)

        #expect(!state.isFreePreviewActive(at: start.addingTimeInterval(60)))
    }

    /// Users migrated from before v11 had `firstRealUnlockTracked` inferred from spent minutes
    /// but no unlock count, and must not get a second free unlock after the upgrade.
    @Test("A migrated unlock flag alone counts as the free unlock")
    func migratedFlagCounts() {
        var state = SharedState.initial(day: DayKey(date: start))
        state.firstRealUnlockTracked = true

        #expect(state.hasSpentFreeUnlock)
        #expect(!state.isFreePreviewActive(at: start))
    }
}
