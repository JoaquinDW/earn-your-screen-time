import EarnDomain
import Foundation
import UserNotifications

/// Local nudges for someone who has stopped opening the app.
///
/// Nobody who finished onboarding in 1.2.2 came back on a second day, and nothing invited them
/// to: shields work silently and the only notifications were a session's own end. These three
/// are rescheduled every time the app is opened, so they only ever reach someone who has
/// actually been away — 1, 3 and 7 days after their last visit, in the early evening.
@MainActor
final class ReengagementNotificationService {
    enum Kind: String, CaseIterable {
        case inactiveDay1 = "inactive_day_1"
        case inactiveDay3 = "inactive_day_3"
        case inactiveDay7 = "inactive_day_7"

        var daysAfterLastOpen: Int {
            switch self {
            case .inactiveDay1: 1
            case .inactiveDay3: 3
            case .inactiveDay7: 7
            }
        }

        var identifier: String { "reengagement.\(rawValue)" }
    }

    /// What the copy needs to know about the person at the moment they left.
    struct Snapshot {
        let availableMinutes: Int
        let stepsPerReward: Int
        let rewardMinutes: Int
    }

    /// `userInfo` key carrying the `Kind`, read back when a notification is opened.
    nonisolated static let kindKey = "earnit.notification.kind"
    /// Late enough that the day's walk is still possible, early enough not to land at night.
    private static let deliveryHour = 18

    private let center = UNUserNotificationCenter.current()

    func reschedule(_ snapshot: Snapshot, language: AppLanguage, now: Date = Date()) async {
        cancelAll()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        for kind in Kind.allCases {
            guard let components = Self.deliveryComponents(daysAfter: kind.daysAfterLastOpen, from: now) else {
                continue
            }
            let content = Self.content(for: kind, snapshot: snapshot, locale: language.locale)
            try? await center.add(UNNotificationRequest(
                identifier: kind.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            ))
        }
    }

    func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: Kind.allCases.map(\.identifier))
    }

    private static func deliveryComponents(daysAfter days: Int, from now: Date) -> DateComponents? {
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: days, to: now),
              let fireDate = calendar.date(bySettingHour: deliveryHour, minute: 0, second: 0, of: day) else {
            return nil
        }
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
    }

    private static func content(for kind: Kind, snapshot: Snapshot, locale: Locale) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = [kindKey: kind.rawValue]
        // Banked minutes never expire, so a balance is the strongest reason to come back on any
        // of the three days.
        if snapshot.availableMinutes > 0 {
            content.title = String(localized: "notification.reengage.balance.title", locale: locale)
            content.body = String(
                localized: "notification.reengage.balance.body \(snapshot.availableMinutes)",
                locale: locale
            )
            return content
        }
        switch kind {
        case .inactiveDay1:
            content.title = String(
                localized: "notification.reengage.day1.title \(snapshot.stepsPerReward) \(snapshot.rewardMinutes)",
                locale: locale
            )
            content.body = String(localized: "notification.reengage.day1.body", locale: locale)
        case .inactiveDay3:
            content.title = String(localized: "notification.reengage.day3.title", locale: locale)
            content.body = String(localized: "notification.reengage.day3.body", locale: locale)
        case .inactiveDay7:
            content.title = String(localized: "notification.reengage.day7.title", locale: locale)
            content.body = String(localized: "notification.reengage.day7.body", locale: locale)
        }
        return content
    }
}

/// Reports which local notification brought someone back. Without a delegate iOS still opens
/// the app on a tap, but the app never learns that a notification was the reason.
final class NotificationOpenTracker: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: (@MainActor (String) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        // Session notifications predate the kind key; their identifier says which one they are.
        let kind = request.content.userInfo[ReengagementNotificationService.kindKey] as? String
            ?? (request.identifier.hasSuffix(".warning") ? "session_warning" : "session_ended")
        Task { @MainActor [onOpen] in onOpen?(kind) }
        completionHandler()
    }
}
