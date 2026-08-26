import Foundation
import Testing
@testable import EarnDomain

private let sessionNow = Date(timeIntervalSince1970: 1_800_000_000)

@Suite("DeviceActivity session plan")
struct MonitorPlanTests {
    @Test("Five minutes complete ten minutes before the carrier ends")
    func fiveMinutes() {
        let session = ScreenTimeSession(startedAt: sessionNow, durationMinutes: 5)
        let plan = SessionMonitorPlan.make(for: session, at: sessionNow)
        #expect(plan?.remainingSeconds == 300)
        #expect(plan?.warningSeconds == 600)
        #expect(plan?.scheduleSeconds == 900)
    }

    @Test("Long sessions end with their own schedule")
    func longSession() {
        let session = ScreenTimeSession(startedAt: sessionNow, durationMinutes: 90)
        let plan = SessionMonitorPlan.make(for: session, at: sessionNow)
        #expect(plan?.remainingSeconds == 5_400)
        #expect(plan?.scheduleSeconds == 5_400)
        #expect(plan?.warningSeconds == nil)
    }

    @Test("Ten minutes complete five minutes before the carrier ends")
    func tenMinutes() {
        let session = ScreenTimeSession(startedAt: sessionNow, durationMinutes: 10)
        let plan = SessionMonitorPlan.make(for: session, at: sessionNow)
        #expect(plan?.remainingSeconds == 600)
        #expect(plan?.warningSeconds == 300)
    }

    @Test("Fifteen minutes complete at the carrier interval end")
    func fifteenMinutes() {
        let session = ScreenTimeSession(startedAt: sessionNow, durationMinutes: 15)
        let plan = SessionMonitorPlan.make(for: session, at: sessionNow)
        #expect(plan?.remainingSeconds == 900)
        #expect(plan?.warningSeconds == nil)
    }

    @Test("Recovery schedules only the remaining wall-clock time")
    func recovery() {
        let session = ScreenTimeSession(startedAt: sessionNow, durationMinutes: 5)
        let plan = SessionMonitorPlan.make(
            for: session,
            at: sessionNow.addingTimeInterval(180)
        )
        #expect(plan?.remainingSeconds == 120)
        #expect(plan?.warningSeconds == 780)
    }

    @Test("Expired sessions produce no monitoring plan")
    func expired() {
        let session = ScreenTimeSession(startedAt: sessionNow, durationMinutes: 5)
        #expect(SessionMonitorPlan.make(
            for: session,
            at: sessionNow.addingTimeInterval(300)
        ) == nil)
    }

    @Test("Activity names carry the session identity")
    func activityNameRoundTrip() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let name = SessionMonitorPlan.activityName(for: id)
        #expect(SessionMonitorPlan.sessionID(fromActivityName: name) == id)
        #expect(SessionMonitorPlan.sessionID(fromActivityName: "earnYourScreenTimeDaily") == nil)
    }
}

@Suite("Discrete access sessions")
struct ScreenTimeSessionTests {
    private func creditedState(minutes: Int = 10) -> SharedState {
        var state = SharedState.initial(day: DayKey(year: 2027, month: 1, day: 15))
        state.ledger.wallet.credit(seconds: minutes * 60)
        return state
    }

    private var fiveMinutesBeforeMidnight: Date {
        Calendar.current.date(from: DateComponents(
            year: 2027,
            month: 1,
            day: 15,
            hour: 23,
            minute: 55
        ))!
    }

    @Test("Banked credit does not create access")
    func creditDoesNotStartSession() {
        let state = creditedState()
        #expect(state.ledger.wallet.availableMinutes == 10)
        #expect(state.activeSession(at: sessionNow) == nil)
    }

    @Test("Starting reserves the whole session immediately")
    func startsAndSpends() throws {
        let state = try ScreenTimeSessionEngine.start(
            durationMinutes: 5,
            at: sessionNow,
            in: creditedState()
        )
        #expect(state.ledger.wallet.availableMinutes == 5)
        #expect(state.activeSession(at: sessionNow)?.durationMinutes == 5)
        #expect(state.currentSession?.spentSeconds == 300)
        #expect(state.ledger.wallet.reservedSeconds == 300)
        #expect(state.ledger.wallet.consumedSeconds == 0)
    }

    @Test("A session cannot exceed the available balance")
    func insufficientBalance() {
        #expect(throws: ScreenTimeSessionError.insufficientBalance) {
            try ScreenTimeSessionEngine.start(
                durationMinutes: 10,
                at: sessionNow,
                in: creditedState(minutes: 5)
            )
        }
    }

    @Test("The full balance remains startable shortly before midnight")
    func crossingMidnightIsStartable() throws {
        let date = fiveMinutesBeforeMidnight
        let available = ScreenTimeSessionEngine.maximumStartableMinutes(
            availableMinutes: 20,
            at: date
        )
        let active = try ScreenTimeSessionEngine.start(
            durationMinutes: 20,
            at: date,
            in: creditedState(minutes: 20)
        )

        #expect(available == 20)
        #expect(active.currentSession?.endsAt == date.addingTimeInterval(1_200))
    }

    @Test("A session cannot use more than twenty minutes after midnight")
    func crossingMidnightCarryLimit() {
        #expect(throws: ScreenTimeSessionError.exceedsCarryOverWindow) {
            try ScreenTimeSessionEngine.start(
                durationMinutes: 26,
                at: fiveMinutesBeforeMidnight,
                in: creditedState(minutes: 30)
            )
        }
    }

    @Test("A crossing session is charged once across both daily wallets")
    func crossingMidnightSettlement() throws {
        let startedAt = fiveMinutesBeforeMidnight
        let boundary = Calendar.current.dateInterval(of: .day, for: startedAt)!.end
        var active = try ScreenTimeSessionEngine.start(
            durationMinutes: 20,
            at: startedAt,
            in: creditedState(minutes: 20)
        )

        active = ScreenTimeSessionEngine.settleActiveSessionThrough(in: active, at: boundary)
        #expect(active.currentSession?.status == .active)
        #expect(active.currentSession?.consumedSeconds == 300)
        #expect(active.ledger.wallet.consumedSeconds == 300)
        #expect(active.ledger.wallet.availableSeconds == 900)
        #expect(active.ledger.wallet.reservedSeconds == 0)

        active.ledger = CreditEngine.rollOverIfNeeded(
            active.ledger,
            to: DayKey(date: boundary),
            carryOverSeconds: active.ledger.wallet.remainingValueSeconds
        )
        let didReserveRemainder = active.ledger.wallet.reserve(seconds: 900)
        #expect(didReserveRemainder)

        let completed = ScreenTimeSessionEngine.complete(
            sessionID: active.currentSession!.id,
            in: active,
            at: startedAt.addingTimeInterval(1_200)
        )
        #expect(completed.currentSession?.consumedSeconds == 1_200)
        #expect(completed.ledger.wallet.consumedSeconds == 900)
        #expect(completed.ledger.wallet.reservedSeconds == 0)
        #expect(completed.ledger.walletTransactions.last?.amountSeconds == 900)
    }

    @Test("Pausing after midnight returns the unconsumed remainder")
    func crossingMidnightPause() throws {
        let startedAt = fiveMinutesBeforeMidnight
        let boundary = Calendar.current.dateInterval(of: .day, for: startedAt)!.end
        var active = try ScreenTimeSessionEngine.start(
            durationMinutes: 20,
            at: startedAt,
            in: creditedState(minutes: 20)
        )

        active = ScreenTimeSessionEngine.settleActiveSessionThrough(in: active, at: boundary)
        active.ledger = CreditEngine.rollOverIfNeeded(
            active.ledger,
            to: DayKey(date: boundary),
            carryOverSeconds: active.ledger.wallet.remainingValueSeconds
        )
        let didReserveRemainder = active.ledger.wallet.reserve(seconds: 900)
        #expect(didReserveRemainder)

        let paused = ScreenTimeSessionEngine.pauseActiveSession(
            in: active,
            at: boundary.addingTimeInterval(300)
        )
        #expect(paused.currentSession?.consumedSeconds == 600)
        #expect(paused.currentSession?.savedSeconds == 600)
        #expect(paused.ledger.wallet.consumedSeconds == 300)
        #expect(paused.ledger.wallet.availableSeconds == 600)
        #expect(paused.ledger.walletTransactions.last?.amountSeconds == 300)
    }

    @Test("Only one session can be active")
    func oneAtATime() throws {
        let active = try ScreenTimeSessionEngine.start(
            durationMinutes: 5,
            at: sessionNow,
            in: creditedState(minutes: 15)
        )
        #expect(throws: ScreenTimeSessionError.sessionAlreadyActive) {
            try ScreenTimeSessionEngine.start(
                durationMinutes: 5,
                at: sessionNow.addingTimeInterval(1),
                in: active
            )
        }
    }

    @Test("Completing an old ID cannot close the current session")
    func staleCompletion() throws {
        let active = try ScreenTimeSessionEngine.start(
            durationMinutes: 5,
            at: sessionNow,
            in: creditedState()
        )
        let unchanged = ScreenTimeSessionEngine.complete(sessionID: UUID(), in: active)
        #expect(unchanged.currentSession?.status == .active)
    }

    @Test("Expired sessions recover as completed")
    func expirationRecovery() throws {
        let active = try ScreenTimeSessionEngine.start(
            durationMinutes: 5,
            at: sessionNow,
            in: creditedState()
        )
        let recovered = ScreenTimeSessionEngine.recoverExpiredSession(
            in: active,
            at: sessionNow.addingTimeInterval(300)
        )
        #expect(recovered.currentSession?.status == .completed)
        #expect(recovered.activeSession(at: sessionNow.addingTimeInterval(300)) == nil)
        #expect(recovered.ledger.wallet.availableMinutes == 5)
        #expect(recovered.ledger.wallet.consumedSeconds == 300)
    }

    @Test("Pausing charges elapsed wall-clock time and returns the rest")
    func partialPause() throws {
        let active = try ScreenTimeSessionEngine.start(
            durationMinutes: 5,
            at: sessionNow,
            in: creditedState()
        )
        let paused = ScreenTimeSessionEngine.pauseActiveSession(
            in: active,
            at: sessionNow.addingTimeInterval(120)
        )
        #expect(paused.currentSession?.status == .paused)
        #expect(paused.currentSession?.consumedSeconds == 120)
        #expect(paused.currentSession?.savedSeconds == 180)
        #expect(paused.ledger.wallet.availableSeconds == 480)
        #expect(paused.ledger.wallet.consumedSeconds == 120)
        #expect(paused.ledger.wallet.reservedSeconds == 0)
        #expect(paused.ledger.walletTransactions.last?.kind == .consumed)
    }

    @Test("Pausing twice cannot consume twice")
    func idempotentPause() throws {
        let active = try ScreenTimeSessionEngine.start(
            durationMinutes: 5,
            at: sessionNow,
            in: creditedState()
        )
        let paused = ScreenTimeSessionEngine.pauseActiveSession(
            in: active,
            at: sessionNow.addingTimeInterval(60)
        )
        let repeated = ScreenTimeSessionEngine.pauseActiveSession(
            in: paused,
            at: sessionNow.addingTimeInterval(240)
        )
        #expect(repeated == paused)
    }

    @Test("Earning during a session does not extend its end")
    func earningDoesNotExtendSession() throws {
        var active = try ScreenTimeSessionEngine.start(
            durationMinutes: 5,
            at: sessionNow,
            in: creditedState()
        )
        let originalEnd = active.currentSession?.endsAt
        active.ledger.wallet.credit(seconds: 300)
        #expect(active.currentSession?.endsAt == originalEnd)
        #expect(active.ledger.wallet.availableMinutes == 10)
    }
}

@Suite("Shared state serialization")
struct SharedStateTests {
    @Test("State and its active session survive a JSON round trip")
    func roundTrip() throws {
        var state = SharedState.initial(day: DayKey(year: 2026, month: 8, day: 20))
        state.ledger.wallet.credit(seconds: 900)
        state = try ScreenTimeSessionEngine.start(durationMinutes: 5, at: sessionNow, in: state)
        state.onboardingCompleted = true
        state.restrictedItemCount = 5

        let restored = try SharedState.decoded(from: state.encoded())
        #expect(restored == state)
        #expect(restored.ledger.wallet.availableSeconds == 600)
        #expect(restored.currentSession?.status == .active)
        #expect(restored.hasRestrictedApps)
    }

    @Test("A fresh install has no access session or selected apps")
    func initialState() {
        let state = SharedState.initial()
        #expect(!state.onboardingCompleted)
        #expect(!state.hasRestrictedApps)
        #expect(state.currentSession == nil)
    }
}
