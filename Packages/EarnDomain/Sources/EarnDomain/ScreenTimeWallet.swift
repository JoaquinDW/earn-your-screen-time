import Foundation

/// Whether the user's restricted apps should currently be shielded.
public enum RestrictionState: String, Codable, Sendable {
    case locked
    case available
}

/// The user's screen-time balance for a single day.
///
/// `consumedSeconds` is stored raw (it can overshoot `earnedSeconds` because the system
/// reports usage thresholds with some delay), while `availableSeconds` never goes negative.
public struct ScreenTimeWallet: Codable, Equatable, Sendable {
    public private(set) var earnedSeconds: Int
    public private(set) var consumedSeconds: Int

    public init(earnedSeconds: Int = 0, consumedSeconds: Int = 0) {
        self.earnedSeconds = max(0, earnedSeconds)
        self.consumedSeconds = max(0, consumedSeconds)
    }

    public var availableSeconds: Int { max(0, earnedSeconds - consumedSeconds) }
    public var availableMinutes: Int { availableSeconds / 60 }
    public var restrictionState: RestrictionState { availableSeconds > 0 ? .available : .locked }
    public var isExhausted: Bool { availableSeconds == 0 }

    public mutating func credit(seconds: Int) {
        guard seconds > 0 else { return }
        earnedSeconds += seconds
    }

    /// Records total usage reported by the system.
    ///
    /// Idempotent on purpose: DeviceActivity threshold events can be re-delivered or
    /// delivered out of order, so consumption only ever moves forward.
    public mutating func recordTotalConsumed(seconds: Int) {
        consumedSeconds = max(consumedSeconds, max(0, seconds))
    }
}
