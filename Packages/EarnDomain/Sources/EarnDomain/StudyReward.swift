import Foundation

public enum EarningMethod: String, Codable, CaseIterable, Sendable {
    case steps
    case study
    case pushups

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(rawValue: try container.decode(String.self)) ?? .steps
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A reward authorized by the server for a completed earning transaction.
public struct ServerRewardReceipt: Codable, Equatable, Sendable {
    public let id: UUID
    public let method: EarningMethod
    public let rewardSeconds: Int
    public let issuedAt: Date
    public let externalReference: String?

    public init(
        id: UUID,
        method: EarningMethod = .study,
        rewardSeconds: Int,
        issuedAt: Date,
        externalReference: String? = nil
    ) {
        self.id = id
        self.method = method
        self.rewardSeconds = rewardSeconds
        self.issuedAt = issuedAt
        self.externalReference = externalReference
    }

    private enum CodingKeys: String, CodingKey {
        case id, method, rewardSeconds, issuedAt, externalReference
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            method: try container.decodeIfPresent(EarningMethod.self, forKey: .method) ?? .study,
            rewardSeconds: try container.decode(Int.self, forKey: .rewardSeconds),
            issuedAt: try container.decode(Date.self, forKey: .issuedAt),
            externalReference: try container.decodeIfPresent(String.self, forKey: .externalReference)
        )
    }
}

/// The original Study API remains available while receipts are generalized across earning methods.
public typealias StudyRewardReceipt = ServerRewardReceipt

/// Source-neutral audit record for screen time awarded by an earning method.
public struct RewardTransaction: Codable, Equatable, Sendable {
    public let id: UUID
    public let method: EarningMethod
    public let awardedSeconds: Int
    public let issuedAt: Date
    public let externalReference: String?

    public init(
        id: UUID,
        method: EarningMethod,
        awardedSeconds: Int,
        issuedAt: Date,
        externalReference: String? = nil
    ) {
        self.id = id
        self.method = method
        self.awardedSeconds = max(0, awardedSeconds)
        self.issuedAt = issuedAt
        self.externalReference = externalReference
    }

    private enum CodingKeys: String, CodingKey {
        case id, method, awardedSeconds, issuedAt, externalReference
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id)
                ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            method: try container.decodeIfPresent(EarningMethod.self, forKey: .method) ?? .steps,
            awardedSeconds: try container.decodeIfPresent(Int.self, forKey: .awardedSeconds) ?? 0,
            issuedAt: try container.decodeIfPresent(Date.self, forKey: .issuedAt) ?? Date(timeIntervalSince1970: 0),
            externalReference: try container.decodeIfPresent(String.self, forKey: .externalReference)
        )
    }
}

/// Applies server-authorized rewards without I/O.
public enum ServerRewardEngine {
    public enum Result: Equatable, Sendable {
        case applied
        case duplicate
        case insufficientWalletCapacity
        case invalidReward
    }

    public struct Outcome: Equatable, Sendable {
        public let state: SharedState
        public let result: Result
        public let awardedSeconds: Int

        public var didApply: Bool { result == .applied }
    }

    public static func apply(_ receipt: ServerRewardReceipt, to state: SharedState) -> Outcome {
        guard !state.appliedRewardIDs.contains(receipt.id) else {
            return Outcome(state: state, result: .duplicate, awardedSeconds: 0)
        }
        guard receipt.rewardSeconds > 0 else {
            return Outcome(state: state, result: .invalidReward, awardedSeconds: 0)
        }
        guard receipt.rewardSeconds <= ScreenTimeWallet.maximumSavedSeconds - state.ledger.wallet.remainingValueSeconds else {
            return Outcome(state: state, result: .insufficientWalletCapacity, awardedSeconds: 0)
        }

        var updated = state
        let credited = updated.ledger.wallet.credit(seconds: receipt.rewardSeconds)
        guard credited == receipt.rewardSeconds else {
            return Outcome(state: state, result: .insufficientWalletCapacity, awardedSeconds: 0)
        }
        updated.ledger.walletTransactions.append(WalletTransaction(
            kind: .earned,
            amountSeconds: credited,
            source: receipt.method.walletSource,
            date: receipt.issuedAt
        ))
        updated.ledger.rewardTransactions.append(RewardTransaction(
            id: receipt.id,
            method: receipt.method,
            awardedSeconds: credited,
            issuedAt: receipt.issuedAt,
            externalReference: receipt.externalReference
        ))
        updated.recordAppliedReward(receipt.id)
        return Outcome(state: updated, result: .applied, awardedSeconds: credited)
    }
}

public typealias StudyRewardEngine = ServerRewardEngine

private extension EarningMethod {
    var walletSource: WalletTransaction.Source {
        switch self {
        case .steps: .steps
        case .study: .study
        case .pushups: .pushups
        }
    }
}
