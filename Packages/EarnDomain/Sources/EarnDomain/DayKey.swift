import Foundation

/// A calendar day in the user's local time zone (PRD §17).
public struct DayKey: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    public static func today(calendar: Calendar = .current, now: Date = Date()) -> DayKey {
        DayKey(date: now, calendar: calendar)
    }

    public func startOfDay(calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// The same day shifted by `days`, in the given calendar. `nil` only for a day that
    /// cannot be represented (a corrupt stored key).
    public func adding(days: Int, calendar: Calendar = .current) -> DayKey? {
        guard
            let start = startOfDay(calendar: calendar),
            let shifted = calendar.date(byAdding: .day, value: days, to: start)
        else { return nil }
        return DayKey(date: shifted, calendar: calendar)
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
