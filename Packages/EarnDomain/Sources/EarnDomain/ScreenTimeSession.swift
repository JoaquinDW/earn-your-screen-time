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
    case crossesDayBoundary
}

/// Pure, idempotent transitions. Scheduling and shields remain in `RestrictionCoordinator`.
public enum ScreenTimeSessionEngine {
    public static let supportedDurations = [5, 10, 15]
    public static let minimumDurationMinutes = 1
    public static let maximumDurationMinutes = ScreenTimeWallet.maximumSavedSeconds / 60

    public static func start(
        durationMinutes: Int,
        at date: Date,
        in state: SharedState
    ) throws -> SharedState {
        guard (minimumDurationMinutes...maximumDurationMinutes).contains(durationMinutes) else {
            throw ScreenTimeSessionError.unsupportedDuration
        }
        let proposedEnd = date.addingTimeInterval(TimeInterval(durationMinutes * 60))
        guard Calendar.current.isDate(date, inSameDayAs: proposedEnd) else {
            throw ScreenTimeSessionError.crossesDayBoundary
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
        let saved = next.ledger.wallet.settleReservation(consuming: consumed)
        next.currentSession?.status = status
        next.currentSession?.settledAt = date
        next.currentSession?.consumedSeconds = consumed
        next.currentSession?.savedSeconds = saved
        if consumed > 0 {
            next.ledger.walletTransactions.append(WalletTransaction(
                kind: .consumed,
                amountSeconds: consumed,
                source: .session,
                date: date,
                sessionID: sessionID
            ))
        }
        return next
    }
}
