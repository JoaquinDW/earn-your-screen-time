import Foundation
import HealthKit

struct DailyStepSample: Equatable, Sendable {
    let date: Date
    let steps: Int
}

struct DailyStepResult: Equatable, Sendable {
    let samples: [DailyStepSample]

    /// A zero-step day is treated like an unreadable day. Three valid days are required before
    /// the value is useful enough to present as a baseline.
    var baselineSteps: Int? {
        guard samples.count >= 3 else { return nil }
        return samples.reduce(0) { $0 + $1.steps } / samples.count
    }
}

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
    /// The seven most recent readable completed days found within the last 14 local days.
    func recentDailySteps() async throws -> DailyStepResult
    /// Average steps over the recent valid completed days in the user's local calendar.
    /// Returns `nil` until at least three valid days are available; denial is indistinguishable.
    func recentAverageSteps() async throws -> Int?
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

    func recentAverageSteps() async throws -> Int? {
        try await recentDailySteps().baselineSteps
    }

    func recentDailySteps() async throws -> DailyStepResult {
        guard isAvailable else { throw HealthKitError.unavailable }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -14, to: end) else {
            return DailyStepResult(samples: [])
        }
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate, .strictEndDate]
        )
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: stepType, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: end,
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)
        let samples = collection.statistics()
            .reversed()
            .compactMap { statistics -> DailyStepSample? in
                let steps = Int(statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                return steps > 0 ? DailyStepSample(date: statistics.startDate, steps: steps) : nil
            }
            .prefix(7)
        return DailyStepResult(samples: Array(samples))
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
    private var averageSteps: Int?
    private let dailyValues: [Int]?
    private let available: Bool
    private let injectedError: (any Error)?

    /// `dailySteps` is ordered newest completed day first.
    init(
        hasRequested: Bool = false,
        steps: Int? = nil,
        recentAverageSteps: Int? = nil,
        dailySteps: [Int]? = nil,
        isAvailable: Bool = true,
        error: (any Error)? = nil
    ) {
        self.hasRequestedAuthorization = hasRequested
        self.steps = steps
        self.averageSteps = recentAverageSteps
        self.dailyValues = dailySteps
        self.available = isAvailable
        self.injectedError = error
    }

    var isAvailable: Bool { available }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        if let injectedError { throw injectedError }
        try? await Task.sleep(for: .milliseconds(400))
        hasRequestedAuthorization = true
    }

    func todaySteps() async throws -> Int {
        guard isAvailable else { throw HealthKitError.unavailable }
        if let injectedError { throw injectedError }
        return steps ?? SharedStore.shared.load().ledger.activityAmount
    }

    func recentAverageSteps() async throws -> Int? {
        guard isAvailable else { throw HealthKitError.unavailable }
        if let injectedError { throw injectedError }
        if dailyValues != nil {
            return try await recentDailySteps().baselineSteps
        }
        return averageSteps
    }

    func recentDailySteps() async throws -> DailyStepResult {
        guard isAvailable else { throw HealthKitError.unavailable }
        if let injectedError { throw injectedError }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let samples = (dailyValues ?? [])
            .prefix(14)
            .enumerated()
            .compactMap { offset, steps -> DailyStepSample? in
                guard steps > 0,
                      let date = calendar.date(byAdding: .day, value: -(offset + 1), to: end)
                else { return nil }
                return DailyStepSample(date: date, steps: steps)
            }
            .prefix(7)
        return DailyStepResult(samples: Array(samples))
    }
}
