import Foundation

/// The hours protected apps are shielded. Without one, they are shielded around the clock.
///
/// Opal and BePresent both let people block only during work or at night, and leave the apps
/// alone otherwise. A schedule is one daily window, on chosen weekdays; outside it the apps are
/// free and earned minutes stay in the wallet.
public struct BlockSchedule: Codable, Equatable, Sendable {
    /// DeviceActivity needs at least 15 minutes; an hour is the smallest window worth offering.
    public static let minimumDurationMinutes = 60
    public static let minutesPerDay = 24 * 60

    /// Minutes after local midnight. An end at or before the start crosses midnight.
    public let startMinute: Int
    public let endMinute: Int
    /// `Calendar` weekdays (1 = Sunday … 7 = Saturday) on which the window *starts*. A window
    /// that crosses midnight belongs to the evening it started on.
    public let weekdays: Set<Int>

    public static let everyDay: Set<Int> = Set(1...7)
    public static let workdays: Set<Int> = Set(2...6)

    /// `nil` for a window shorter than the minimum or a schedule with no days.
    public init?(startMinute: Int, endMinute: Int, weekdays: Set<Int>) {
        let start = Self.normalized(startMinute)
        let end = Self.normalized(endMinute)
        let days = weekdays.filter { (1...7).contains($0) }
        guard !days.isEmpty else { return nil }
        let duration = (end - start + Self.minutesPerDay) % Self.minutesPerDay
        guard duration >= Self.minimumDurationMinutes else { return nil }
        self.startMinute = start
        self.endMinute = end
        self.weekdays = days
    }

    public var crossesMidnight: Bool { endMinute <= startMinute }

    public var durationMinutes: Int {
        (endMinute - startMinute + Self.minutesPerDay) % Self.minutesPerDay
    }

    public func isBlocking(at date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday else { return true }
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if !crossesMidnight {
            return weekdays.contains(weekday) && minute >= startMinute && minute < endMinute
        }
        if minute >= startMinute { return weekdays.contains(weekday) }
        if minute < endMinute { return weekdays.contains(weekday == 1 ? 7 : weekday - 1) }
        return false
    }

    /// The next moment the shields go up or come down, for "free until 9:00"-style copy.
    public func nextChange(after date: Date, calendar: Calendar = .current) -> Date? {
        let blocking = isBlocking(at: date, calendar: calendar)
        let today = calendar.startOfDay(for: date)
        // Every change happens at a window edge; a week and a bit of edges covers any weekdays.
        var edges: [Date] = []
        for offset in -1...8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for minute in [startMinute, endMinute] {
                if let edge = calendar.date(byAdding: .minute, value: minute, to: day), edge > date {
                    edges.append(edge)
                }
            }
        }
        return edges.sorted().first { isBlocking(at: $0, calendar: calendar) != blocking }
    }

    private static func normalized(_ minute: Int) -> Int {
        ((minute % minutesPerDay) + minutesPerDay) % minutesPerDay
    }

    private enum CodingKeys: String, CodingKey {
        case startMinute, endMinute, weekdays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let schedule = BlockSchedule(
            startMinute: try container.decode(Int.self, forKey: .startMinute),
            endMinute: try container.decode(Int.self, forKey: .endMinute),
            weekdays: try container.decode(Set<Int>.self, forKey: .weekdays)
        ) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid block schedule"
            ))
        }
        self = schedule
    }
}

/// Opal's "Deep Focus" and BePresent's "Beast Mode": for a chosen stretch, the person cannot
/// make blocking any weaker. Everything that would loosen it is refused until the end date.
public enum StrictMode {
    /// DeviceActivity schedules are capped at about a week, and the end of strict mode is
    /// delivered by one.
    public static let maximumDuration: TimeInterval = 6 * 24 * 3_600

    /// The end date for a strict period starting at `date`, clamped to the maximum.
    public static func endDate(startingAt date: Date, duration: TimeInterval) -> Date {
        date.addingTimeInterval(min(max(0, duration), maximumDuration))
    }

    /// Changing the schedule during strict mode may only make it block at least as much: the
    /// one schedule change that never frees an app is going back to around the clock.
    public static func allowsScheduleChange(from old: BlockSchedule?, to new: BlockSchedule?) -> Bool {
        new == nil || new == old
    }

    /// A rule may only get harder: more steps per reward, or fewer minutes for the same steps.
    public static func allowsRuleChange(from old: EarningRule, to new: EarningRule) -> Bool {
        new.amountRequired * old.rewardSeconds >= old.amountRequired * new.rewardSeconds
    }
}

extension SharedState {
    /// Whether the schedule shields the protected apps at `date`. No schedule means always.
    public func isWithinBlockingHours(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        blockSchedule?.isBlocking(at: date, calendar: calendar) ?? true
    }

    public func isStrictModeActive(at date: Date = Date()) -> Bool {
        guard let strictModeUntil else { return false }
        return date < strictModeUntil
    }
}
