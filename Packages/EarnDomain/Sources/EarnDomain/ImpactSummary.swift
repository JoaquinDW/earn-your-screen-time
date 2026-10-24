import Foundation

/// What a stretch of days amounted to, told as an outcome rather than a ledger.
///
/// Progress already shows minutes earned against minutes used. This adds the two numbers that
/// say whether the app is working: the opens the person skipped at a shield, and how much less
/// time went to the protected apps than the daily scrolling they reported in onboarding.
public struct ImpactSummary: Equatable, Sendable {
    public let activityAmount: Int
    public let earnedSeconds: Int
    public let consumedSeconds: Int
    public let skippedOpens: Int
    /// Days whose usage Earnit actually recorded. Gaps and pre-history days say nothing.
    public let trackedDays: Int
    /// Reported scrolling minus recorded use, over the tracked days. `nil` when there is no
    /// baseline to compare with: no onboarding answer, or one whose lower bound is zero.
    public let reclaimedSeconds: Int?

    /// - Parameters:
    ///   - today: The day still in progress, if `summaries` contains it.
    ///   - todayElapsedFraction: How much of today's baseline has had the chance to happen
    ///     (0…1). Claiming a whole day's scrolling as reclaimed at 9 a.m. would be a lie.
    public init(
        summaries: [DaySummary],
        skippedOpens: Int,
        scrolling: OnboardingProfile.ScrollingBand?,
        today: DayKey? = nil,
        todayElapsedFraction: Double = 1
    ) {
        let tracked = summaries.filter(\.hasUsageData)
        activityAmount = summaries.reduce(0) { $0 + $1.activityAmount }
        earnedSeconds = summaries.reduce(0) { $0 + $1.earnedSeconds }
        consumedSeconds = summaries.reduce(0) { $0 + $1.consumedSeconds }
        self.skippedOpens = max(0, skippedOpens)
        trackedDays = tracked.count

        guard let scrolling, !tracked.isEmpty else {
            reclaimedSeconds = nil
            return
        }
        let baselineSeconds = Self.conservativeDailyBaselineSeconds(for: scrolling)
        guard baselineSeconds > 0 else {
            reclaimedSeconds = nil
            return
        }
        let fraction = min(1, max(0, todayElapsedFraction))
        let expected = tracked.reduce(0.0) { total, summary in
            total + Double(baselineSeconds) * (summary.day == today ? fraction : 1)
        }
        let used = tracked.reduce(0) { $0 + $1.consumedSeconds }
        reclaimedSeconds = max(0, Int(expected.rounded()) - used)
    }

    /// The bottom of the band the person picked. Low on purpose: the claim has to hold for
    /// everyone who picked it, and only the apps they protected are counted against it.
    public static func conservativeDailyBaselineSeconds(
        for scrolling: OnboardingProfile.ScrollingBand
    ) -> Int {
        Int(ScreenTimeCostRange(scrollingBand: scrolling).weeklyHours.lowerBound / 7 * 3_600)
    }

    /// The share of a waking day (7:00–23:00) that has passed at `date`.
    public static func wakingDayFraction(at date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hours = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
        return min(1, max(0, (hours - 7) / 16))
    }

    public var earnedMinutes: Int { earnedSeconds / 60 }
    public var consumedMinutes: Int { consumedSeconds / 60 }
    public var reclaimedMinutes: Int? { reclaimedSeconds.map { $0 / 60 } }

    /// Whether there is anything worth showing or sharing yet.
    public var hasContent: Bool {
        earnedSeconds > 0 || skippedOpens > 0 || (reclaimedSeconds ?? 0) >= 60
    }
}
