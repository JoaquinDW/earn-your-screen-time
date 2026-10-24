import EarnDomain
import SwiftUI
import WidgetKit

/// The minutes you have, and how far the next ones are — on the Home and Lock Screen.
///
/// In 1.2.2–1.3.0 almost nobody came back after the first session, and nothing outside the app
/// reminded them it existed. Screen-time apps that keep people (BePresent's streak widget, Opal's
/// focus widgets) put one number on the Home Screen every day; here that number is the balance,
/// because a balance waiting to be spent is the reason to open the app.
///
/// It is drawn as a small piece of the app rather than a system tile: the dusk illustrations
/// behind the type, the balance in Instrument Serif with its label in the italic, and progress on
/// the app's tick rule instead of a progress bar. The scene follows the state — the path while
/// there is nothing to spend, the ridge once there is, the evening chair during an unlock — the
/// same scenes those moments use inside the app.
struct EarnWalletWidget: Widget {
    static let kind = "EarnWalletWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: EarnWalletProvider()) { entry in
            EarnWalletWidgetView(entry: entry)
                .environment(\.locale, entry.locale)
                .widgetURL(URL(string: "earnyourscreentime://home"))
        }
        .configurationDisplayName("widget.displayName")
        .description("widget.description")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
        // The illustration is the background; the system's own margin would frame it in black.
        .contentMarginsDisabled()
    }
}

// MARK: - Timeline

struct EarnWalletEntry: TimelineEntry {
    let date: Date
    let isSetUp: Bool
    let availableMinutes: Int
    let earnedMinutesToday: Int
    let steps: Int
    let nextRewardTarget: Int
    let nextRewardMinutes: Int
    let stepsPerReward: Int
    let dailyGoal: Int
    let streakDays: Int
    let sessionEndsAt: Date?
    let locale: Locale

    var stepsToNextReward: Int { max(0, nextRewardTarget - steps) }

    /// How far into the current earning interval today's steps are.
    var rewardProgress: Double {
        guard stepsPerReward > 0 else { return 0 }
        let start = nextRewardTarget - stepsPerReward
        return min(1, max(0, Double(steps - start) / Double(stepsPerReward)))
    }

    var goalProgress: Double {
        guard dailyGoal > 0 else { return 0 }
        return min(1, Double(steps) / Double(dailyGoal))
    }

    var isSessionActive: Bool { sessionEndsAt.map { $0 > date } ?? false }

    /// The illustration behind the numbers, chosen by what the person can do right now.
    var sceneName: String {
        if isSessionActive { return "widget-home-evening" }
        return availableMinutes > 0 ? "widget-freedom-ridge" : "widget-earn-path"
    }

    static func load(at date: Date = Date()) -> EarnWalletEntry {
        let state = SharedStore.shared.load(now: date)
        let ledger = state.ledger
        let next = CreditEngine.nextMilestone(in: ledger)
        return EarnWalletEntry(
            date: date,
            isSetUp: state.onboardingCompleted,
            availableMinutes: ledger.wallet.availableMinutes,
            earnedMinutesToday: ledger.wallet.earnedSeconds / 60,
            steps: ledger.activityAmount,
            nextRewardTarget: next.targetAmount,
            nextRewardMinutes: next.rewardMinutes,
            stepsPerReward: ledger.rule.amountRequired,
            dailyGoal: state.dailyStepGoal,
            streakDays: state.history.streak(endingOn: ledger.day, including: ledger),
            sessionEndsAt: state.activeSession(at: date)?.endsAt,
            locale: AppLanguage.saved.locale
        )
    }

    static let placeholder = EarnWalletEntry(
        date: Date(),
        isSetUp: true,
        availableMinutes: 15,
        earnedMinutesToday: 20,
        steps: 3_320,
        nextRewardTarget: 3_500,
        nextRewardMinutes: 5,
        stepsPerReward: 500,
        dailyGoal: 4_000,
        streakDays: 3,
        sessionEndsAt: nil,
        locale: .autoupdatingCurrent
    )
}

struct EarnWalletProvider: TimelineProvider {
    func placeholder(in context: Context) -> EarnWalletEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (EarnWalletEntry) -> Void) {
        completion(context.isPreview ? .placeholder : .load())
    }

    /// The app reloads this timeline whenever the wallet changes. An active session also ends
    /// on its own, so the entry after it is scheduled for the moment it does.
    func getTimeline(in context: Context, completion: @escaping (Timeline<EarnWalletEntry>) -> Void) {
        let now = Date()
        let entry = EarnWalletEntry.load(at: now)
        var entries = [entry]
        if let endsAt = entry.sessionEndsAt, endsAt > now {
            entries.append(.load(at: endsAt.addingTimeInterval(1)))
        }
        // Steps only move when the app syncs them, but a new day resets the progress at midnight.
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(24 * 60 * 60))
        let refresh = min(midnight, now.addingTimeInterval(30 * 60))
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

// MARK: - Design

/// The night palette and the two typefaces, restated because a widget extension cannot import
/// the app's design system. Keep in step with `Night` and `Typography.swift`.
private enum WidgetPalette {
    static let cobalt = Color(red: 46 / 255, green: 92 / 255, blue: 230 / 255)
    static let cobaltText = Color(red: 110 / 255, green: 151 / 255, blue: 255 / 255)
    static let ground = Color(red: 7 / 255, green: 14 / 255, blue: 13 / 255)
    static let ink = Color(red: 236 / 255, green: 243 / 255, blue: 238 / 255)
    static let soft = Color(red: 185 / 255, green: 204 / 255, blue: 194 / 255)
    static let muted = Color(red: 147 / 255, green: 167 / 255, blue: 157 / 255)
    static let flame = Color(red: 1, green: 0.62, blue: 0.32)
}

private extension Font {
    /// Instrument Serif — every number and every headline in the app.
    static func widgetSerif(_ size: CGFloat, italic: Bool = false) -> Font {
        .custom(italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular", size: size)
    }

    /// Figtree — the running text.
    static func widgetSans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .bold, .heavy, .black: .custom("Figtree-Bold", size: size)
        case .semibold, .medium: .custom("Figtree-SemiBold", size: size)
        default: .custom("Figtree-Regular", size: size)
        }
    }
}

/// The illustration and the two washes that keep type legible over it. Separate from the
/// content because WidgetKit wants it as the container background, and the app's preview of
/// the widget, where `containerBackground` does nothing, draws it itself.
struct EarnWalletBackground: View {
    let entry: EarnWalletEntry
    var isWide = false

    var body: some View {
        ZStack {
            WidgetPalette.ground
            if isWide {
                // The scene keeps the trailing two thirds; the balance owns the leading third.
                GeometryReader { proxy in
                    Image(entry.sceneName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width * 0.68, height: proxy.size.height)
                        .clipped()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                LinearGradient(
                    stops: [
                        .init(color: WidgetPalette.ground, location: 0.36),
                        .init(color: WidgetPalette.ground.opacity(0.6), location: 0.5),
                        .init(color: .clear, location: 0.7)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                // A square crop that keeps the figure to the right of the type.
                Image(entry.sceneName + "-square")
                    .resizable()
                    .scaledToFill()
                LinearGradient(
                    stops: [
                        .init(color: WidgetPalette.ground.opacity(0.78), location: 0),
                        .init(color: WidgetPalette.ground.opacity(0.15), location: 0.5),
                        .init(color: WidgetPalette.ground.opacity(0.88), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}

/// The app's tick rule (`TickMeter`), at widget scale.
private struct WidgetTicks: View {
    let progress: Double
    var count = 24
    var height: CGFloat = 9
    var tint: Color = WidgetPalette.cobaltText
    var track: Color = WidgetPalette.ink.opacity(0.22)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(Double(index) / Double(count) < progress ? tint : track)
                    .frame(width: 1.5)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The uppercase, letter-spaced marker the app puts above every section.
private struct Eyebrow: View {
    let text: Text

    var body: some View {
        text
            .font(.widgetSans(9.5, weight: .semibold))
            .textCase(.uppercase)
            .kerning(1.6)
            .foregroundStyle(WidgetPalette.soft)
            .lineLimit(1)
    }
}

private struct StreakMark: View {
    let days: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WidgetPalette.flame)
            Text(verbatim: "\(days)")
                .font(.widgetSans(11, weight: .semibold))
                .foregroundStyle(WidgetPalette.ink)
                .monospacedDigit()
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(WidgetPalette.ground.opacity(0.55), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("widget.streak \(days)"))
    }
}

// MARK: - Views

struct EarnWalletWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    let entry: EarnWalletEntry
    /// For the app's own preview of the widget, where `widgetFamily` is not set by WidgetKit
    /// and defaults to medium.
    var family: WidgetFamily?

    private var resolvedFamily: WidgetFamily { family ?? widgetFamily }

    var body: some View {
        switch resolvedFamily {
        case .accessoryCircular:
            CircularView(entry: entry).containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            RectangularView(entry: entry).containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            InlineView(entry: entry).containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            MediumView(entry: entry)
                .containerBackground(for: .widget) { EarnWalletBackground(entry: entry, isWide: true) }
        default:
            SmallView(entry: entry)
                .containerBackground(for: .widget) { EarnWalletBackground(entry: entry) }
        }
    }
}

/// The balance and the rule to the next minutes, stacked — the whole small widget, and the
/// leading column of the medium one.
private struct BalanceColumn: View {
    let entry: EarnWalletEntry
    var showsStreak = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                if entry.isSessionActive {
                    Eyebrow(text: Text("widget.unlocked"))
                } else {
                    // The same wordmark that heads Home: the serif name, nothing else.
                    Text(verbatim: "Earnit")
                        .font(.widgetSerif(17))
                        .foregroundStyle(WidgetPalette.ink)
                }
                Spacer(minLength: 4)
                if showsStreak, entry.streakDays > 0, !entry.isSessionActive {
                    StreakMark(days: entry.streakDays)
                }
            }
            .frame(height: 20)

            if !entry.isSetUp {
                Spacer(minLength: 0)
                Text("widget.setUp")
                    .font(.widgetSerif(24))
                    .foregroundStyle(WidgetPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else if let endsAt = entry.sessionEndsAt, entry.isSessionActive {
                Text(endsAt, style: .timer)
                    .font(.widgetSerif(46))
                    .monospacedDigit()
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 4)
                Text("widget.unlockedLeft")
                    .font(.widgetSerif(16, italic: true))
                    .foregroundStyle(WidgetPalette.soft)
                    .lineLimit(2)
                    .padding(.top, -6)
                Spacer(minLength: 0)
            } else {
                // Home's balance, scaled down: the serif numeral with "min" set small beside it,
                // and what the minutes are for underneath.
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: "\(entry.availableMinutes)")
                        .font(.widgetSerif(60))
                        .foregroundStyle(WidgetPalette.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(verbatim: "min")
                        .font(.widgetSans(14, weight: .medium))
                        .foregroundStyle(WidgetPalette.soft)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, 2)
                Text(entry.availableMinutes > 0 ? "widget.readyForApps" : "widget.walkToEarn")
                    .font(.widgetSerif(16, italic: true))
                    .foregroundStyle(WidgetPalette.soft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, -8)
                Spacer(minLength: 6)
                WidgetTicks(progress: entry.rewardProgress)
                Text("widget.stepsToReward \(entry.stepsToNextReward.formatted()) \(entry.nextRewardMinutes)")
                    .font(.widgetSans(10.5, weight: .semibold))
                    .foregroundStyle(WidgetPalette.soft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 5)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SmallView: View {
    let entry: EarnWalletEntry

    var body: some View {
        BalanceColumn(entry: entry)
            .padding(14)
    }
}

/// The balance on the left over the darkened edge of the scene; the scene itself on the right,
/// carrying today's steps toward the goal and the streak as two quiet labels.
private struct MediumView: View {
    let entry: EarnWalletEntry

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            BalanceColumn(entry: entry, showsStreak: false)
                .frame(width: 140)
            Spacer(minLength: 0)
            if entry.isSetUp {
                VStack(alignment: .trailing, spacing: 0) {
                    if entry.streakDays > 0 {
                        StreakMark(days: entry.streakDays)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("widget.stepsOfGoal \(entry.steps.formatted()) \(entry.dailyGoal.formatted())")
                            .font(.widgetSans(10.5, weight: .semibold))
                            .foregroundStyle(WidgetPalette.ink)
                            .lineLimit(1)
                        WidgetTicks(progress: entry.goalProgress, count: 18, height: 7)
                            .frame(width: 92)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(WidgetPalette.ground.opacity(0.55), in: .rect(cornerRadius: 10))
                }
            }
        }
        .padding(14)
    }
}

// MARK: Lock Screen

private struct CircularView: View {
    let entry: EarnWalletEntry

    var body: some View {
        if let endsAt = entry.sessionEndsAt, entry.isSessionActive {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "lock.open.fill").font(.system(size: 10, weight: .bold))
                    Text(endsAt, style: .timer)
                        .font(.widgetSans(12, weight: .bold))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                }
            }
        } else {
            Gauge(value: entry.rewardProgress) {
                Image(systemName: "figure.walk")
            } currentValueLabel: {
                Text(verbatim: "\(entry.availableMinutes)")
                    .font(.widgetSerif(24))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityLabel(Text("widget.minutesReadyCount \(entry.availableMinutes)"))
        }
    }
}

private struct RectangularView: View {
    let entry: EarnWalletEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let endsAt = entry.sessionEndsAt, entry.isSessionActive {
                Label("widget.unlocked", systemImage: "lock.open.fill")
                    .font(.widgetSans(12, weight: .semibold))
                Text(endsAt, style: .timer)
                    .font(.widgetSerif(26))
                    .monospacedDigit()
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: "\(entry.availableMinutes)")
                        .font(.widgetSerif(28))
                        .widgetAccentable()
                    Text(verbatim: "min")
                        .font(.widgetSans(13, weight: .semibold))
                    Text(entry.availableMinutes > 0 ? "widget.readyForApps" : "widget.walkToEarn")
                        .font(.widgetSerif(15, italic: true))
                }
                WidgetTicks(progress: entry.rewardProgress, count: 30, height: 7, tint: .primary, track: .primary.opacity(0.3))
                    .widgetAccentable()
                Text("widget.stepsToReward \(entry.stepsToNextReward.formatted()) \(entry.nextRewardMinutes)")
                    .font(.widgetSans(11, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

private struct InlineView: View {
    let entry: EarnWalletEntry

    var body: some View {
        if let endsAt = entry.sessionEndsAt, entry.isSessionActive {
            Label { Text(endsAt, style: .timer) } icon: { Image(systemName: "lock.open.fill") }
        } else {
            Label("widget.minutesReadyCount \(entry.availableMinutes)", systemImage: "hourglass")
        }
    }
}

#Preview("Small", as: .systemSmall) {
    EarnWalletWidget()
} timeline: {
    EarnWalletEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    EarnWalletWidget()
} timeline: {
    EarnWalletEntry.placeholder
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    EarnWalletWidget()
} timeline: {
    EarnWalletEntry.placeholder
}
