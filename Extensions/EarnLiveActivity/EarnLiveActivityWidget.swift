import ActivityKit
import SwiftUI
import WidgetKit

/// The v6 night palette, restated here because a widget extension cannot import the app's
/// design system. Keep in step with `Night` in `App/DesignSystem/NightTheme.swift`.
private enum LiveActivityPalette {
    /// `Night.cobalt` — #2E5CE6.
    static let cobalt = Color(red: 46 / 255, green: 92 / 255, blue: 230 / 255)
    /// `Night.cobaltText` — #6E97FF. Cobalt at text weight on a dark card.
    static let cobaltText = Color(red: 110 / 255, green: 151 / 255, blue: 255 / 255)
    /// `Night.ground` — #070E0D.
    static let ground = Color(red: 7 / 255, green: 14 / 255, blue: 13 / 255)
    /// `Night.text` — #ECF3EE.
    static let ink = Color(red: 236 / 255, green: 243 / 255, blue: 238 / 255)
    /// `Night.textMuted` — #93A79D.
    static let muted = Color(red: 147 / 255, green: 167 / 255, blue: 157 / 255)
}

struct EarnLiveActivityWidget: Widget {
    private let deepLink = URL(string: "earnyourscreentime://home")

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EarnActivityAttributes.self) { context in
            EarnLockScreenView(context: context)
                .environment(\.locale, Locale(identifier: context.state.localeIdentifier))
                .activityBackgroundTint(LiveActivityPalette.ground)
                .activitySystemActionForegroundColor(LiveActivityPalette.cobaltText)
                .widgetURL(deepLink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedTitle(context: context)
                        .environment(\.locale, Locale(identifier: context.state.localeIdentifier))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedMetric(context: context)
                        .environment(\.locale, Locale(identifier: context.state.localeIdentifier))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedDetail(context: context)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                        .environment(\.locale, Locale(identifier: context.state.localeIdentifier))
                }
            } compactLeading: {
                CompactLeading(context: context)
                    .environment(\.locale, Locale(identifier: context.state.localeIdentifier))
            } compactTrailing: {
                CompactTrailing(context: context)
                    .environment(\.locale, Locale(identifier: context.state.localeIdentifier))
            } minimal: {
                MinimalPresentation(context: context)
                    .environment(\.locale, Locale(identifier: context.state.localeIdentifier))
            }
            .keylineTint(LiveActivityPalette.cobalt)
            .widgetURL(deepLink)
        }
    }
}

private struct EarnLockScreenView: View {
    let context: ActivityViewContext<EarnActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("liveActivity.title", systemImage: "hourglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LiveActivityPalette.cobaltText)

            if effectivePresentation(context) == .normal {
                ActiveSessionContent(context: context, onDarkBackground: false)
            } else {
                TemporaryStatusView(context: context, onDarkBackground: false)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .foregroundStyle(LiveActivityPalette.ink)
        .accessibilityElement(children: .combine)
    }
}

private struct ActiveSessionContent: View {
    let context: ActivityViewContext<EarnActivityAttributes>
    let onDarkBackground: Bool

    private var primary: Color { onDarkBackground ? .white : LiveActivityPalette.cobaltText }
    private var secondary: Color { onDarkBackground ? .white.opacity(0.62) : LiveActivityPalette.muted }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let endsAt = context.state.activeSessionEndsAt {
                Text(endsAt, style: .timer)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(primary)
                    .contentTransition(.numericText(countsDown: true))
            }
            Text("liveActivity.sessionRemaining")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(secondary)
            Text("liveActivity.saved \(context.state.availableMinutes)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(secondary)
        }
    }
}

private struct TemporaryStatusView: View {
    let context: ActivityViewContext<EarnActivityAttributes>
    let onDarkBackground: Bool

    private var primary: Color { onDarkBackground ? .white : LiveActivityPalette.cobaltText }
    private var secondary: Color { onDarkBackground ? .white.opacity(0.68) : LiveActivityPalette.muted }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch effectivePresentation(context) {
            case let .earned(minutes):
                Text("liveActivity.earned \(minutes)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(primary)
                Text("liveActivity.available \(context.state.availableMinutes)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secondary)
            case .unlocked:
                Text("liveActivity.unlocked")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(primary)
                if let endsAt = context.state.activeSessionEndsAt {
                    Text(endsAt, style: .timer)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(secondary)
                }
            case .goalCompleted:
                Text("liveActivity.goalComplete")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(primary)
                Text("liveActivity.goalSummary \(context.state.dailyGoalTarget) \(context.state.earnedMinutesToday)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secondary)
            case .balanceExpired:
                Text("liveActivity.timesUp")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(primary)
                if context.state.availableMinutes > 0 {
                    Text("liveActivity.available \(context.state.availableMinutes)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(secondary)
                } else {
                    Text("liveActivity.walkToEarn")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(secondary)
                }
            case .normal:
                EmptyView()
            }
        }
        .contentTransition(.opacity)
    }
}

private struct ExpandedTitle: View {
    let context: ActivityViewContext<EarnActivityAttributes>

    var body: some View {
        Label("liveActivity.title", systemImage: presentationSymbol(effectivePresentation(context)))
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(LiveActivityPalette.cobalt)
    }
}

private struct ExpandedMetric: View {
    let context: ActivityViewContext<EarnActivityAttributes>

    var body: some View {
        Group {
            switch effectivePresentation(context) {
            case let .earned(minutes):
                Text("+\(minutes)m")
            case .goalCompleted:
                Image(systemName: "checkmark.circle.fill")
            case .unlocked:
                Image(systemName: "lock.open.fill")
            case .balanceExpired:
                Image(systemName: "hourglass.bottomhalf.filled")
            case .normal:
                if let endsAt = context.state.activeSessionEndsAt {
                    Text(endsAt, style: .timer)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                }
            }
        }
        .font(.system(size: 22, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .accessibilityLabel(presentationAccessibilityLabel(context))
    }
}

private struct ExpandedDetail: View {
    let context: ActivityViewContext<EarnActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if effectivePresentation(context) == .normal {
                Text("liveActivity.saved \(context.state.availableMinutes)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
            } else {
                TemporaryStatusView(context: context, onDarkBackground: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .allowsTightening(true)
    }
}

private struct CompactLeading: View {
    let context: ActivityViewContext<EarnActivityAttributes>

    var body: some View {
        Image(systemName: presentationSymbol(effectivePresentation(context)))
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .foregroundStyle(LiveActivityPalette.cobalt)
        .accessibilityLabel(presentationAccessibilityLabel(context))
    }
}

private struct CompactTrailing: View {
    let context: ActivityViewContext<EarnActivityAttributes>

    var body: some View {
        Group {
            if let endsAt = context.state.activeSessionEndsAt,
               effectivePresentation(context) == .normal || effectivePresentation(context) == .unlocked {
                Text(endsAt, style: .timer)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
            } else {
                Image(systemName: presentationSymbol(effectivePresentation(context)))
            }
        }
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .frame(width: 50, alignment: .trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityLabel(presentationAccessibilityLabel(context))
    }
}

private struct MinimalPresentation: View {
    let context: ActivityViewContext<EarnActivityAttributes>

    var body: some View {
        Image(systemName: presentationSymbol(effectivePresentation(context)))
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(LiveActivityPalette.cobalt)
        .accessibilityLabel(presentationAccessibilityLabel(context))
    }
}

private func effectivePresentation(
    _ context: ActivityViewContext<EarnActivityAttributes>
) -> EarnActivityAttributes.ContentState.PresentationState {
    if context.isStale,
       context.state.presentation == .normal,
       context.state.activeSessionEndsAt != nil {
        return .balanceExpired
    }
    return context.state.presentation
}

private func presentationSymbol(
    _ presentation: EarnActivityAttributes.ContentState.PresentationState
) -> String {
    switch presentation {
    case .earned, .goalCompleted: "checkmark.circle.fill"
    case .unlocked: "lock.open.fill"
    case .balanceExpired: "hourglass.bottomhalf.filled"
    case .normal: "hourglass"
    }
}

private func presentationAccessibilityLabel(
    _ context: ActivityViewContext<EarnActivityAttributes>
) -> Text {
    switch effectivePresentation(context) {
    case let .earned(minutes): Text("liveActivity.earned \(minutes)")
    case .goalCompleted: Text("liveActivity.goalComplete")
    case .unlocked: Text("liveActivity.unlocked")
    case .balanceExpired: Text("liveActivity.timesUp")
    case .normal:
        if let endsAt = context.state.activeSessionEndsAt {
            Text("liveActivity.sessionEnds \(endsAt)")
        } else {
            Text("liveActivity.title")
        }
    }
}

private let earnedPreviewState = EarnActivityAttributes.ContentState(
    dayKey: "2026-08-24",
    steps: 5_000,
    nextMilestoneTarget: 6_000,
    dailyGoalTarget: 8_000,
    availableMinutes: 20,
    earnedMinutesToday: 25,
    nextRewardMinutes: 5,
    milestoneStepAmount: 1_000,
    activeSessionEndsAt: nil,
    localeIdentifier: "en",
    presentation: .earned(minutes: 5)
)

private let goalPreviewState = EarnActivityAttributes.ContentState(
    dayKey: "2026-08-24",
    steps: 8_000,
    nextMilestoneTarget: 9_000,
    dailyGoalTarget: 8_000,
    availableMinutes: 40,
    earnedMinutesToday: 40,
    nextRewardMinutes: 5,
    milestoneStepAmount: 1_000,
    activeSessionEndsAt: nil,
    localeIdentifier: "en",
    presentation: .goalCompleted
)

private let activePreviewState = EarnActivityAttributes.ContentState(
    dayKey: "2026-08-24",
    steps: 5_580,
    nextMilestoneTarget: 6_000,
    dailyGoalTarget: 8_000,
    availableMinutes: 5,
    earnedMinutesToday: 20,
    nextRewardMinutes: 5,
    milestoneStepAmount: 1_000,
    activeSessionEndsAt: .now.addingTimeInterval(8 * 60),
    localeIdentifier: "en",
    presentation: .normal
)

private let expiredPreviewState = EarnActivityAttributes.ContentState(
    dayKey: "2026-08-24",
    steps: 5_580,
    nextMilestoneTarget: 6_000,
    dailyGoalTarget: 8_000,
    availableMinutes: 0,
    earnedMinutesToday: 15,
    nextRewardMinutes: 5,
    milestoneStepAmount: 1_000,
    activeSessionEndsAt: nil,
    localeIdentifier: "en",
    presentation: .balanceExpired
)

private let unlockedPreviewState = EarnActivityAttributes.ContentState(
    dayKey: "2026-08-24",
    steps: 5_580,
    nextMilestoneTarget: 6_000,
    dailyGoalTarget: 8_000,
    availableMinutes: 5,
    earnedMinutesToday: 20,
    nextRewardMinutes: 5,
    milestoneStepAmount: 1_000,
    activeSessionEndsAt: .now.addingTimeInterval(8 * 60),
    localeIdentifier: "es",
    presentation: .unlocked
)

#Preview("Lock Screen Events", as: .content, using: EarnActivityAttributes()) {
    EarnLiveActivityWidget()
} contentStates: {
    earnedPreviewState
    goalPreviewState
    expiredPreviewState
}

#Preview("Active Session", as: .dynamicIsland(.compact), using: EarnActivityAttributes()) {
    EarnLiveActivityWidget()
} contentStates: {
    activePreviewState
}

#Preview("Compact States", as: .dynamicIsland(.compact), using: EarnActivityAttributes()) {
    EarnLiveActivityWidget()
} contentStates: {
    earnedPreviewState
    unlockedPreviewState
    expiredPreviewState
}

#Preview("Active Session Expanded", as: .dynamicIsland(.expanded), using: EarnActivityAttributes()) {
    EarnLiveActivityWidget()
} contentStates: {
    activePreviewState
}

#Preview("Event Expanded", as: .dynamicIsland(.expanded), using: EarnActivityAttributes()) {
    EarnLiveActivityWidget()
} contentStates: {
    earnedPreviewState
    goalPreviewState
    expiredPreviewState
}
