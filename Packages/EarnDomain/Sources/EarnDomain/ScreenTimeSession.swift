import Foundation

public enum ScreenTimeSessionStatus: String, Codable, Equatable, Sendable {
    case active
    case completed
    case paused
    case cancelled
}

/// One explicitly reserved wall-clock window in which restricted apps are available.
public struct ScreenTimeSession: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let durationMinutes: Int
    public let endsAt: Date
    public var status: ScreenTimeSessionStatus
    public let reservedSeconds: Int
    public var settledAt: Date?
    public var consumedSeconds: Int
    public var savedSeconds: Int
    public var settlementAnalyticsReported: Bool

    /// Compatibility name for code and payloads written before reservations were refundable.
    public var spentSeconds: Int { reservedSeconds }

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        durationMinutes: Int,
        status: ScreenTimeSessionStatus = .active,
        settledAt: Date? = nil,
        consumedSeconds: Int = 0,
        savedSeconds: Int = 0,
        settlementAnalyticsReported: Bool = false
    ) {
        self.id = id
        self.startedAt = startedAt
        self.durationMinutes = durationMinutes
        self.endsAt = startedAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
        self.status = status
        self.reservedSeconds = max(0, durationMinutes * 60)
        self.settledAt = settledAt
        self.consumedSeconds = max(0, consumedSeconds)
        self.savedSeconds = max(0, savedSeconds)
        self.settlementAnalyticsReported = settlementAnalyticsReported
    }

    public func isActive(at date: Date) -> Bool {
        status == .active && date < endsAt
    }

    public func remainingSeconds(at date: Date) -> Int {
        guard status == .active else { return 0 }
        return max(0, Int(ceil(endsAt.timeIntervalSince(date))))
    }

    public func elapsedSeconds(at date: Date) -> Int {
        min(reservedSeconds, max(0, Int(floor(date.timeIntervalSince(startedAt)))))
    }

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, durationMinutes, endsAt, status
        case reservedSeconds, spentSeconds, settledAt, consumedSeconds, savedSeconds
        case settlementAnalyticsReported
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        endsAt = try container.decodeIfPresent(Date.self, forKey: .endsAt)
            ?? startedAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
        status = try container.decodeIfPresent(ScreenTimeSessionStatus.self, forKey: .status) ?? .cancelled
        reservedSeconds = try container.decodeIfPresent(Int.self, forKey: .reservedSeconds)
            ?? container.decodeIfPresent(Int.self, forKey: .spentSeconds)
            ?? durationMinutes * 60
        settledAt = try container.decodeIfPresent(Date.self, forKey: .settledAt)
        consumedSeconds = try container.decodeIfPresent(Int.self, forKey: .consumedSeconds)
            ?? (status == .active ? 0 : reservedSeconds)
        savedSeconds = try container.decodeIfPresent(Int.self, forKey: .savedSeconds) ?? 0
        settlementAnalyticsReported = try container.decodeIfPresent(
            Bool.self,
            forKey: .settlementAnalyticsReported
        ) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(durationMinutes, forKey: .durationMinutes)
        try container.encode(endsAt, forKey: .endsAt)
        try container.encode(status, forKey: .status)
        try container.encode(reservedSeconds, forKey: .reservedSeconds)
        try container.encodeIfPresent(settledAt, forKey: .settledAt)
        try container.encode(consumedSeconds, forKey: .consumedSeconds)
        try container.encode(savedSeconds, forKey: .savedSeconds)
        try container.encode(settlementAnalyticsReported, forKey: .settlementAnalyticsReported)
    }
}

public enum ScreenTimeSessionError: Error, Equatable, Sendable {
    case unsupportedDuration
    case insufficientBalance
    case sessionAlreadyActive
    case exceedsCarryOverWindow
}

/// Pure, idempotent transitions. Scheduling and shields remain in `RestrictionCoordinator`.
public enum ScreenTimeSessionEngine {
    public static let supportedDurations = [5, 10, 15]
    public static let minimumDurationMinutes = 1
    public static let maximumDurationMinutes = ScreenTimeWallet.maximumSavedSeconds / 60

    /// Sessions may use the next day's carry-over allowance without stopping at midnight.
    public static func maximumStartableMinutes(
        availableMinutes: Int,
        at date: Date,
        calendar: Calendar = .current
    ) -> Int {
        guard let dayBoundary = calendar.dateInterval(of: .day, for: date)?.end else { return 0 }
        let latestEnd = dayBoundary.addingTimeInterval(
            TimeInterval(ScreenTimeWallet.maximumCarryOverSeconds)
        )
        let minutesUntilLatestEnd = max(0, Int(latestEnd.timeIntervalSince(date) / 60))
        return min(availableMinutes, maximumDurationMinutes, minutesUntilLatestEnd)
    }

    public static func start(
        durationMinutes: Int,
        at date: Date,
        in state: SharedState
    ) throws -> SharedState {
        guard (minimumDurationMinutes...maximumDurationMinutes).contains(durationMinutes) else {
            throw ScreenTimeSessionError.unsupportedDuration
        }
        guard durationMinutes <= maximumStartableMinutes(
            availableMinutes: maximumDurationMinutes,
            at: date
        ) else {
            throw ScreenTimeSessionError.exceedsCarryOverWindow
        }

        var next = recoverExpiredSession(in: state, at: date)
        guard next.currentSession?.isActive(at: date) != true else {
            throw ScreenTimeSessionError.sessionAlreadyActive
        }
        guard next.ledger.wallet.reserve(seconds: durationMinutes * 60) else {
            throw ScreenTimeSessionError.insufficientBalance
        }

        next.currentSession = ScreenTimeSession(startedAt: date, durationMinutes: durationMinutes)
        return next
    }

    public static func complete(
        sessionID: UUID,
        in state: SharedState,
        at date: Date = Date()
    ) -> SharedState {
        settle(sessionID: sessionID, in: state, at: date, status: .completed, consumeAll: true)
    }

    public static func pauseActiveSession(in state: SharedState, at date: Date) -> SharedState {
        guard let session = state.currentSession else { return state }
        return settle(sessionID: session.id, in: state, at: date, status: .paused, consumeAll: false)
    }

    public static func cancelActiveSession(in state: SharedState, at date: Date = Date()) -> SharedState {
        guard let session = state.currentSession else { return state }
        return settle(sessionID: session.id, in: state, at: date, status: .cancelled, consumeAll: false)
    }

    public static func recoverExpiredSession(in state: SharedState, at date: Date) -> SharedState {
        guard let session = state.currentSession,
              session.status == .active,
              date >= session.endsAt else {
            return state
        }
        return complete(sessionID: session.id, in: state, at: session.endsAt)
    }

    /// Charges the elapsed part of a crossing session while keeping the remainder active.
    /// The caller can then roll the released value into the new day's wallet and reserve it again.
    public static func settleActiveSessionThrough(
        in state: SharedState,
        at date: Date
    ) -> SharedState {
        guard let session = state.currentSession,
              session.status == .active,
              session.startedAt < date,
              date < session.endsAt else {
            return state
        }

        var next = state
        let consumed = session.elapsedSeconds(at: date)
        let newlyConsumed = max(0, consumed - session.consumedSeconds)
        guard newlyConsumed > 0 else { return state }

        next.ledger.wallet.settleReservation(consuming: newlyConsumed)
        next.currentSession?.consumedSeconds = consumed
        next.ledger.walletTransactions.append(WalletTransaction(
            kind: .consumed,
            amountSeconds: newlyConsumed,
            source: .session,
            date: date,
            sessionID: session.id
        ))
        return next
    }

    private static func settle(
        sessionID: UUID,
        in state: SharedState,
        at date: Date,
        status: ScreenTimeSessionStatus,
        consumeAll: Bool
    ) -> SharedState {
        guard let session = state.currentSession,
              session.id == sessionID,
              session.status == .active else {
            return state
        }

        var next = state
        let consumed = consumeAll ? session.reservedSeconds : session.elapsedSeconds(at: date)
        let newlyConsumed = max(0, consumed - session.consumedSeconds)
        let saved = next.ledger.wallet.settleReservation(consuming: newlyConsumed)
        next.currentSession?.status = status
        next.currentSession?.settledAt = date
        next.currentSession?.consumedSeconds = consumed
        next.currentSession?.savedSeconds = saved
        if newlyConsumed > 0 {
            next.ledger.walletTransactions.append(WalletTransaction(
                kind: .consumed,
                amountSeconds: newlyConsumed,
                source: .session,
                date: date,
                sessionID: sessionID
            ))
        }
        return next
    }
}
