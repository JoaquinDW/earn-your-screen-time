import Foundation
import HealthKit

/// Reads the activity that earns screen time.
///
/// ## A limitation worth knowing
///
/// HealthKit never reveals whether *read* permission was granted — that would leak the fact that
/// the user has no step data. `authorizationStatus(for:)` only reports write access. So the only
/// honest signal is: we asked, and a query came back. A user who denied access looks exactly like
/// a user who has not walked. The UI has to be written so both cases read sensibly.
@MainActor
protocol HealthKitServing: AnyObject {
    var isAvailable: Bool { get }
    /// Whether the authorization sheet has been presented. Not a permission check — see above.
    var hasRequestedAuthorization: Bool { get }
    func requestAuthorization() async throws
    /// Steps recorded today, in the user's local calendar.
    func todaySteps() async throws -> Int
}

@MainActor
final class LiveHealthKitService: HealthKitServing {
    private let store = HKHealthStore()
    private let stepType = HKQuantityType(.stepCount)
    private let defaults = AppGroup.defaults
    private let requestedKey = "health.didRequestAuthorization"

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var hasRequestedAuthorization: Bool {
        defaults.bool(forKey: requestedKey)
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        try await store.requestAuthorization(toShare: [], read: [stepType])
        defaults.set(true, forKey: requestedKey)
    }

    func todaySteps() async throws -> Int {
        guard isAvailable else { throw HealthKitError.unavailable }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: nil, options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: stepType, predicate: predicate),
            options: .cumulativeSum
        )
        let sum = try await descriptor.result(for: store)?.sumQuantity()
        return Int(sum?.doubleValue(for: .count()) ?? 0)
    }
}

enum HealthKitError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        String(localized: "health.error.unavailable")
    }
}

/// Preview/Simulator stand-in. Reports whatever the shared ledger already holds, so
/// `scripts/seed-simulator.sh` drives the UI without needing Health data.
@MainActor
final class MockHealthKitService: HealthKitServing {
    private(set) var hasRequestedAuthorization: Bool
    private var steps: Int?

    init(hasRequested: Bool = false, steps: Int? = nil) {
        self.hasRequestedAuthorization = hasRequested
        self.steps = steps
    }

    var isAvailable: Bool { true }

    func requestAuthorization() async throws {
        try? await Task.sleep(for: .milliseconds(400))
        hasRequestedAuthorization = true
    }

    func todaySteps() async throws -> Int {
        steps ?? SharedStore.shared.load().ledger.activityAmount
    }
}
