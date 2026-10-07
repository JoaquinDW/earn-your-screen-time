import EarnDomain
import Foundation
import Supabase

struct ExerciseConfiguration: Equatable, Sendable {
    let enabled: Bool
    let entitled: Bool
    let updateRequired: Bool?
    let minimumAppVersion: String
    let detectionVersion: String
    let sessionTTLSeconds: Int
    let dailyCapSeconds: Int
    let poseThresholds: ExercisePoseThresholds
    let challenges: [ExerciseChallenge]
    /// `nil` when the server predates squats or has them switched off.
    let squats: SquatConfiguration?
    let earnedSeconds: Int
    let rewardSecondsRemaining: Int
    let resetsAt: Date
}

extension ExerciseConfiguration {
    var availableExercises: [ExerciseKind] {
        squats.map { $0.challenges.isEmpty ? [.pushup] : [.pushup, .squat] } ?? [.pushup]
    }

    func challenges(for exercise: ExerciseKind) -> [ExerciseChallenge] {
        switch exercise {
        case .pushup: challenges
        case .squat: squats?.challenges ?? []
        }
    }
}

struct ExerciseChallenge: Codable, Equatable, Sendable {
    let targetReps: Int
    let rewardSeconds: Int
}

struct SquatConfiguration: Codable, Equatable, Sendable {
    let poseThresholds: SquatRemotePoseThresholds
    let challenges: [ExerciseChallenge]
}

struct SquatRemotePoseThresholds: Codable, Equatable, Sendable {
    let minimumConfidence: Double
    let bottomDepthScore: Double
    let minimumRepDurationSeconds: Double
}

struct ExercisePoseThresholds: Codable, Equatable, Sendable {
    let minimumConfidence: Double
    let downElbowAngleDegrees: Double
    let upElbowAngleDegrees: Double
    let minimumBodyAngleDegrees: Double
    let minimumRepDurationSeconds: Double
}

struct ExerciseSession: Codable, Equatable, Sendable {
    let id: UUID
    let exercise: ExerciseKind
    let status: String
    let targetReps: Int
    let rewardSeconds: Int
    let expiresAt: Date
    let detectionVersion: String

    init(
        id: UUID,
        exercise: ExerciseKind,
        status: String,
        targetReps: Int,
        rewardSeconds: Int,
        expiresAt: Date,
        detectionVersion: String
    ) {
        self.id = id
        self.exercise = exercise
        self.status = status
        self.targetReps = targetReps
        self.rewardSeconds = rewardSeconds
        self.expiresAt = expiresAt
        self.detectionVersion = detectionVersion
    }

    private enum CodingKeys: String, CodingKey {
        case id, exercise, status, targetReps, rewardSeconds, expiresAt, detectionVersion
    }

    /// A session persisted in a pending claim before squats existed was a push-up session.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            exercise: try container.decodeIfPresent(ExerciseKind.self, forKey: .exercise) ?? .pushup,
            status: try container.decode(String.self, forKey: .status),
            targetReps: try container.decode(Int.self, forKey: .targetReps),
            rewardSeconds: try container.decode(Int.self, forKey: .rewardSeconds),
            expiresAt: try container.decode(Date.self, forKey: .expiresAt),
            detectionVersion: try container.decode(String.self, forKey: .detectionVersion)
        )
    }
}

struct ExerciseReward: Codable, Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    let amountSeconds: Int
    let earnedOn: Date
    let createdAt: Date
}

protocol ExerciseServing: Sendable {
    func ensureIdentity() async throws -> UUID
    func configuration() async throws -> ExerciseConfiguration
    func start(
        exercise: ExerciseKind,
        challenge: ExerciseChallenge,
        detectionVersion: String,
        requestID: UUID
    ) async throws -> ExerciseSession
    func claim(
        sessionID: UUID,
        completedReps: Int,
        durationSeconds: Double,
        completedAt: Date,
        detectionVersion: String
    ) async throws -> ExerciseReward
}

enum ExerciseServiceError: LocalizedError, Equatable {
    case notConfigured
    case server(code: String, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Pushups to Earn is not configured in this build."
        case let .server(_, message):
            message
        case .invalidResponse:
            "The exercise service returned an invalid response."
        }
    }

    var code: String? {
        if case let .server(code, _) = self { return code }
        return nil
    }
}

actor SupabaseExerciseService: ExerciseServing {
    private let url: URL
    private let publishableKey: String
    private let client: SupabaseClient
    private let http: URLSession
    private let appVersion: String
    private let requestTimeout: TimeInterval

    init?(
        url: URL? = AppConfiguration.supabaseURL,
        publishableKey: String? = AppConfiguration.supabasePublishableKey,
        http: URLSession = .shared,
        bundle: Bundle = .main,
        requestTimeout: TimeInterval = 15
    ) {
        guard let url, let publishableKey else { return nil }
        self.url = url
        self.publishableKey = publishableKey
        self.http = http
        appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        self.requestTimeout = requestTimeout
        client = SupabaseClient(supabaseURL: url, supabaseKey: publishableKey)
    }

    func ensureIdentity() async throws -> UUID {
        if let session = try? await client.auth.session {
            return session.user.id
        }
        return try await client.auth.signInAnonymously().user.id
    }

    func configuration() async throws -> ExerciseConfiguration {
        let response: ConfigResponse = try await invoke(
            "pushups-config",
            method: "GET",
            queryItems: [URLQueryItem(name: "app_version", value: appVersion)],
            body: Optional<EmptyBody>.none
        )
        guard let resetsAt = Self.date(response.availability.resetsAt) else {
            throw ExerciseServiceError.invalidResponse
        }
        return ExerciseConfiguration(
            enabled: response.configuration.enabled,
            entitled: response.entitled,
            updateRequired: response.updateRequired,
            minimumAppVersion: response.configuration.minimumAppVersion,
            detectionVersion: response.configuration.detectionVersion,
            sessionTTLSeconds: response.configuration.sessionTtlSeconds,
            dailyCapSeconds: response.configuration.dailyCapSeconds,
            poseThresholds: response.configuration.poseThresholds,
            challenges: response.configuration.challenges,
            squats: response.configuration.squats.flatMap { squats in
                squats.enabled
                    ? SquatConfiguration(poseThresholds: squats.poseThresholds, challenges: squats.challenges)
                    : nil
            },
            earnedSeconds: response.availability.earnedSeconds,
            rewardSecondsRemaining: response.availability.rewardSecondsRemaining,
            resetsAt: resetsAt
        )
    }

    func start(
        exercise: ExerciseKind,
        challenge: ExerciseChallenge,
        detectionVersion: String,
        requestID: UUID
    ) async throws -> ExerciseSession {
        let response: SessionResponse = try await invoke(
            "pushups-start",
            method: "POST",
            body: StartRequest(
                clientRequestID: requestID,
                // Omitted for push-ups so the request stays valid against a server without squats.
                exerciseType: exercise == .pushup ? nil : exercise.rawValue,
                targetReps: challenge.targetReps,
                appVersion: appVersion,
                detectionVersion: detectionVersion
            )
        )
        guard let expiresAt = Self.date(response.session.expiresAt) else {
            throw ExerciseServiceError.invalidResponse
        }
        return ExerciseSession(
            id: response.session.id,
            exercise: response.session.exerciseType.flatMap(ExerciseKind.init(rawValue:)) ?? exercise,
            status: response.session.status,
            targetReps: response.session.targetReps,
            rewardSeconds: response.session.rewardSeconds,
            expiresAt: expiresAt,
            detectionVersion: response.session.detectionVersion
        )
    }

    func claim(
        sessionID: UUID,
        completedReps: Int,
        durationSeconds: Double,
        completedAt: Date,
        detectionVersion: String
    ) async throws -> ExerciseReward {
        let response: RewardResponse = try await invoke(
            "pushups-claim",
            method: "POST",
            body: ClaimRequest(
                sessionID: sessionID,
                completedReps: completedReps,
                durationSeconds: durationSeconds,
                completedAt: Self.iso8601(completedAt),
                detectionVersion: detectionVersion
            )
        )
        guard let earnedOn = Self.date(response.reward.earnedOn),
              let createdAt = Self.date(response.reward.createdAt) else {
            throw ExerciseServiceError.invalidResponse
        }
        return ExerciseReward(
            id: response.reward.id,
            sessionID: response.reward.sessionId,
            amountSeconds: response.reward.amountSeconds,
            earnedOn: earnedOn,
            createdAt: createdAt
        )
    }

    private func invoke<Response: Decodable, Body: Encodable>(
        _ function: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Body?
    ) async throws -> Response {
        let session: Session
        if let existing = try? await client.auth.session {
            session = existing
        } else {
            session = try await client.auth.signInAnonymously()
        }
        guard var components = URLComponents(
            url: url.appending(path: "functions/v1/\(function)"),
            resolvingAgainstBaseURL: false
        ) else {
            throw ExerciseServiceError.invalidResponse
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let requestURL = components.url else {
            throw ExerciseServiceError.invalidResponse
        }
        var request = URLRequest(url: requestURL, timeoutInterval: requestTimeout)
        request.httpMethod = method
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await http.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExerciseServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard (200..<300).contains(httpResponse.statusCode) else {
            let payload = try? decoder.decode(ErrorResponse.self, from: data)
            throw ExerciseServiceError.server(
                code: payload?.code ?? "http_\(httpResponse.statusCode)",
                message: payload?.error ?? "The exercise request failed."
            )
        }
        guard let decoded = try? decoder.decode(Response.self, from: data) else {
            throw ExerciseServiceError.invalidResponse
        }
        return decoded
    }

    private static func date(_ value: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = precise.date(from: value) ?? ISO8601DateFormatter().date(from: value) {
            return date
        }
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .iso8601)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(secondsFromGMT: 0)
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: value)
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private struct EmptyBody: Encodable {}
private struct ErrorResponse: Decodable { let error: String; let code: String }

private struct ConfigResponse: Decodable {
    struct Configuration: Decodable {
        let enabled: Bool
        let minimumAppVersion: String
        let detectionVersion: String
        let sessionTtlSeconds: Int
        let dailyCapSeconds: Int
        let poseThresholds: ExercisePoseThresholds
        let challenges: [ExerciseChallenge]
        let squats: Squats?
    }

    struct Squats: Decodable {
        let enabled: Bool
        let poseThresholds: SquatRemotePoseThresholds
        let challenges: [ExerciseChallenge]
    }

    struct Availability: Decodable {
        let earnedSeconds: Int
        let rewardSecondsRemaining: Int
        let resetsAt: String
    }

    let configuration: Configuration
    let entitled: Bool
    let updateRequired: Bool?
    let availability: Availability
}

private struct StartRequest: Encodable {
    let clientRequestID: UUID
    let exerciseType: String?
    let targetReps: Int
    let appVersion: String
    let detectionVersion: String
}

private struct SessionResponse: Decodable {
    struct RemoteSession: Decodable {
        let id: UUID
        let exerciseType: String?
        let status: String
        let targetReps: Int
        let rewardSeconds: Int
        let expiresAt: String
        let detectionVersion: String
    }

    let session: RemoteSession
}

private struct ClaimRequest: Encodable {
    let sessionID: UUID
    let completedReps: Int
    let durationSeconds: Double
    let completedAt: String
    let detectionVersion: String
}

private struct RewardResponse: Decodable {
    struct RemoteReward: Decodable {
        let id: UUID
        let sessionId: UUID
        let amountSeconds: Int
        let earnedOn: String
        let createdAt: String
    }

    let reward: RemoteReward
}

actor UnconfiguredExerciseService: ExerciseServing {
    func ensureIdentity() async throws -> UUID { throw ExerciseServiceError.notConfigured }
    func configuration() async throws -> ExerciseConfiguration { throw ExerciseServiceError.notConfigured }
    func start(
        exercise: ExerciseKind,
        challenge: ExerciseChallenge,
        detectionVersion: String,
        requestID: UUID
    ) async throws -> ExerciseSession {
        throw ExerciseServiceError.notConfigured
    }
    func claim(
        sessionID: UUID,
        completedReps: Int,
        durationSeconds: Double,
        completedAt: Date,
        detectionVersion: String
    ) async throws -> ExerciseReward {
        throw ExerciseServiceError.notConfigured
    }
}
