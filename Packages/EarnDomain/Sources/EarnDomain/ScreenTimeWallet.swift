import Foundation

/// The user's screen-time balance for a single day.
///
/// `consumedSeconds` includes time reserved when explicit access sessions start. It remains
/// separate from restriction state: banked credit never removes shields by itself.
public struct ScreenTimeWallet: Codable, Equatable, Sendable {
    public private(set) var earnedSeconds: Int
    public private(set) var consumedSeconds: Int

    public init(earnedSeconds: Int = 0, consumedSeconds: Int = 0) {
        self.earnedSeconds = max(0, earnedSeconds)
        self.consumedSeconds = max(0, consumedSeconds)
    }

    public var availableSeconds: Int { max(0, earnedSeconds - consumedSeconds) }
    public var availableMinutes: Int { availableSeconds / 60 }

    public mutating func credit(seconds: Int) {
        guard seconds > 0 else { return }
        earnedSeconds += seconds
    }

    /// Reserves earned time immediately when an access session starts.
    @discardableResult
    public mutating func spend(seconds: Int) -> Bool {
        guard seconds > 0, seconds <= availableSeconds else { return false }
        consumedSeconds += seconds
        return true
    }

}
