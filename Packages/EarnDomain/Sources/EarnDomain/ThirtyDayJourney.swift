import Foundation

/// Compact persisted progress through a fixed 30-day commitment.
public struct ThirtyDayJourney: Codable, Equatable, Sendable {
    public static let durationDays = 30

    public let startDay: DayKey
    public let dailyGoal: Int
    public let target: Int
    public private(set) var cumulativeSteps: Int
    public private(set) var earnedSeconds: Int
    public private(set) var activeDays: Int
    public private(set) var goalHitDays: Int
    public private(set) var finalizedResult: FinalizedResult?
    public var completionAcknowledged: Bool
    private var incorporatedDays: Set<DayKey>

    public struct FinalizedResult: Codable, Equatable, Sendable {
        public let cumulativeSteps: Int
        public let earnedSeconds: Int
        public let activeDays: Int
        public let goalHitDays: Int
        public let reachedTarget: Bool
    }

    public struct Progress: Equatable, Sendable {
        public let cumulativeSteps: Int
        public let earnedSeconds: Int
        public let activeDays: Int
        public let goalHitDays: Int
        public let fraction: Double
    }

    public init(startDay: DayKey, dailyGoal: Int, target: Int? = nil) {
        self.startDay = startDay
        self.dailyGoal = max(0, dailyGoal)
        self.target = max(0, target ?? max(0, dailyGoal) * Self.durationDays)
        cumulativeSteps = 0
        earnedSeconds = 0
        activeDays = 0
        goalHitDays = 0
        finalizedResult = nil
        completionAcknowledged = false
        incorporatedDays = []
    }

    /// Incorporates an in-range finished day once and returns a new value.
    public func incorporating(_ summary: DaySummary, calendar: Calendar = .current) -> Self {
        guard finalizedResult == nil,
              contains(summary.day, calendar: calendar),
              !incorporatedDays.contains(summary.day)
        else { return self }

        var copy = self
        copy.incorporatedDays.insert(summary.day)
        copy.cumulativeSteps += summary.activityAmount
        copy.earnedSeconds += summary.stepEarnedSeconds
        if summary.activityAmount > 0 { copy.activeDays += 1 }
        if summary.activityAmount >= dailyGoal { copy.goalHitDays += 1 }
        return copy
    }

    /// Freezes the result once the 30-day window has elapsed. Calling it again is idempotent.
    public func finalizing(asOf day: DayKey, calendar: Calendar = .current) -> Self {
        guard let endDay = startDay.adding(days: Self.durationDays - 1, calendar: calendar),
              finalizedResult == nil,
              day > endDay else {
            return self
        }
        var copy = self
        copy.finalizedResult = FinalizedResult(
            cumulativeSteps: cumulativeSteps,
            earnedSeconds: earnedSeconds,
            activeDays: activeDays,
            goalHitDays: goalHitDays,
            reachedTarget: cumulativeSteps >= target
        )
        return copy
    }

    public func acknowledgingCompletion() -> Self {
        guard finalizedResult != nil else { return self }
        var copy = self
        copy.completionAcknowledged = true
        return copy
    }

    /// One-based while underway, zero before the start, and capped at 30.
    public func elapsedDay(asOf day: DayKey, calendar: Calendar = .current) -> Int {
        guard let start = startDay.startOfDay(calendar: calendar),
              let current = day.startOfDay(calendar: calendar),
              let difference = calendar.dateComponents([.day], from: start, to: current).day
        else { return 0 }
        return min(Self.durationDays, max(0, difference + 1))
    }

    public var progress: Double {
        guard target > 0 else { return finalizedResult == nil ? 0 : 1 }
        return min(1, Double(cumulativeSteps) / Double(target))
    }

    /// Display totals can include today's unfinished ledger without persisting or double counting it.
    public func progress(includingToday summary: DaySummary?) -> Progress {
        let include = summary.map { contains($0.day) && !incorporatedDays.contains($0.day) } == true
        let steps = cumulativeSteps + (include ? summary?.activityAmount ?? 0 : 0)
        let seconds = earnedSeconds + (include ? summary?.stepEarnedSeconds ?? 0 : 0)
        let displayedActiveDays = activeDays + (include && (summary?.activityAmount ?? 0) > 0 ? 1 : 0)
        let displayedGoalDays = goalHitDays + (include && (summary?.activityAmount ?? 0) >= dailyGoal ? 1 : 0)
        let fraction = target > 0 ? min(1, Double(steps) / Double(target)) : 0
        return Progress(
            cumulativeSteps: steps,
            earnedSeconds: seconds,
            activeDays: displayedActiveDays,
            goalHitDays: displayedGoalDays,
            fraction: fraction
        )
    }

    private func contains(_ day: DayKey, calendar: Calendar = .current) -> Bool {
        guard let end = startDay.adding(days: Self.durationDays - 1, calendar: calendar) else { return false }
        return day >= startDay && day <= end
    }

    private enum CodingKeys: String, CodingKey {
        case startDay, dailyGoal, target, cumulativeSteps, earnedSeconds, activeDays, goalHitDays
        case finalizedResult, completionAcknowledged, incorporatedDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startDay = try container.decode(DayKey.self, forKey: .startDay)
        dailyGoal = max(0, try container.decode(Int.self, forKey: .dailyGoal))
        target = max(0, try container.decodeIfPresent(Int.self, forKey: .target) ?? dailyGoal * Self.durationDays)
        cumulativeSteps = max(0, try container.decodeIfPresent(Int.self, forKey: .cumulativeSteps) ?? 0)
        earnedSeconds = max(0, try container.decodeIfPresent(Int.self, forKey: .earnedSeconds) ?? 0)
        activeDays = max(0, try container.decodeIfPresent(Int.self, forKey: .activeDays) ?? 0)
        goalHitDays = max(0, try container.decodeIfPresent(Int.self, forKey: .goalHitDays) ?? 0)
        finalizedResult = try container.decodeIfPresent(FinalizedResult.self, forKey: .finalizedResult)
        completionAcknowledged = try container.decodeIfPresent(Bool.self, forKey: .completionAcknowledged) ?? false
        incorporatedDays = try container.decodeIfPresent(Set<DayKey>.self, forKey: .incorporatedDays) ?? []
    }
}
