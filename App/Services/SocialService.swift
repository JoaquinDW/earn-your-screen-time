import EarnDomain
import Foundation
import Supabase

// MARK: - Models

struct SocialProfile: Decodable, Equatable, Sendable {
    let userId: UUID
    let displayName: String
    let inviteCode: String
    let shareMisses: Bool
    let pushEnabled: Bool
}

struct SocialProgress: Decodable, Equatable, Sendable {
    let day: String
    let dailyGoal: Int
    let activityAmount: Int
    let earnedSeconds: Int
    let streakDays: Int
    let isFinal: Bool

    var goalMet: Bool { dailyGoal > 0 && activityAmount >= dailyGoal }
}

struct SocialFriend: Decodable, Equatable, Identifiable, Sendable {
    let userId: UUID
    let displayName: String
    let today: SocialProgress?
    let yesterday: SocialProgress?
    let nudgedToday: Bool
    let cheeredToday: Bool

    var id: UUID { userId }
    /// Yesterday is over and short of its goal, and today is not on goal yet: worth a nudge.
    var missedYesterday: Bool {
        guard let yesterday, yesterday.isFinal else { return false }
        return !yesterday.goalMet && today?.goalMet != true
    }
}

struct SquadStanding: Decodable, Equatable, Identifiable, Sendable {
    let userId: UUID
    let displayName: String
    let goalDays: Int
    let earnedSeconds: Int
    let streakDays: Int

    var id: UUID { userId }
}

struct SocialSquad: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let inviteCode: String
    let weekStart: String
    let standings: [SquadStanding]
}

struct SocialEvent: Decodable, Equatable, Identifiable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case missedGoal = "missed_goal"
        case nudge
        case cheer
        case friendAdded = "friend_added"
    }

    let id: UUID
    let kind: Kind
    let day: String
    let isRead: Bool
    let actorName: String
}

struct SocialOverview: Decodable, Equatable, Sendable {
    let profile: SocialProfile?
    let friends: [SocialFriend]
    let squads: [SocialSquad]
    let events: [SocialEvent]

    static let empty = SocialOverview(profile: nil, friends: [], squads: [], events: [])

    var unreadCount: Int { events.filter { !$0.isRead }.count }
}

enum SocialSendKind: String, Encodable, Sendable {
    case nudge
    case cheer
}

enum SocialServiceError: LocalizedError, Equatable {
    case notConfigured
    case server(code: String, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Friends are not configured in this build."
        case let .server(_, message): message
        case .invalidResponse: "The friends service returned an invalid response."
        }
    }

    var code: String? {
        if case let .server(code, _) = self { return code }
        return nil
    }
}

protocol SocialServing: Sendable {
    func overview(today: DayKey) async throws -> SocialOverview
    func saveProfile(displayName: String?, shareMisses: Bool?) async throws -> SocialProfile
    func registerPushToken(_ token: String, environment: String) async throws
    func deleteProfile() async throws
    func addFriend(code: String, today: DayKey) async throws -> String
    func removeFriend(_ id: UUID) async throws
    func recordProgress(_ days: [AccountabilityDay]) async throws
    func send(_ kind: SocialSendKind, to friend: UUID, today: DayKey) async throws -> Bool
    func createSquad(name: String) async throws
    func joinSquad(code: String) async throws -> String
    func leaveSquad(_ id: UUID) async throws
    func markEventsRead() async throws
}

// MARK: - Supabase

actor SupabaseSocialService: SocialServing {
    private let url: URL
    private let publishableKey: String
    private let client: SupabaseClient
    private let http: URLSession
    private let requestTimeout: TimeInterval

    init?(
        url: URL? = AppConfiguration.supabaseURL,
        publishableKey: String? = AppConfiguration.supabasePublishableKey,
        http: URLSession = .shared,
        requestTimeout: TimeInterval = 15
    ) {
        guard let url, let publishableKey else { return nil }
        self.url = url
        self.publishableKey = publishableKey
        self.http = http
        self.requestTimeout = requestTimeout
        // The same anonymous identity the study and exercise services use: one person, one id.
        client = SupabaseClient(supabaseURL: url, supabaseKey: publishableKey)
    }

    func overview(today: DayKey) async throws -> SocialOverview {
        try await invoke(Request(action: "overview", today: today.description))
    }

    func saveProfile(displayName: String?, shareMisses: Bool?) async throws -> SocialProfile {
        let response: ProfileResponse = try await invoke(Request(
            action: "save_profile",
            displayName: displayName,
            shareMisses: shareMisses
        ))
        return response.profile
    }

    func registerPushToken(_ token: String, environment: String) async throws {
        let _: ProfileResponse = try await invoke(Request(
            action: "save_profile",
            apnsToken: token,
            apnsEnvironment: environment
        ))
    }

    func deleteProfile() async throws {
        let _: Ignored = try await invoke(Request(action: "delete_profile"))
    }

    func addFriend(code: String, today: DayKey) async throws -> String {
        let response: FriendResponse = try await invoke(Request(
            action: "add_friend",
            today: today.description,
            inviteCode: code
        ))
        return response.friend.displayName
    }

    func removeFriend(_ id: UUID) async throws {
        let _: Ignored = try await invoke(Request(action: "remove_friend", friendId: id.uuidString.lowercased()))
    }

    func recordProgress(_ days: [AccountabilityDay]) async throws {
        guard !days.isEmpty else { return }
        let _: Ignored = try await invoke(Request(action: "record_progress", days: days.map(ProgressBody.init)))
    }

    func send(_ kind: SocialSendKind, to friend: UUID, today: DayKey) async throws -> Bool {
        let response: SendResponse = try await invoke(Request(
            action: "send",
            today: today.description,
            friendId: friend.uuidString.lowercased(),
            kind: kind
        ))
        return response.sent
    }

    func createSquad(name: String) async throws {
        let _: Ignored = try await invoke(Request(action: "create_squad", name: name))
    }

    func joinSquad(code: String) async throws -> String {
        let response: SquadResponse = try await invoke(Request(action: "join_squad", inviteCode: code))
        return response.squad.name
    }

    func leaveSquad(_ id: UUID) async throws {
        let _: Ignored = try await invoke(Request(action: "leave_squad", squadId: id.uuidString.lowercased()))
    }

    func markEventsRead() async throws {
        let _: Ignored = try await invoke(Request(action: "mark_read"))
    }

    private func invoke<Response: Decodable>(_ body: Request) async throws -> Response {
        let session: Session
        if let existing = try? await client.auth.session {
            session = existing
        } else {
            session = try await client.auth.signInAnonymously()
        }
        var request = URLRequest(url: url.appending(path: "functions/v1/social"), timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await http.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SocialServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard (200..<300).contains(httpResponse.statusCode) else {
            let payload = try? decoder.decode(ErrorResponse.self, from: data)
            throw SocialServiceError.server(
                code: payload?.code ?? "http_\(httpResponse.statusCode)",
                message: payload?.error ?? "The friends request failed."
            )
        }
        guard let decoded = try? decoder.decode(Response.self, from: data) else {
            throw SocialServiceError.invalidResponse
        }
        return decoded
    }

    /// Every action posts one object; nil fields are left out of the JSON.
    private struct Request: Encodable {
        let action: String
        var today: String?
        var displayName: String?
        var shareMisses: Bool?
        var apnsToken: String?
        var apnsEnvironment: String?
        var inviteCode: String?
        var friendId: String?
        var squadId: String?
        var kind: SocialSendKind?
        var name: String?
        var days: [ProgressBody]?

        init(
            action: String,
            today: String? = nil,
            displayName: String? = nil,
            shareMisses: Bool? = nil,
            apnsToken: String? = nil,
            apnsEnvironment: String? = nil,
            inviteCode: String? = nil,
            friendId: String? = nil,
            squadId: String? = nil,
            kind: SocialSendKind? = nil,
            name: String? = nil,
            days: [ProgressBody]? = nil
        ) {
            self.action = action
            self.today = today
            self.displayName = displayName
            self.shareMisses = shareMisses
            self.apnsToken = apnsToken
            self.apnsEnvironment = apnsEnvironment
            self.inviteCode = inviteCode
            self.friendId = friendId
            self.squadId = squadId
            self.kind = kind
            self.name = name
            self.days = days
        }
    }

    private struct ProgressBody: Encodable {
        let day: String
        let dailyGoal: Int
        let activityAmount: Int
        let earnedSeconds: Int
        let streakDays: Int
        let isFinal: Bool

        init(_ day: AccountabilityDay) {
            self.day = day.day.description
            dailyGoal = day.dailyGoal
            activityAmount = day.activityAmount
            earnedSeconds = day.earnedSeconds
            streakDays = day.streakDays
            isFinal = day.isFinal
        }
    }

    private struct ProfileResponse: Decodable { let profile: SocialProfile }
    private struct FriendResponse: Decodable {
        struct Friend: Decodable { let displayName: String }
        let friend: Friend
    }
    private struct SquadResponse: Decodable {
        struct Squad: Decodable { let name: String }
        let squad: Squad
    }
    private struct SendResponse: Decodable { let sent: Bool }
    private struct Ignored: Decodable {}
    private struct ErrorResponse: Decodable {
        let error: String
        let code: String
    }
}

/// Builds without Supabase keys: the Friends screen explains it is unavailable.
struct UnconfiguredSocialService: SocialServing {
    func overview(today: DayKey) async throws -> SocialOverview { throw SocialServiceError.notConfigured }
    func saveProfile(displayName: String?, shareMisses: Bool?) async throws -> SocialProfile { throw SocialServiceError.notConfigured }
    func registerPushToken(_ token: String, environment: String) async throws { throw SocialServiceError.notConfigured }
    func deleteProfile() async throws { throw SocialServiceError.notConfigured }
    func addFriend(code: String, today: DayKey) async throws -> String { throw SocialServiceError.notConfigured }
    func removeFriend(_ id: UUID) async throws { throw SocialServiceError.notConfigured }
    func recordProgress(_ days: [AccountabilityDay]) async throws { throw SocialServiceError.notConfigured }
    func send(_ kind: SocialSendKind, to friend: UUID, today: DayKey) async throws -> Bool { throw SocialServiceError.notConfigured }
    func createSquad(name: String) async throws { throw SocialServiceError.notConfigured }
    func joinSquad(code: String) async throws -> String { throw SocialServiceError.notConfigured }
    func leaveSquad(_ id: UUID) async throws { throw SocialServiceError.notConfigured }
    func markEventsRead() async throws { throw SocialServiceError.notConfigured }
}
