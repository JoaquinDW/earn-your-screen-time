import EarnDomain
import Foundation
import UserNotifications

@MainActor
final class SessionNotificationService {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func schedule(for session: ScreenTimeSession, language: AppLanguage) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
            return
        }

        cancel(sessionID: session.id)

        let endContent = UNMutableNotificationContent()
        endContent.title = String(
            localized: "session.notification.ended.title",
            locale: language.locale
        )
        endContent.body = String(
            localized: "session.notification.ended.body \(session.durationMinutes)",
            locale: language.locale
        )
        endContent.sound = .default
        await add(
            identifier: endIdentifier(session.id),
            content: endContent,
            fireAt: session.endsAt
        )

        let warningAt = session.endsAt.addingTimeInterval(-60)
        guard warningAt > Date() else { return }
        let warningContent = UNMutableNotificationContent()
        warningContent.title = String(
            localized: "session.notification.warning.title",
            locale: language.locale
        )
        warningContent.body = String(
            localized: "session.notification.warning.body",
            locale: language.locale
        )
        warningContent.sound = .default
        await add(
            identifier: warningIdentifier(session.id),
            content: warningContent,
            fireAt: warningAt
        )
    }

    func cancel(sessionID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [
            endIdentifier(sessionID),
            warningIdentifier(sessionID)
        ])
    }

    private func add(identifier: String, content: UNNotificationContent, fireAt: Date) async {
        let interval = max(1, fireAt.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try? await center.add(UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        ))
    }

    private func endIdentifier(_ id: UUID) -> String { "session.\(id).ended" }
    private func warningIdentifier(_ id: UUID) -> String { "session.\(id).warning" }
}
