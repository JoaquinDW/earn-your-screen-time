import Foundation
import Supabase

struct StudyConfiguration: Equatable, Sendable {
    let enabled: Bool
    let entitled: Bool
    let rewardSeconds: Int
    let dailyCapSeconds: Int
    let maxRegenerations: Int
    let sourceTextMinLength: Int
    let sourceTextMaxLength: Int
    let completionsToday: Int
    let canEarnFullReward: Bool
    let nextAvailableAt: Date?
}

struct StudyQuestion: Equatable, Sendable {
    let sessionID: UUID
    let text: String
    let regenerationCount: Int
    let answerAttemptCount: Int
}

struct StudyEvaluation: Equatable, Sendable {
    let pass: Bool
    let confidence: Double
    let feedback: String
    let missingConcept: String?
    let reward: StudyAPIReturnedReward?
}

struct StudyAPIReturnedReward: Equatable, Sendable {
    let id: UUID
    let amountSeconds: Int
    let issuedAt: Date
    let sessionID: UUID
}

protocol StudyServing: Sendable {
    func ensureIdentity() async throws -> UUID
    func configuration() async throws -> StudyConfiguration
    func start(sourceText: String, locale: String, requestID: UUID) async throws -> StudyQuestion
    func regenerate(sessionID: UUID) async throws -> StudyQuestion
    func submit(answer: String, sessionID: UUID) async throws -> StudyEvaluation
    func abandon(sessionID: UUID) async
}

enum StudyServiceError: LocalizedError, Equatable {
    case notConfigured
    case server(code: String, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Study to Earn is not configured in this build."
        case let .server(_, message): message
        case .invalidResponse: "The study service returned an invalid response."
        }
    }

    var code: String? {
        if case let .server(code, _) = self { return code }
        return nil
    }
}

actor SupabaseStudyService: StudyServing {
    private let url: URL
    private let publishableKey: String
    private let client: SupabaseClient
    private let http: URLSession

    init?(
        url: URL? = AppConfiguration.supabaseURL,
        publishableKey: String? = AppConfiguration.supabasePublishableKey,
        http: URLSession = .shared
    ) {
        guard let url, let publishableKey else { return nil }
        self.url = url
        self.publishableKey = publishableKey
        self.http = http
        client = SupabaseClient(supabaseURL: url, supabaseKey: publishableKey)
    }

    func ensureIdentity() async throws -> UUID {
        if let session = try? await client.auth.session {
            return session.user.id
        }
        return try await client.auth.signInAnonymously().user.id
    }

    func configuration() async throws -> StudyConfiguration {
        let response: ConfigResponse = try await invoke(
            "study-config",
            method: "GET",
            body: Optional<EmptyBody>.none
        )
        return StudyConfiguration(
            enabled: response.configuration.enabled,
            entitled: response.entitled,
            rewardSeconds: response.configuration.rewardSeconds,
            dailyCapSeconds: response.configuration.dailyCapSeconds,
            maxRegenerations: response.configuration.maxRegenerations,
            sourceTextMinLength: response.configuration.sourceTextMinLength,
            sourceTextMaxLength: response.configuration.sourceTextMaxLength,
            completionsToday: response.availability.completionsToday,
            canEarnFullReward: response.availability.canEarnFullReward,
            nextAvailableAt: Self.date(response.availability.nextAvailableAt)
        )
    }

    func start(sourceText: String, locale: String, requestID: UUID) async throws -> StudyQuestion {
        let response: SessionResponse = try await invoke(
            "study-session",
            method: "POST",
            body: SessionRequest(
                action: "start",
                sessionID: nil,
                clientRequestID: requestID,
                sourceText: sourceText,
                locale: locale
            )
        )
        return response.session.questionModel
    }

    func regenerate(sessionID: UUID) async throws -> StudyQuestion {
        let response: SessionResponse = try await invoke(
            "study-session",
            method: "POST",
            body: SessionRequest(
                action: "regenerate",
                sessionID: sessionID,
                clientRequestID: nil,
                sourceText: nil,
                locale: nil
            )
        )
        return response.session.questionModel
    }

    func submit(answer: String, sessionID: UUID) async throws -> StudyEvaluation {
        let response: EvaluationResponse = try await invoke(
            "study-answer",
            method: "POST",
            body: AnswerRequest(sessionID: sessionID, answer: answer)
        )
        let reward: StudyAPIReturnedReward?
        if let returnedReward = response.reward {
            guard let issuedAt = Self.date(returnedReward.createdAt) else {
                throw StudyServiceError.invalidResponse
            }
            reward = StudyAPIReturnedReward(
                id: returnedReward.id,
                amountSeconds: returnedReward.amountSeconds,
                issuedAt: issuedAt,
                sessionID: returnedReward.sessionID
            )
        } else {
            reward = nil
        }
        return StudyEvaluation(
            pass: response.pass,
            confidence: response.confidence ?? 1,
            feedback: response.feedback ?? "",
            missingConcept: response.missingConcept,
            reward: reward
        )
    }

    func abandon(sessionID: UUID) async {
        let _: SessionResponse? = try? await invoke(
            "study-session",
            method: "POST",
            body: SessionRequest(
                action: "abandon",
                sessionID: sessionID,
                clientRequestID: nil,
                sourceText: nil,
                locale: nil
            )
        )
    }

    private func invoke<Response: Decodable, Body: Encodable>(
        _ function: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        let session: Session
        if let existing = try? await client.auth.session {
            session = existing
        } else {
            session = try await client.auth.signInAnonymously()
        }
        var request = URLRequest(url: url.appending(path: "functions/v1/\(function)"))
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
            throw StudyServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard (200..<300).contains(httpResponse.statusCode) else {
            let payload = try? decoder.decode(ErrorResponse.self, from: data)
            throw StudyServiceError.server(
                code: payload?.code ?? "http_\(httpResponse.statusCode)",
                message: payload?.error ?? "The study request failed."
            )
        }
        guard let decoded = try? decoder.decode(Response.self, from: data) else {
            throw StudyServiceError.invalidResponse
        }
        return decoded
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct EmptyBody: Encodable {}
private struct ErrorResponse: Decodable { let error: String; let code: String }

private struct ConfigResponse: Decodable {
    struct Configuration: Decodable {
        let enabled: Bool
        let rewardSeconds: Int
        let dailyCapSeconds: Int
        let maxRegenerations: Int
        let sourceTextMinLength: Int
        let sourceTextMaxLength: Int
    }
    struct Availability: Decodable {
        let completionsToday: Int
        let canEarnFullReward: Bool
        let nextAvailableAt: String?
    }
    let configuration: Configuration
    let entitled: Bool
    let availability: Availability
}

private struct SessionRequest: Encodable {
    let action: String
    let sessionID: UUID?
    let clientRequestID: UUID?
    let sourceText: String?
    let locale: String?
}

private struct SessionResponse: Decodable {
    struct RemoteSession: Decodable {
        let id: UUID
        let question: String?
        let regenerationCount: Int?
        let answerAttemptCount: Int?

        var questionModel: StudyQuestion {
            StudyQuestion(
                sessionID: id,
                text: question ?? "",
                regenerationCount: regenerationCount ?? 0,
                answerAttemptCount: answerAttemptCount ?? 0
            )
        }
    }
    let session: RemoteSession
}

private struct AnswerRequest: Encodable { let sessionID: UUID; let answer: String }

private struct EvaluationResponse: Decodable {
    struct Reward: Decodable {
        let id: UUID
        let amountSeconds: Int
        let createdAt: String
        let sessionID: UUID
    }
    let pass: Bool
    let confidence: Double?
    let feedback: String?
    let missingConcept: String?
    let reward: Reward?
}

actor UnconfiguredStudyService: StudyServing {
    func ensureIdentity() async throws -> UUID { throw StudyServiceError.notConfigured }
    func configuration() async throws -> StudyConfiguration { throw StudyServiceError.notConfigured }
    func start(sourceText: String, locale: String, requestID: UUID) async throws -> StudyQuestion {
        throw StudyServiceError.notConfigured
    }
    func regenerate(sessionID: UUID) async throws -> StudyQuestion { throw StudyServiceError.notConfigured }
    func submit(answer: String, sessionID: UUID) async throws -> StudyEvaluation { throw StudyServiceError.notConfigured }
    func abandon(sessionID: UUID) async {}
}
