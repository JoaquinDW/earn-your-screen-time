import Testing
@testable import EarnDomain

@Suite("DeviceActivity threshold plan")
struct MonitorPlanTests {

    @Test("No balance means no monitoring thresholds")
    func emptyWhenBroke() {
        #expect(MonitorPlan.thresholds(totalEarnedSeconds: 0).isEmpty)
        #expect(MonitorPlan.thresholds(totalEarnedSeconds: 59).isEmpty)
    }

    @Test("5 earned minutes produce one tick per minute, last one exhausting")
    func fiveMinutes() {
        let plan = MonitorPlan.thresholds(totalEarnedSeconds: 300)
        #expect(plan.map(\.minute) == [1, 2, 3, 4, 5])
        #expect(plan.last?.isExhaustion == true)
        #expect(plan.dropLast().allSatisfy { !$0.isExhaustion })
    }

    @Test("The exhaustion threshold always equals the total earned minutes")
    func exhaustionMatchesBalance() {
        for minutes in 1...240 {
            let plan = MonitorPlan.thresholds(totalEarnedSeconds: minutes * 60)
            #expect(plan.last?.minute == minutes)
            #expect(plan.last?.isExhaustion == true)
        }
    }

    @Test("Event count stays within the configured budget")
    func respectsEventBudget() {
        for minutes in 1...600 {
            let plan = MonitorPlan.thresholds(totalEarnedSeconds: minutes * 60)
            #expect(plan.count <= MonitorPlan.defaultMaxEvents)
        }
    }

    @Test("Thresholds are strictly increasing")
    func strictlyIncreasing() {
        let plan = MonitorPlan.thresholds(totalEarnedSeconds: 137 * 60)
        #expect(zip(plan, plan.dropFirst()).allSatisfy { $0.minute < $1.minute })
    }

    @Test("Event names round-trip to their minute value")
    func nameRoundTrip() {
        let threshold = MonitorPlan.thresholds(totalEarnedSeconds: 600)[2]
        #expect(threshold.eventName == "tick_3")
        #expect(MonitorPlan.minute(fromEventName: threshold.eventName) == 3)
        #expect(MonitorPlan.minute(fromEventName: "garbage") == nil)
    }

    @Test("Earning more only extends the plan, never rewrites past thresholds")
    func planGrowsMonotonically() {
        let before = MonitorPlan.thresholds(totalEarnedSeconds: 300)
        let after = MonitorPlan.thresholds(totalEarnedSeconds: 600)
        // The first five minutes keep the same minute markers, so usage already counted
        // under the old plan still maps to the same consumed amount.
        #expect(after.map(\.minute).prefix(5) == [1, 2, 3, 4, 5])
        #expect(before.map(\.minute).allSatisfy { after.map(\.minute).contains($0) })
    }
}

@Suite("Shared state serialization")
struct SharedStateTests {

    @Test("State survives a round trip through JSON")
    func roundTrip() throws {
        var state = SharedState.initial(day: DayKey(year: 2026, month: 8, day: 20))
        state.ledger = CreditEngine.apply(activityAmount: 3_842, to: state.ledger).ledger
        state.ledger = CreditEngine.applyConsumption(totalSeconds: 360, to: state.ledger)
        state.onboardingCompleted = true
        state.restrictedItemCount = 5

        let restored = try SharedState.decoded(from: state.encoded())
        #expect(restored == state)
        #expect(restored.ledger.wallet.availableSeconds == 540)
        #expect(restored.hasRestrictedApps)
    }

    @Test("A fresh install starts locked, with no apps selected")
    func initialState() {
        let state = SharedState.initial()
        #expect(!state.onboardingCompleted)
        #expect(!state.hasRestrictedApps)
        #expect(state.ledger.restrictionState == .locked)
    }
}
