import Foundation

/// Where earned screen time comes from.
///
/// Only ``steps`` is implemented for the MVP, but the domain is modelled around the
/// abstraction so workouts / focus sessions / distance goals can be added without
/// reshaping persisted data (PRD §25).
public enum EarningSource: String, Codable, Sendable, CaseIterable {
    case steps
    case workout
    case focusSession
    case runningDistance
    case cyclingDistance
    case custom

    /// Sources the MVP can actually measure today.
    public static var implemented: [EarningSource] { [.steps] }

    public var isImplemented: Bool { Self.implemented.contains(self) }
}

/// "X units of activity earn Y seconds of screen time."
public struct EarningRule: Codable, Equatable, Sendable {
    public static let minimumAmount = 100
    public static let maximumAmount = 50_000
    public static let minimumReward = 60
    public static let maximumReward = 60 * 60

    public let source: EarningSource
    /// Activity units required per milestone (e.g. 1_000 steps).
    public let amountRequired: Int
    /// Screen time granted per milestone, in seconds (e.g. 300 = 5 minutes).
    public let rewardSeconds: Int

    public init(source: EarningSource = .steps, amountRequired: Int, rewardSeconds: Int) {
        self.source = source
        self.amountRequired = min(max(amountRequired, Self.minimumAmount), Self.maximumAmount)
        // Sessions are offered in whole minutes, so fractional-minute credit cannot be spent.
        let clampedReward = min(max(rewardSeconds, Self.minimumReward), Self.maximumReward)
        self.rewardSeconds = (clampedReward / 60) * 60
    }

    /// PRD §8 default: 1,000 steps = 5 minutes.
    public static let `default` = EarningRule(source: .steps, amountRequired: 1_000, rewardSeconds: 300)

    public var rewardMinutes: Int { rewardSeconds / 60 }
}
