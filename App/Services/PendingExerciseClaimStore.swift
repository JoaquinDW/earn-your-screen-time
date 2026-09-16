import Foundation

enum PendingExerciseClaimStage: String, Codable, Equatable, Sendable {
    case started
    case completed
}

struct PendingExerciseClaim: Codable, Equatable, Sendable {
    let clientRequestID: UUID
    let targetReps: Int
    let detectionVersion: String
    var session: ExerciseSession?
    var stage: PendingExerciseClaimStage
    var completedReps: Int?
    var durationSeconds: Double?
    var completedAt: Date?

    init(
        clientRequestID: UUID,
        targetReps: Int,
        detectionVersion: String,
        session: ExerciseSession? = nil
    ) {
        self.clientRequestID = clientRequestID
        self.targetReps = targetReps
        self.detectionVersion = detectionVersion
        self.session = session
        stage = .started
        completedReps = nil
        durationSeconds = nil
        completedAt = nil
    }

    mutating func markCompleted(completedReps: Int, durationSeconds: Double, completedAt: Date) {
        stage = .completed
        self.completedReps = completedReps
        self.durationSeconds = durationSeconds
        self.completedAt = completedAt
    }
}

enum PendingExerciseClaimStoreError: LocalizedError {
    case invalidRecord

    var errorDescription: String? {
        "The pending exercise claim could not be read."
    }
}

@MainActor
final class PendingExerciseClaimStore {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "pendingExerciseClaim.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load() throws -> PendingExerciseClaim? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let record = try? JSONDecoder().decode(PendingExerciseClaim.self, from: data) else {
            throw PendingExerciseClaimStoreError.invalidRecord
        }
        return record
    }

    func save(_ record: PendingExerciseClaim) throws {
        defaults.set(try JSONEncoder().encode(record), forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
