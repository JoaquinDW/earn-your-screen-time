import EarnDomain
import Foundation
import Observation

/// Loads Friends and runs its actions. Every action reloads the overview afterwards, so the
/// screen always shows what the server holds.
@MainActor
@Observable
final class FriendsModel {
    enum Phase: Equatable {
        case loading
        case unavailable
        case setup
        case ready
    }

    private(set) var phase: Phase = .loading
    private(set) var overview = SocialOverview.empty
    private(set) var isWorking = false
    /// A localized message for the last failed action, shown under the header.
    var message: String?

    func load(in env: AppEnvironment) async {
        do {
            overview = try await env.social.overview(today: env.state.ledger.day)
            phase = overview.profile == nil ? .setup : .ready
            if overview.profile == nil, env.hasSocialProfile {
                await env.socialProfileDidChange(hasProfile: false)
            } else if overview.profile != nil, !env.hasSocialProfile {
                await env.socialProfileDidChange(hasProfile: true)
            }
            env.setSocialUnreadCount(overview.unreadCount)
        } catch SocialServiceError.notConfigured {
            phase = .unavailable
        } catch {
            if phase == .loading { phase = .unavailable }
            message = Self.message(for: error, locale: env.appLanguage.locale)
        }
    }

    /// Opening Friends reads the inbox.
    func markEventsRead(in env: AppEnvironment) async {
        guard overview.unreadCount > 0 else { return }
        try? await env.social.markEventsRead()
        env.setSocialUnreadCount(0)
    }

    func createProfile(name: String, in env: AppEnvironment) async {
        await perform(in: env) {
            _ = try await env.social.saveProfile(displayName: name, shareMisses: true)
            env.analytics.track(.socialProfileCreated)
            await env.socialProfileDidChange(hasProfile: true)
        }
    }

    func setShareMisses(_ share: Bool, in env: AppEnvironment) async {
        await perform(in: env) {
            _ = try await env.social.saveProfile(displayName: nil, shareMisses: share)
            env.analytics.track(.socialSettingChanged.withProperties(["share_misses": .bool(share)]))
        }
    }

    func leave(in env: AppEnvironment) async {
        await perform(in: env) {
            try await env.social.deleteProfile()
            env.analytics.track(.socialProfileDeleted)
            await env.socialProfileDidChange(hasProfile: false)
        }
    }

    func addFriend(code: String, in env: AppEnvironment) async {
        await perform(in: env) {
            _ = try await env.social.addFriend(code: code, today: env.state.ledger.day)
            env.analytics.track(.friendAdded)
        }
    }

    func remove(_ friend: SocialFriend, in env: AppEnvironment) async {
        await perform(in: env) {
            try await env.social.removeFriend(friend.userId)
            env.analytics.track(.friendRemoved)
        }
    }

    func send(_ kind: SocialSendKind, to friend: SocialFriend, in env: AppEnvironment) async {
        await perform(in: env) {
            _ = try await env.social.send(kind, to: friend.userId, today: env.state.ledger.day)
            env.analytics.track(.friendMessageSent.withProperties([
                "kind": .string(kind.rawValue),
                "friend_missed_yesterday": .bool(friend.missedYesterday)
            ]))
        }
    }

    func createSquad(name: String, in env: AppEnvironment) async {
        await perform(in: env) {
            try await env.social.createSquad(name: name)
            env.analytics.track(.squadCreated)
        }
    }

    func joinSquad(code: String, in env: AppEnvironment) async {
        await perform(in: env) {
            _ = try await env.social.joinSquad(code: code)
            env.analytics.track(.squadJoined)
        }
    }

    func leave(_ squad: SocialSquad, in env: AppEnvironment) async {
        await perform(in: env) {
            try await env.social.leaveSquad(squad.id)
        }
    }

    private func perform(in env: AppEnvironment, _ action: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        message = nil
        do {
            try await action()
        } catch {
            message = Self.message(for: error, locale: env.appLanguage.locale)
        }
        await load(in: env)
    }

    static func message(for error: Error, locale: Locale) -> String {
        let key: String.LocalizationValue = switch (error as? SocialServiceError)?.code {
        case "code_not_found": "friends.error.codeNotFound"
        case "own_code": "friends.error.ownCode"
        case "friend_limit": "friends.error.friendLimit"
        case "squad_limit": "friends.error.squadLimit"
        case "squad_full": "friends.error.squadFull"
        default: "friends.error.generic"
        }
        return String(localized: key, locale: locale)
    }
}
