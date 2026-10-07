import SwiftUI
import UIKit

/// App-wide presentation for completed domain transitions. Earned time gets an authored
/// celebration; operational state changes stay compact so their urgency remains proportional.
struct EarnFeedbackOverlay: View {
    let feedback: EarnPresentationFeedback
    let onFinished: () -> Void
    var onImpact: () -> Void = {}
    var reduceMotionOverride: Bool? = nil
    var shouldAnnounce: () -> Bool = { true }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        Group {
            if let minutes = feedback.event.earnedMinutes {
                EarnedTimeCelebration(
                    event: feedback.event,
                    minutes: minutes,
                    balance: feedback.earnedTimeBalance,
                    announcement: announcement,
                    reduceMotion: reduceMotion,
                    voiceOverEnabled: voiceOverEnabled,
                    shouldAnnounce: shouldAnnounce,
                    onImpact: onImpact,
                    onFinished: onFinished
                )
            } else if let title {
                StatusReceipt(
                    title: title,
                    symbol: symbol,
                    announcement: announcement,
                    reduceMotion: reduceMotion,
                    voiceOverEnabled: voiceOverEnabled,
                    shouldAnnounce: shouldAnnounce,
                    onImpact: onImpact,
                    onFinished: onFinished
                )
            }
        }
        .allowsHitTesting(false)
    }

    private var title: LocalizedStringKey? {
        switch feedback.event {
        case let .screenTimeEarned(minutes): "feedback.earned \(minutes)"
        case let .firstRewardEarned(minutes): "feedback.firstReward \(minutes)"
        case let .dailyGoalCompleted(minutes): "feedback.goalComplete \(minutes)"
        case .appUnlocked: "feedback.appsUnlocked"
        case .appLocked: "feedback.appsLocked"
        case .balanceExpired: "feedback.balanceEmpty"
        case let .timeSaved(seconds):
            seconds < 60 ? "feedback.timeSavedLessThanMinute" : "feedback.timeSaved \(seconds / 60)"
        case .walletFull: "feedback.walletFull"
        case let .streakUpdated(days): "feedback.streak \(days)"
        case .error: nil
        }
    }

    private var symbol: String {
        switch feedback.event {
        case .screenTimeEarned, .firstRewardEarned: "plus"
        case .dailyGoalCompleted: "checkmark"
        case .appUnlocked: "lock.open.fill"
        case .appLocked, .balanceExpired: "lock.fill"
        case .timeSaved: "arrow.uturn.backward"
        case .walletFull: "tray.full.fill"
        case .streakUpdated: "flame.fill"
        case .error: "exclamationmark"
        }
    }

    private var announcement: String? {
        switch feedback.event {
        case let .screenTimeEarned(minutes): String(localized: "feedback.earned \(minutes)")
        case let .firstRewardEarned(minutes): String(localized: "feedback.firstReward \(minutes)")
        case let .dailyGoalCompleted(minutes): String(localized: "feedback.goalComplete \(minutes)")
        case .appUnlocked: String(localized: "feedback.appsUnlocked")
        case .appLocked: String(localized: "feedback.appsLocked")
        case .balanceExpired: String(localized: "feedback.balanceEmpty")
        case let .timeSaved(seconds):
            seconds < 60
                ? String(localized: "feedback.timeSavedLessThanMinute")
                : String(localized: "feedback.timeSaved \(seconds / 60)")
        case .walletFull: String(localized: "feedback.walletFull")
        case let .streakUpdated(days): String(localized: "feedback.streak \(days)")
        case .error: nil
        }
    }
}

private struct EarnedTimeCelebration: View {
    let event: EarnPresentationEvent
    let minutes: Int
    let balance: EarnedTimeBalance?
    let announcement: String?
    let reduceMotion: Bool
    let voiceOverEnabled: Bool
    let shouldAnnounce: () -> Bool
    let onImpact: () -> Void
    let onFinished: () -> Void

    @State private var phase = Phase.hidden

    private enum Phase {
        case hidden
        case horizon
        case formed
        case credited
        case exiting
    }

    private var isElevatedReward: Bool {
        switch event {
        case .firstRewardEarned, .dailyGoalCompleted: true
        default: false
        }
    }

    private var momentTitle: LocalizedStringKey {
        switch event {
        case .firstRewardEarned: "feedback.celebration.first"
        case .dailyGoalCompleted: "feedback.celebration.goal"
        default: "feedback.celebration.earned"
        }
    }

    private var isVisible: Bool { phase != .hidden && phase != .exiting }
    private var hasHorizon: Bool { phase != .hidden && phase != .exiting }
    private var hasFormed: Bool { phase == .formed || phase == .credited }
    private var isCredited: Bool { phase == .credited }
    private var markCount: Int { min(max(minutes, 1), 15) }

    var body: some View {
        ZStack {
            Night.ground
                .opacity(isVisible ? (isElevatedReward ? 0.98 : 0.96) : 0)
                .ignoresSafeArea()

            VStack(spacing: Theme.Space.l) {
                title
                timePulse
                balanceConfirmation
            }
            .padding(.horizontal, Theme.Space.gutter)
            .frame(maxWidth: 430)
            .opacity(isVisible ? 1 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(announcement ?? ""))
        .task { await animatePresentation() }
    }

    private var title: some View {
        HStack(spacing: Theme.Space.s) {
            if case .dailyGoalCompleted = event {
                Image(systemName: "checkmark")
                    .font(.sans(11, weight: .bold, relativeTo: .caption))
                    .accessibilityHidden(true)
            }
            Text(momentTitle)
        }
        .eyebrowStyle(Night.cobaltText)
        .opacity(hasHorizon ? 1 : 0)
        .offset(y: reduceMotion || hasHorizon ? 0 : Theme.Space.s)
    }

    private var timePulse: some View {
        ZStack {
            Rectangle()
                .fill(Night.cobalt.opacity(isCredited ? 0.45 : 0.9))
                .frame(height: 1)
                .scaleEffect(x: hasHorizon ? (isCredited ? 0.62 : 1) : 0, anchor: .center)
                .offset(y: 40)

            HStack(spacing: markCount > 10 ? Theme.Space.xs : Theme.Space.s) {
                ForEach(0..<markCount, id: \.self) { index in
                    Capsule()
                        .fill(Night.cobaltText)
                        .frame(width: 2, height: index.isMultiple(of: 5) ? 18 : 10)
                        .scaleEffect(y: hasFormed && !reduceMotion ? 1 : 0.2, anchor: .bottom)
                        .offset(y: hasFormed && !reduceMotion ? -32 : 0)
                        .opacity(hasFormed && !isCredited && !reduceMotion ? 0.9 : 0)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: Theme.Space.s) {
                Text(verbatim: "+\(minutes)")
                    .font(.serif(82))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("home.unit.minutes")
                    .font(.sans(18, weight: .medium, relativeTo: .title3))
                    .textCase(.lowercase)
                    .foregroundStyle(Night.textSoft)
            }
            .foregroundStyle(Night.text)
            .opacity(hasFormed ? 1 : 0)
            .scaleEffect(reduceMotion || hasFormed ? 1 : 0.94)
            .offset(y: reduceMotion || hasFormed ? -4 : Theme.Space.m)
        }
        .frame(height: 142)
        .shadow(
            color: Night.cobalt.opacity(hasFormed && !reduceMotion ? 0.22 : 0),
            radius: Theme.Space.l,
            y: Theme.Space.s
        )
    }

    @ViewBuilder
    private var balanceConfirmation: some View {
        if let balance {
            Text("feedback.celebration.balance \(balance.afterMinutes)")
                .font(.sans(15, weight: .medium))
                .foregroundStyle(Night.textSoft)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(balance.afterMinutes)))
                .opacity(isCredited ? 1 : 0)
                .offset(y: reduceMotion || isCredited ? 0 : Theme.Space.s)
        } else {
            Text("feedback.celebration.added")
                .font(.sans(15, weight: .medium))
                .foregroundStyle(Night.textSoft)
                .opacity(isCredited ? 1 : 0)
        }
    }

    @MainActor
    private func animatePresentation() async {
        phase = .hidden
        await Task.yield()
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: reduceMotion ? EarnMotion.quick : EarnMotion.standard)) {
            phase = .horizon
        }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 180 : 240))
        guard !Task.isCancelled else { return }

        withAnimation(reduceMotion ? .easeOut(duration: EarnMotion.quick) : .snappy(duration: EarnMotion.reward)) {
            phase = .formed
        }
        onImpact()
        if voiceOverEnabled, shouldAnnounce(), let announcement {
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 220 : 480))
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: reduceMotion ? EarnMotion.quick : EarnMotion.standard)) {
            phase = .credited
        }
        try? await Task.sleep(for: .milliseconds(voiceOverEnabled ? 2_200 : isElevatedReward ? 1_150 : 850))
        guard !Task.isCancelled else { return }

        withAnimation(.easeIn(duration: reduceMotion ? 0.18 : EarnMotion.standard)) {
            phase = .exiting
        }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 180 : 320))
        guard !Task.isCancelled else { return }
        onFinished()
    }
}

private struct StatusReceipt: View {
    let title: LocalizedStringKey
    let symbol: String
    let announcement: String?
    let reduceMotion: Bool
    let voiceOverEnabled: Bool
    let shouldAnnounce: () -> Bool
    let onImpact: () -> Void
    let onFinished: () -> Void

    @State private var phase = Phase.hidden

    private enum Phase {
        case hidden
        case arrived
        case settled
        case exiting
    }

    var body: some View {
        VStack {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: symbol)
                    .font(.sans(15, weight: .bold))
                    .foregroundStyle(Night.cobaltText)
                    .frame(width: 40, height: 40)
                    .background(Night.cobaltWash, in: .rect(cornerRadius: 12))
                    .scaleEffect(symbolScale)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.sans(14, weight: .bold))
                    .foregroundStyle(Night.text)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: 330)
            .background(Night.panel.opacity(0.96), in: .rect(cornerRadius: Theme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Night.line, lineWidth: 1)
            }
            .opacity(opacity)
            .scaleEffect(scale)
            .offset(y: offset)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isStaticText)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.s)
        .task { await animatePresentation() }
    }

    private var opacity: Double {
        switch phase {
        case .hidden, .exiting: 0
        case .arrived, .settled: 1
        }
    }

    private var scale: CGFloat {
        guard !reduceMotion else { return 1 }
        return switch phase {
        case .hidden: 0.97
        case .arrived: 1.01
        case .settled: 1
        case .exiting: 0.99
        }
    }

    private var symbolScale: CGFloat {
        guard !reduceMotion else { return 1 }
        return phase == .arrived ? 1.08 : 1
    }

    private var offset: CGFloat {
        guard !reduceMotion else { return 0 }
        return switch phase {
        case .hidden: -12
        case .arrived, .settled: 0
        case .exiting: -8
        }
    }

    @MainActor
    private func animatePresentation() async {
        phase = .hidden
        await Task.yield()
        guard !Task.isCancelled else { return }

        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .snappy(duration: EarnMotion.standard)) {
            phase = .arrived
        }
        onImpact()
        if voiceOverEnabled, shouldAnnounce(), let announcement {
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 180 : 320))
        guard !Task.isCancelled else { return }

        withAnimation(reduceMotion ? nil : .easeOut(duration: EarnMotion.quick)) {
            phase = .settled
        }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 1_980 : voiceOverEnabled ? 2_300 : 1_050))
        guard !Task.isCancelled else { return }

        withAnimation(.easeIn(duration: reduceMotion ? 0.18 : EarnMotion.standard)) {
            phase = .exiting
        }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 180 : 320))
        guard !Task.isCancelled else { return }
        onFinished()
    }
}

#Preview("Earned time pulse") {
    ZStack {
        SceneBackdrop(scene: .homeEvening).ignoresSafeArea()
        EarnFeedbackOverlay(
            feedback: EarnPresentationFeedback(
                event: .screenTimeEarned(minutes: 5),
                earnedTimeBalance: EarnedTimeBalance(beforeMinutes: 10, afterMinutes: 15)
            ),
            onFinished: {}
        )
    }
}

#Preview("Daily goal - Reduce Motion") {
    ZStack {
        Night.ground.ignoresSafeArea()
        EarnFeedbackOverlay(
            feedback: EarnPresentationFeedback(
                event: .dailyGoalCompleted(minutes: 15),
                earnedTimeBalance: EarnedTimeBalance(beforeMinutes: 20, afterMinutes: 35)
            ),
            onFinished: {},
            reduceMotionOverride: true
        )
    }
}

#Preview("Operational receipt") {
    ZStack {
        Night.ground.ignoresSafeArea()
        EarnFeedbackOverlay(
            feedback: EarnPresentationFeedback(event: .appUnlocked),
            onFinished: {}
        )
    }
}
