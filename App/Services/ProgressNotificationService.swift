import EarnDomain
import Foundation
import UserNotifications

/// When the daily walk reminder fires, and whether it does. Stored in the App Group so a
/// background step update, which may launch the app without its UI, reads the same choice.
struct DailyReminderPreference: Equatable {
    var isEnabled: Bool
    var hour: Int
    var minute: Int

    /// Early evening: late enough that the day's walk is still possible, early enough not to land
    /// at night. The same hour the inactivity nudges always used.
    static let `default` = DailyReminderPreference(isEnabled: true, hour: 18, minute: 0)

    private enum Key {
        static let enabled = "notifications.dailyReminder.enabled"
        static let hour = "notifications.dailyReminder.hour"
        static let minute = "notifications.dailyReminder.minute"
    }

    static var saved: DailyReminderPreference {
        let defaults = AppGroup.defaults
        guard defaults.object(forKey: Key.enabled) != nil else { return .default }
        return DailyReminderPreference(
            isEnabled: defaults.bool(forKey: Key.enabled),
            hour: defaults.integer(forKey: Key.hour),
            minute: defaults.integer(forKey: Key.minute)
        )
    }

    func save() {
        let defaults = AppGroup.defaults
        defaults.set(isEnabled, forKey: Key.enabled)
        defaults.set(hour, forKey: Key.hour)
        defaults.set(minute, forKey: Key.minute)
    }
}

/// Notifications about progress, as opposed to absence (`ReengagementNotificationService`) or a
/// running unlock (`SessionNotificationService`).
///
/// The screen-time apps people keep (AppBlock, BePresent, Blockin, Jomo) only notify about
/// something that just changed for the person — a block about to start, a limit almost reached.
/// For Earnit that is minutes earned while the phone was in a pocket, and a daily walk reminder
/// at a time the person chose, worded from where today actually stands.
@MainActor
final class ProgressNotificationService {
    enum Kind: String {
        case minutesEarned = "minutes_earned"
        case goalReached = "goal_reached"
        case dailyReminder = "daily_reminder"
    }

    struct Snapshot {
        let steps: Int
        let dailyGoal: Int
        let goalBonusMinutes: Int
        let goalReached: Bool
        let availableMinutes: Int
        let stepsPerReward: Int
        let rewardMinutes: Int
    }

    private let center = UNUserNotificationCenter.current()
    /// Every earned-minutes notice replaces the last, so a day of walking leaves one in the
    /// Notification Center rather than a stack of them.
    private static let earnedIdentifier = "progress.earned"
    private static let reminderPrefix = "progress.daily."
    /// Far enough ahead that someone who stops opening the app keeps getting the reminder for a
    /// week, which is also as long as the inactivity nudges run.
    private static let reminderDays = 7

    private var isAuthorized: Bool {
        get async {
            let status = await center.notificationSettings().authorizationStatus
            return status == .authorized || status == .provisional
        }
    }

    /// Delivered right away. Only called when the app is not in the foreground, where the
    /// in-app celebration already says the same thing.
    func notifyEarned(minutes: Int, reachedGoal: Bool, snapshot: Snapshot, language: AppLanguage) async {
        guard minutes > 0, await isAuthorized else { return }
        let locale = language.locale
        let content = UNMutableNotificationContent()
        content.sound = .default
        if reachedGoal {
            content.title = String(localized: "notification.progress.goal.title", locale: locale)
            content.body = String(
                localized: "notification.progress.goal.body \(snapshot.goalBonusMinutes) \(snapshot.availableMinutes)",
                locale: locale
            )
            content.userInfo = [ReengagementNotificationService.kindKey: Kind.goalReached.rawValue]
        } else {
            content.title = String(localized: "notification.progress.earned.title \(minutes)", locale: locale)
            content.body = String(
                localized: "notification.progress.earned.body \(snapshot.steps.formatted()) \(snapshot.availableMinutes)",
                locale: locale
            )
            content.userInfo = [ReengagementNotificationService.kindKey: Kind.minutesEarned.rawValue]
        }
        try? await center.add(UNNotificationRequest(
            identifier: Self.earnedIdentifier,
            content: content,
            trigger: nil
        ))
    }

    /// Rewritten on every step sync, so today's reminder speaks to today's remaining steps and
    /// disappears once the goal is met.
    func rescheduleDailyReminder(
        _ snapshot: Snapshot,
        preference: DailyReminderPreference,
        language: AppLanguage,
        now: Date = Date()
    ) async {
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.reminderPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard preference.isEnabled, await isAuthorized else { return }

        let calendar = Calendar.current
        for offset in 0..<Self.reminderDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fireDate = calendar.date(
                      bySettingHour: preference.hour,
                      minute: preference.minute,
                      second: 0,
                      of: day
                  ),
                  fireDate > now else { continue }
            let isToday = offset == 0
            if isToday, snapshot.goalReached { continue }
            let content = Self.reminderContent(snapshot, isToday: isToday, locale: language.locale)
            try? await center.add(UNNotificationRequest(
                identifier: Self.reminderPrefix + DayKey(date: fireDate).description,
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                    repeats: false
                )
            ))
        }
    }

    func cancelDailyReminders() async {
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.reminderPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
    }

    private static func reminderContent(_ snapshot: Snapshot, isToday: Bool, locale: Locale) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = [ReengagementNotificationService.kindKey: Kind.dailyReminder.rawValue]
        let remaining = max(0, snapshot.dailyGoal - snapshot.steps)
        if isToday, snapshot.steps > 0, remaining > 0 {
            content.title = String(
                localized: "notification.progress.reminder.partial.title \(remaining.formatted())",
                locale: locale
            )
            content.body = String(
                localized: "notification.progress.reminder.partial.body \(snapshot.goalBonusMinutes)",
                locale: locale
            )
        } else if isToday, snapshot.availableMinutes > 0 {
            content.title = String(
                localized: "notification.progress.reminder.balance.title \(snapshot.availableMinutes)",
                locale: locale
            )
            content.body = String(
                localized: "notification.progress.reminder.balance.body \(snapshot.stepsPerReward.formatted()) \(snapshot.rewardMinutes)",
                locale: locale
            )
        } else {
            content.title = String(localized: "notification.progress.reminder.title", locale: locale)
            content.body = String(
                localized: "notification.progress.reminder.body \(snapshot.stepsPerReward.formatted()) \(snapshot.rewardMinutes)",
                locale: locale
            )
        }
        return content
    }
}
