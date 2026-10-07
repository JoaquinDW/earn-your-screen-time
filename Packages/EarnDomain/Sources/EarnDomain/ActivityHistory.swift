import Foundation

/// What a finished day amounted to.
///
/// Only the two numbers the product ever shows again: how much was walked, and how much screen
/// time that bought. Consumption is not kept — how the time was spent is the user's business,
/// and the "This week" screen is about what they earned.
public struct DaySummary: Codable, Equatable, Sendable {
    public let day: DayKey
    public let activityAmount: Int
    public let earnedSeconds: Int
    public let stepEarnedSeconds: Int
    public let studyEarnedSeconds: Int
    public let pushupEarnedSeconds: Int
    public let squatEarnedSeconds: Int
    public let consumedSeconds: Int
    public let sessionCount: Int
    public let returnedSeconds: Int
    /// False for payloads written before usage history existed and for calendar gaps.
    public let hasUsageData: Bool

    public init(day: DayKey, activityAmount: Int, earnedSeconds: Int) {
        self.init(
            day: day,
            activityAmount: activityAmount,
            stepEarnedSeconds: earnedSeconds,
            studyEarnedSeconds: 0,
            pushupEarnedSeconds: 0,
            squatEarnedSeconds: 0,
            consumedSeconds: 0,
            sessionCount: 0,
            returnedSeconds: 0,
            hasUsageData: true
        )
    }

    public init(
        day: DayKey,
        activityAmount: Int,
        stepEarnedSeconds: Int,
        studyEarnedSeconds: Int,
        pushupEarnedSeconds: Int = 0,
        squatEarnedSeconds: Int = 0,
        consumedSeconds: Int = 0,
        sessionCount: Int = 0,
        returnedSeconds: Int = 0,
        hasUsageData: Bool = true
    ) {
        self.day = day
        self.activityAmount = max(0, activityAmount)
        self.stepEarnedSeconds = max(0, stepEarnedSeconds)
        self.studyEarnedSeconds = max(0, studyEarnedSeconds)
        self.pushupEarnedSeconds = max(0, pushupEarnedSeconds)
        self.squatEarnedSeconds = max(0, squatEarnedSeconds)
        self.consumedSeconds = max(0, consumedSeconds)
        self.sessionCount = max(0, sessionCount)
        self.returnedSeconds = max(0, returnedSeconds)
        self.hasUsageData = hasUsageData
        earnedSeconds = self.stepEarnedSeconds + self.studyEarnedSeconds + self.pushupEarnedSeconds
            + self.squatEarnedSeconds
    }

    public init(ledger: DailyLedger) {
        let studySeconds = ledger.walletTransactions.reduce(into: 0) { total, transaction in
            if transaction.kind == .earned, transaction.source == .study {
                total += transaction.amountSeconds
            }
        }
        let pushupSeconds = ledger.walletTransactions.reduce(into: 0) { total, transaction in
            if transaction.kind == .earned, transaction.source == .pushups {
                total += transaction.amountSeconds
            }
        }
        let squatSeconds = ledger.walletTransactions.reduce(into: 0) { total, transaction in
            if transaction.kind == .earned, transaction.source == .squats {
                total += transaction.amountSeconds
            }
        }
        self.init(
            day: ledger.day,
            activityAmount: ledger.activityAmount,
            stepEarnedSeconds: max(0, ledger.wallet.earnedSeconds - studySeconds - pushupSeconds - squatSeconds),
            studyEarnedSeconds: studySeconds,
            pushupEarnedSeconds: pushupSeconds,
            squatEarnedSeconds: squatSeconds,
            consumedSeconds: ledger.wallet.consumedSeconds,
            sessionCount: ledger.sessionCount,
            returnedSeconds: ledger.returnedSessionSeconds
        )
    }

    public var earnedMinutes: Int { earnedSeconds / 60 }
    public var consumedMinutes: Int { consumedSeconds / 60 }
    public var returnedMinutes: Int { returnedSeconds / 60 }
    public var netSeconds: Int { earnedSeconds - consumedSeconds }
    /// A day only counts toward a streak if it actually earned something.
    public var didEarn: Bool { earnedSeconds > 0 }

    private enum CodingKeys: String, CodingKey {
        case day, activityAmount, earnedSeconds, stepEarnedSeconds, studyEarnedSeconds, pushupEarnedSeconds
        case squatEarnedSeconds
        case consumedSeconds, sessionCount, returnedSeconds
        case hasUsageData
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let historicalEarnedSeconds = max(0, try container.decodeIfPresent(Int.self, forKey: .earnedSeconds) ?? 0)
        let studySeconds = max(0, try container.decodeIfPresent(Int.self, forKey: .studyEarnedSeconds) ?? 0)
        let pushupSeconds = max(0, try container.decodeIfPresent(Int.self, forKey: .pushupEarnedSeconds) ?? 0)
        // Days filed before v15 predate squats.
        let squatSeconds = max(0, try container.decodeIfPresent(Int.self, forKey: .squatEarnedSeconds) ?? 0)
        let hasPersistedUsage = container.contains(.consumedSeconds)
            || container.contains(.sessionCount)
            || container.contains(.returnedSeconds)
        self.init(
            day: try container.decode(DayKey.self, forKey: .day),
            activityAmount: try container.decodeIfPresent(Int.self, forKey: .activityAmount) ?? 0,
            stepEarnedSeconds: try container.decodeIfPresent(Int.self, forKey: .stepEarnedSeconds)
                ?? max(0, historicalEarnedSeconds - studySeconds - pushupSeconds - squatSeconds),
            studyEarnedSeconds: studySeconds,
            pushupEarnedSeconds: pushupSeconds,
            squatEarnedSeconds: squatSeconds,
            consumedSeconds: try container.decodeIfPresent(Int.self, forKey: .consumedSeconds) ?? 0,
            sessionCount: try container.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 0,
            returnedSeconds: try container.decodeIfPresent(Int.self, forKey: .returnedSeconds) ?? 0,
            hasUsageData: try container.decodeIfPresent(Bool.self, forKey: .hasUsageData) ?? hasPersistedUsage
        )
    }
}

/// A rolling calendar-month-sized window of finished days.
///
/// Bounded on purpose: this lives in App Group `UserDefaults` alongside the state the monitor
/// extension reads under a tight memory budget, so it holds 31 days, not a lifetime.
public struct ActivityHistory: Codable, Equatable, Sendable {
    public static let maxDays = 31

    /// Oldest first. Never contains today — a day is only recorded once it is over.
    public private(set) var days: [DaySummary]

    public init(days: [DaySummary] = []) {
        self.days = Array(days.sorted { $0.day < $1.day }.suffix(Self.maxDays))
    }

    /// Files a finished day, replacing any earlier record of the same day.
    public mutating func record(_ summary: DaySummary) {
        days.removeAll { $0.day == summary.day }
        days.append(summary)
        days.sort { $0.day < $1.day }
        if days.count > Self.maxDays {
            days.removeFirst(days.count - Self.maxDays)
        }
    }

    public mutating func record(_ ledger: DailyLedger) {
        record(DaySummary(ledger: ledger))
    }

    public struct Totals: Equatable, Sendable {
        public let activityAmount: Int
        public let earnedSeconds: Int
        public let stepEarnedSeconds: Int
        public let studyEarnedSeconds: Int
        public let pushupEarnedSeconds: Int
        public let squatEarnedSeconds: Int
        public let consumedSeconds: Int
        public let sessionCount: Int
        public let returnedSeconds: Int
        public let activeDays: Int

        public var steps: Int { activityAmount }
        public var earnedMinutes: Int { earnedSeconds / 60 }
        public var consumedMinutes: Int { consumedSeconds / 60 }
        public var returnedMinutes: Int { returnedSeconds / 60 }
        public var netSeconds: Int { earnedSeconds - consumedSeconds }
    }

    /// Totals for an inclusive day range. A live summary may replace a stored summary for its day.
    public func totals(
        from start: DayKey,
        through end: DayKey,
        including liveSummary: DaySummary? = nil
    ) -> Totals {
        guard start <= end else {
            return Totals(
                activityAmount: 0,
                earnedSeconds: 0,
                stepEarnedSeconds: 0,
                studyEarnedSeconds: 0,
                pushupEarnedSeconds: 0,
                squatEarnedSeconds: 0,
                consumedSeconds: 0,
                sessionCount: 0,
                returnedSeconds: 0,
                activeDays: 0
            )
        }
        var byDay = Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0) })
        if let liveSummary { byDay[liveSummary.day] = liveSummary }
        let summaries = byDay.values.filter { $0.day >= start && $0.day <= end }
        return Totals(
            activityAmount: summaries.reduce(0) { $0 + $1.activityAmount },
            earnedSeconds: summaries.reduce(0) { $0 + $1.earnedSeconds },
            stepEarnedSeconds: summaries.reduce(0) { $0 + $1.stepEarnedSeconds },
            studyEarnedSeconds: summaries.reduce(0) { $0 + $1.studyEarnedSeconds },
            pushupEarnedSeconds: summaries.reduce(0) { $0 + $1.pushupEarnedSeconds },
            squatEarnedSeconds: summaries.reduce(0) { $0 + $1.squatEarnedSeconds },
            consumedSeconds: summaries.reduce(0) { $0 + $1.consumedSeconds },
            sessionCount: summaries.reduce(0) { $0 + $1.sessionCount },
            returnedSeconds: summaries.reduce(0) { $0 + $1.returnedSeconds },
            activeDays: summaries.count { $0.activityAmount > 0 }
        )
    }

    public func totals(in range: ClosedRange<DayKey>, including liveSummary: DaySummary? = nil) -> Totals {
        totals(from: range.lowerBound, through: range.upperBound, including: liveSummary)
    }

    public func totals(
        forMonthContaining day: DayKey,
        including liveSummary: DaySummary? = nil,
        calendar: Calendar = .current
    ) -> Totals {
        guard let date = day.startOfDay(calendar: calendar),
              let interval = calendar.dateInterval(of: .month, for: date),
              let lastDate = calendar.date(byAdding: .day, value: -1, to: interval.end)
        else {
            return Totals(
                activityAmount: 0,
                earnedSeconds: 0,
                stepEarnedSeconds: 0,
                studyEarnedSeconds: 0,
                pushupEarnedSeconds: 0,
                squatEarnedSeconds: 0,
                consumedSeconds: 0,
                sessionCount: 0,
                returnedSeconds: 0,
                activeDays: 0
            )
        }
        return totals(
            from: DayKey(date: interval.start, calendar: calendar),
            through: DayKey(date: lastDate, calendar: calendar),
            including: liveSummary
        )
    }

    /// The seven days ending on `today`, oldest first, with zero-filled gaps so the chart
    /// always has seven bars — a day the user did not open the app is a real zero.
    public func week(endingOn today: DayKey, including todayLedger: DailyLedger? = nil, calendar: Calendar = .current) -> [DaySummary] {
        var byDay = Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0) })
        if let todayLedger, todayLedger.day == today {
            byDay[today] = DaySummary(ledger: todayLedger)
        }
        return (0..<7).reversed().compactMap { offset in
            guard let day = today.adding(days: -offset, calendar: calendar) else { return nil }
            return byDay[day] ?? DaySummary(
                day: day,
                activityAmount: 0,
                stepEarnedSeconds: 0,
                studyEarnedSeconds: 0,
                hasUsageData: false
            )
        }
    }

    /// Calendar month through `today`, with empty dates included so the month view keeps its shape.
    public func month(
        through today: DayKey,
        including todaySummary: DaySummary? = nil,
        calendar: Calendar = .current
    ) -> [DaySummary] {
        guard let date = today.startOfDay(calendar: calendar),
              let interval = calendar.dateInterval(of: .month, for: date) else { return [] }
        let first = DayKey(date: interval.start, calendar: calendar)
        var byDay = Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0) })
        if let todaySummary, todaySummary.day == today { byDay[today] = todaySummary }

        var result: [DaySummary] = []
        var cursor = first
        while cursor <= today {
            result.append(byDay[cursor] ?? DaySummary(
                day: cursor,
                activityAmount: 0,
                stepEarnedSeconds: 0,
                studyEarnedSeconds: 0,
                hasUsageData: false
            ))
            guard let next = cursor.adding(days: 1, calendar: calendar), next > cursor else { break }
            cursor = next
        }
        return result
    }

    /// Consecutive days that earned something, counting back from `today`.
    ///
    /// Today is only counted once it has earned: a streak the user has not yet extended today
    /// still stands at yesterday's number, so it never appears to break overnight.
    public func streak(endingOn today: DayKey, including todayLedger: DailyLedger? = nil, calendar: Calendar = .current) -> Int {
        var byDay = Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0) })
        if let todayLedger, todayLedger.day == today {
            byDay[today] = DaySummary(ledger: todayLedger)
        }

        var count = 0
        var offset = 0
        if byDay[today]?.didEarn != true {
            offset = 1        // yesterday still anchors the streak
        }
        while let day = today.adding(days: -offset, calendar: calendar), byDay[day]?.didEarn == true {
            count += 1
            offset += 1
            if count >= Self.maxDays + 1 { break }
        }
        return count
    }
}
