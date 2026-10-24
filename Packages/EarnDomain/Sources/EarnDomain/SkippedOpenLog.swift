import Foundation

/// How many times a day the person met a shield and chose to stay out.
///
/// one sec's whole product is that pause and the count of opens it prevented. Earnit's shield
/// already is the pause; this is the count. The shield action extension writes it, so it lives
/// outside `SharedState` in its own App Group key rather than racing the monitor's ledger writes.
public struct SkippedOpenLog: Codable, Equatable, Sendable {
    /// Two months covers the Progress month view with room to spare.
    public static let retainedDays = 62

    /// Keyed by `DayKey.description` (`yyyy-MM-dd`), which also sorts chronologically.
    public private(set) var counts: [String: Int]
    /// Every skip ever recorded. Unlike `counts` it is never pruned, so the app can report only
    /// the skips analytics has not seen yet.
    public private(set) var totalRecorded: Int

    public init(counts: [String: Int] = [:], totalRecorded: Int? = nil) {
        self.counts = counts.filter { $0.value > 0 }
        self.totalRecorded = max(totalRecorded ?? 0, self.counts.values.reduce(0, +))
    }

    public func count(on day: DayKey) -> Int {
        counts[day.description] ?? 0
    }

    public func total(on days: [DayKey]) -> Int {
        Set(days).reduce(0) { $0 + count(on: $1) }
    }

    public mutating func record(on day: DayKey, calendar: Calendar = .current) {
        counts[day.description, default: 0] += 1
        totalRecorded += 1
        guard let cutoff = day.adding(days: -Self.retainedDays, calendar: calendar) else { return }
        counts = counts.filter { $0.key > cutoff.description }
    }

    private enum CodingKeys: String, CodingKey {
        case counts, totalRecorded
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            counts: (try? container.decodeIfPresent([String: Int].self, forKey: .counts)) ?? [:],
            totalRecorded: try? container.decodeIfPresent(Int.self, forKey: .totalRecorded)
        )
    }
}
