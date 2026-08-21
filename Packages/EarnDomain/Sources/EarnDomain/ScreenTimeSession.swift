import Foundation

public enum ScreenTimeSessionStatus: String, Codable, Equatable, Sendable {
    case active
    case completed
    case cancelled
}

/// One explicitly purchased wall-clock window in which restricted apps are available.
public struct ScreenTimeSession: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let durationMinutes: Int
    public let endsAt: Date
    public var status: ScreenTimeSessionStatus
    public let spentSeconds: Int

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        durationMinutes: Int,
        status: ScreenTimeSessionStatus = .active
    ) {
        self.id = id
        self.startedAt = startedAt
        self.durationMinutes = durationMinutes
        self.endsAt = startedAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
        self.status = status
        self.spentSeconds = durationMinutes * 60
    }

    public func isActive(at date: Date) -> Bool {
        status == .active && date < endsAt
    }

    public func remainingSeconds(at date: Date) -> Int {
        guard status == .active else { return 0 }
        return max(0, Int(ceil(endsAt.timeIntervalSince(date))))
    }
}

public enum ScreenTimeSessionError: Error, Equatable, Sendable {
    case unsupportedDuration
    case insufficientBalance
    case sessionAlreadyActive
}

/// Pure state transitions for a single active session. External scheduling and shields live in
/// `RestrictionCoordinator`; keeping the accounting here makes it testable on macOS.
public enum ScreenTimeSessionEngine {
    public static let supportedDurations = [5, 10, 15]

    public static func start(
        durationMinutes: Int,
        at date: Date,
        in state: SharedState
    ) throws -> SharedState {
        guard supportedDurations.contains(durationMinutes) else {
            throw ScreenTimeSessionError.unsupportedDuration
        }

        var next = recoverExpiredSession(in: state, at: date)
        guard next.currentSession?.isActive(at: date) != true else {
            throw ScreenTimeSessionError.sessionAlreadyActive
        }
        guard next.ledger.wallet.spend(seconds: durationMinutes * 60) else {
            throw ScreenTimeSessionError.insufficientBalance
        }

        next.currentSession = ScreenTimeSession(
            startedAt: date,
            durationMinutes: durationMinutes
        )
        return next
    }

    public static func complete(
        sessionID: UUID,
        in state: SharedState
    ) -> SharedState {
        guard state.currentSession?.id == sessionID,
              state.currentSession?.status == .active else {
            return state
        }

        var next = state
        next.currentSession?.status = .completed
        return next
    }

    public static func cancelActiveSession(in state: SharedState) -> SharedState {
        guard state.currentSession?.status == .active else { return state }
        var next = state
        next.currentSession?.status = .cancelled
        return next
    }

    public static func recoverExpiredSession(
        in state: SharedState,
        at date: Date
    ) -> SharedState {
        guard let session = state.currentSession,
              session.status == .active,
              date >= session.endsAt else {
            return state
        }
        return complete(sessionID: session.id, in: state)
    }
}
