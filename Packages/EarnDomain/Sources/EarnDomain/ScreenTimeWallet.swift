import Foundation

/// The user's persisted screen-time balance.
///
/// A reservation removes time from `availableSeconds`, but it is not consumed until the session
/// is paused or expires. Restriction state remains separate: credit never removes shields itself.
public struct ScreenTimeWallet: Codable, Equatable, Sendable {
    public static let maximumSavedSeconds = 180 * 60
    public static let maximumCarryOverSeconds = 20 * 60

    public private(set) var carriedSeconds: Int
    public private(set) var earnedSeconds: Int
    public private(set) var consumedSeconds: Int
    public private(set) var reservedSeconds: Int

    public init(
        carriedSeconds: Int = 0,
        earnedSeconds: Int = 0,
        consumedSeconds: Int = 0,
        reservedSeconds: Int = 0
    ) {
        self.carriedSeconds = max(0, carriedSeconds)
        self.earnedSeconds = max(0, earnedSeconds)
        self.consumedSeconds = max(0, consumedSeconds)
        self.reservedSeconds = max(0, reservedSeconds)
    }

    public var fundedSeconds: Int { carriedSeconds + earnedSeconds }
    public var availableSeconds: Int { max(0, fundedSeconds - consumedSeconds - reservedSeconds) }
    public var availableMinutes: Int { availableSeconds / 60 }
    public var remainingValueSeconds: Int { availableSeconds + reservedSeconds }
    public var remainingValueMinutes: Int { remainingValueSeconds / 60 }
    public var isAtCapacity: Bool { remainingValueSeconds >= Self.maximumSavedSeconds }

    /// Credits as much as fits and returns the amount actually accepted.
    @discardableResult
    public mutating func credit(seconds: Int) -> Int {
        guard seconds > 0 else { return 0 }
        let accepted = min(seconds, max(0, Self.maximumSavedSeconds - remainingValueSeconds))
        earnedSeconds += accepted
        return accepted
    }

    @discardableResult
    public mutating func reserve(seconds: Int) -> Bool {
        guard seconds > 0, seconds <= availableSeconds else { return false }
        reservedSeconds += seconds
        return true
    }

    /// Finalizes the active reservation and returns the number of seconds released back to balance.
    @discardableResult
    public mutating func settleReservation(consuming seconds: Int) -> Int {
        guard reservedSeconds > 0 else { return 0 }
        let consumed = min(max(0, seconds), reservedSeconds)
        let saved = reservedSeconds - consumed
        consumedSeconds += consumed
        reservedSeconds = 0
        return saved
    }

    /// Converts the old immediate-spend representation into a reservation during schema migration.
    mutating func migrateLegacyReservation(seconds: Int) {
        let amount = min(max(0, seconds), consumedSeconds)
        consumedSeconds -= amount
        reservedSeconds += amount
    }

    private enum CodingKeys: String, CodingKey {
        case carriedSeconds, earnedSeconds, consumedSeconds, reservedSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            carriedSeconds: try container.decodeIfPresent(Int.self, forKey: .carriedSeconds) ?? 0,
            earnedSeconds: try container.decodeIfPresent(Int.self, forKey: .earnedSeconds) ?? 0,
            consumedSeconds: try container.decodeIfPresent(Int.self, forKey: .consumedSeconds) ?? 0,
            reservedSeconds: try container.decodeIfPresent(Int.self, forKey: .reservedSeconds) ?? 0
        )
    }
}
