import EarnDomain
import FamilyControls
import SwiftUI

/// Home (design v5) — the Guardian *is* the progress.
///
/// There is no ring, no percentage and no card. How much of the day has been earned is read off
/// the figure and the air around it: how low it sits, how much of the frame it takes, how far the
/// wings reach, how much cobalt has escaped. See `GuardianAtmosphere` for the layers.
///
/// The copy leads with the reward loop — *680 steps until your next 5 minutes* — because that is
/// the only question the screen is here to answer. The daily total drops to one hairline below
/// it, and the blocked apps stop being a status row of circles: they are now what the balance
/// buys. History lives in the Progress tab; this screen holds nothing that is not today.
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    var onNavigate: ((AppSection) -> Void)? = nil

    @State private var isShowingSettings = false
    @State private var isShowingWeek = false
    @State private var isShowingApps = false
    @State private var isShowingSpend = false
    @State private var isShowingJourneyResult = false
    @State private var selection = FamilyActivitySelection()
    @State private var selectedSessionMinutes = 5
    @State private var guardianEmphasis: CGFloat = 0

    /// The one value the whole screen interpolates from.
    private var progress: Double { env.dayProgress }

    var body: some View {
        ZStack {
            GuardianAtmosphere(progress: progress)

            home

            if let feedback = env.presentationFeedback {
                EarnFeedbackOverlay(
                    feedback: feedback,
                    onFinished: { env.dismissPresentationFeedback(feedback) }
                )
                    .zIndex(1)
            }
        }
        .foregroundStyle(Theme.ink)
        .animation(reduceMotion ? nil : .easeInOut(duration: EarnMotion.reward), value: progress)
        .animation(reduceMotion ? nil : .snappy(duration: EarnMotion.standard), value: env.isLocked)
        .task {
            await env.refresh()
            if env.state.adaptiveIntroSeen {
                await env.evaluateGoalRecommendation()
            }
        }
        .task(id: env.activeSession?.id) {
            guard let session = env.activeSession else { return }
            try? await Task.sleep(for: .seconds(max(0, session.endsAt.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            env.reload()
        }
        .task(id: env.presentationFeedback?.id) {
            guardianEmphasis = 0
            guard !reduceMotion, guardianAmplitude > 0 else { return }

            await Task.yield()
            withAnimation(.smooth(duration: 0.30)) {
                guardianEmphasis = 1
            }
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.44)) {
                guardianEmphasis = 0
            }
        }
        .onAppear {
            selection = env.screenTime.selection
            isShowingJourneyResult = env.journey?.finalizedResult != nil
                && env.journey?.completionAcknowledged == false
        }
        .onChange(of: env.wallet.availableMinutes) { _, availableMinutes in
            if selectedSessionMinutes > availableMinutes {
                selectedSessionMinutes = max(1, availableMinutes)
            }
        }
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
        .sheet(isPresented: $isShowingWeek) { WeekView() }
        .sheet(isPresented: $isShowingApps, onDismiss: { selection = env.screenTime.selection }) {
            AppSelectionView()
        }
        .sheet(isPresented: $isShowingSpend) {
            SpendSheet(selectedMinutes: $selectedSessionMinutes)
                .presentationDetents([.height(430)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingJourneyResult, onDismiss: env.acknowledgeJourneyCompletion) {
            if let journey = env.journey, let result = journey.finalizedResult {
                JourneyResultView(journey: journey, result: result) {
                    env.acknowledgeJourneyCompletion()
                    isShowingJourneyResult = false
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { env.profile.pendingGoalRecommendation != nil },
            set: { if !$0, env.profile.pendingGoalRecommendation != nil { env.respondToGoalRecommendation(accept: false) } }
        )) {
            GoalRecommendationView()
                .interactiveDismissDisabled()
        }
    }

    // MARK: - Home
    //
    // Three bands: a hairline header, an elastic stage the Guardian is anchored to the bottom of,
    // and a copy block fixed to its own content height. The figure takes the upper screen back as
    // the day is earned because the stage is whatever the copy leaves it.

    private var home: some View {
        VStack(spacing: 0) {
            header

            GuardianStage(progress: progress)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(guardianScale)
                .offset(y: guardianOffset)

            copy
        }
    }

    private var header: some View {
        HStack {
            Text(Date.now.formatted(.dateTime.weekday(.wide).locale(locale)))
            Spacer()
            if env.streakDays > 0 {
                Text("dashboard.streak \(env.streakDays)")
                    .foregroundStyle(progress > 0.2 ? Theme.cobalt : Theme.muted)
                    .contentTransition(.numericText(value: Double(env.streakDays)))
            }
        }
        .font(.sans(12.5, weight: .semibold))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 26)
        .padding(.top, 2)
    }

    // MARK: - Copy

    private var copy: some View {
        VStack(alignment: .leading, spacing: 0) {
            headline

            Hairline().padding(.top, ramp(progress, [(0.06, 26), (1.00, 20)]))

            totals.padding(.top, ramp(progress, [(0.06, 15), (1.00, 13)]))

            walletSummary.padding(.top, Theme.Space.m)

            if let error = env.lastError {
                Text(error)
                    .font(.sans(12.5))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Space.s)
                    .transition(.opacity)
            }

            Spacer(minLength: ramp(progress, [(0.06, 20), (1.00, 12)]))

            spendBand.padding(.top, Theme.Space.m)

            if onNavigate == nil {
                footerLinks.padding(.top, Theme.Space.s)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: env.lastError)
    }

    /// The reward loop, in the largest type on the screen.
    ///
    /// At a full day it has nothing left to ask for, so it states what was earned instead.
    @ViewBuilder
    private var headline: some View {
        let display = ramp(progress, [(0.06, 62), (0.47, 58), (0.92, 56), (1.00, 56)])
        let aside = ramp(progress, [(0.06, 25), (0.47, 24), (0.92, 23), (1.00, 23)])

        if progress >= 1 {
            VStack(alignment: .leading, spacing: 0) {
                Text("home.minutesEarnedHeadline \(env.earnedMinutesToday)")
                    .font(.serif(display))
                    .foregroundStyle(Theme.cobalt)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("home.spendHowever")
                    .font(.serif(aside, italic: true, relativeTo: .title2))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("dashboard.stepsToGo \(env.nextMilestone.remainingAmount)")
                    .font(.serif(display))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: Double(env.nextMilestone.remainingAmount)))
                Text(env.isFinalMilestoneOfDay ? "home.untilYourLast" : "home.untilYourNext")
                    .font(.serif(aside, italic: true, relativeTo: .title2))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, ramp(progress, [(0.06, 8), (1.00, 6)]))
                    .padding(.bottom, 2)
                Text("dashboard.minutesReward \(env.nextMilestone.rewardMinutes)")
                    .font(.serif(display))
                    // Cobalt only once the day has actually paid out: at zero earned it is still
                    // a promise, not a reward.
                    .foregroundStyle(env.earnedMinutesToday > 0 ? Theme.cobalt : Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// The day's totals, demoted to one hairline row — and the only place to pull fresh steps
    /// from, since this screen has no scroll to refresh.
    private var totals: some View {
        Button {
            Task { await env.refresh() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Pre-formatted so the count keeps its locale's thousands separators.
                Text("home.stepsTodayCount \(env.ledger.activityAmount.formatted(.number.locale(locale)))")
                    .contentTransition(.numericText(value: Double(env.ledger.activityAmount)))
                Text(verbatim: "·").opacity(0.45)
                if progress >= 1 {
                    Text("home.fullDay")
                } else {
                    Text("home.minutesEarnedCount \(env.earnedMinutesToday)")
                        .foregroundStyle(env.earnedMinutesToday > 0 ? Theme.cobalt : Theme.muted)
                        .fontWeight(env.earnedMinutesToday > 0 ? .semibold : .regular)
                        .contentTransition(.numericText(value: Double(env.earnedMinutesToday)))
                }
                if env.isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.muted)
                        .accessibilityHidden(true)
                }
            }
            .font(.sans(13))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(env.isRefreshing)
        .accessibilityHint(Text("dashboard.refreshSteps"))
    }

    private var walletSummary: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let balance = env.currentWalletBalanceSeconds(at: context.date) / 60
            let consumed = env.currentConsumedSeconds(at: context.date) / 60
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("wallet.title")
                        .font(.sans(10.5, weight: .semibold))
                        .textCase(.uppercase)
                        .kerning(1.3)
                        .foregroundStyle(Theme.muted)
                    Text("common.minutesValue \(balance)")
                        .font(.serif(31))
                        .foregroundStyle(Theme.cobalt)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(balance)))
                }
                Spacer(minLength: Theme.Space.s)
                walletMetric("wallet.earnedToday", value: "+\(env.earnedMinutesToday)")
                walletMetric("wallet.consumedToday", value: "−\(consumed)")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("wallet.summary \(balance) \(env.earnedMinutesToday) \(consumed)"))
        }
    }

    private func walletMetric(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title)
                .font(.sans(10.5))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.sans(15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
        }
    }

    /// The slot below the hairline: what the balance buys, or the session already running.
    @ViewBuilder
    private var spendBand: some View {
        if let session = env.activeSession {
            activeSessionView(session).transition(.opacity)
        } else {
            ReadyToSpendRow(
                selection: selection,
                availableMinutes: env.wallet.availableMinutes,
                minimumSpendMinutes: 1,
                onChoose: { isShowingApps = true },
                onSpend: {
                    guard env.wallet.availableMinutes > 0 else { return }
                    isShowingSpend = true
                }
            )
            .transition(.opacity)
        }
    }

    private func activeSessionView(_ session: ScreenTimeSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label("session.active", systemImage: "lock.open.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.sans(11))
                    .textCase(.uppercase)
                    .kerning(1.5)
                    .foregroundStyle(Theme.cobaltDeep)
                    .contentTransition(.symbolEffect(.replace))
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(sessionTime(session.remainingSeconds(at: context.date)))
                        .font(.sans(22, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.cobalt)
                        .contentTransition(.numericText())
                }
            }
            Text("session.active.explanation")
                .font(.sans(12.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Text("session.walletSaved \(env.wallet.availableMinutes)")
                .font(.sans(12.5, weight: .semibold))
                .foregroundStyle(Theme.cobaltDeep)
                .monospacedDigit()

            Button {
                Task { await env.pauseSession() }
            } label: {
                HStack {
                    if env.isPausingSession {
                        ProgressView().controlSize(.small).accessibilityHidden(true)
                    }
                    Text("session.endAndSave")
                    Spacer()
                    Image(systemName: "stop.fill").accessibilityHidden(true)
                }
                .font(.sans(14, weight: .semibold))
                .frame(minHeight: Theme.minTouchTarget)
                .foregroundStyle(Theme.cobaltDeep)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(env.isPausingSession)
        }
        .padding(.vertical, 10)
    }

    private func sessionTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var guardianScale: CGFloat {
        0.9 * (1 + guardianAmplitude * guardianEmphasis)
    }

    private var guardianOffset: CGFloat {
        -16 - 3 * guardianEmphasis
    }

    private var guardianAmplitude: CGFloat {
        guard !reduceMotion else { return 0 }
        return switch env.presentationFeedback?.event {
        case .screenTimeEarned: 0.012
        case .firstRewardEarned: 0.032
        case .dailyGoalCompleted: 0.025
        default: 0
        }
    }

    private var footerLinks: some View {
        HStack(spacing: Theme.Space.l) {
            Button("dashboard.thisWeek") { isShowingWeek = true }
                .buttonStyle(.quietLink)
            Button("settings.title") { isShowingSettings = true }
                .buttonStyle(.quietLink)
        }
    }
}

private struct EarnFeedbackOverlay: View {
    let feedback: EarnPresentationFeedback
    let onFinished: () -> Void
    var reduceMotionOverride: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var phase = Phase.hidden

    private enum Phase {
        case hidden
        case arrived
        case settled
        case exiting
    }

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

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

    var body: some View {
        Group {
            if let title {
                VStack {
                    Text(title)
                        .font(.sans(12, weight: .bold))
                        .textCase(.uppercase)
                        .kerning(1.2)
                        .foregroundStyle(Theme.cobaltDeep)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Theme.paper.opacity(0.94), in: .capsule)
                        .overlay {
                            Capsule()
                                .stroke(Theme.cobalt.opacity(borderOpacity), lineWidth: 1)
                        }
                        .shadow(color: Theme.cobalt.opacity(shadowOpacity), radius: 14, y: 5)
                        .opacity(opacity)
                        .scaleEffect(scale)
                        .offset(y: offset)
                        .accessibilityAddTraits(.isStaticText)
                    Spacer()
                }
                .padding(.top, 64)
                .accessibilityElement(children: .combine)
                .allowsHitTesting(false)
            }
        }
        .task(id: feedback.id) {
            guard title != nil else {
                onFinished()
                return
            }
            await animatePresentation()
        }
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
        case .hidden: 0.985
        case .arrived, .settled: 1
        case .exiting: 0.995
        }
    }

    private var offset: CGFloat {
        guard !reduceMotion else { return 0 }
        return switch phase {
        case .hidden: 8
        case .arrived, .settled: 0
        case .exiting: -6
        }
    }

    private var borderOpacity: Double {
        switch phase {
        case .hidden, .exiting: 0
        case .arrived: 0.32
        case .settled: 0.14
        }
    }

    private var shadowOpacity: Double {
        switch phase {
        case .arrived: 0.10
        default: 0
        }
    }

    @MainActor
    private func animatePresentation() async {
        phase = .hidden
        await Task.yield()
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: reduceMotion ? 0.18 : 0.32)) {
            phase = .arrived
        }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 180 : 320))
        guard !Task.isCancelled else { return }

        try? await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 160))
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: reduceMotion ? 0.18 : 0.36)) {
            phase = .settled
        }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 180 : 360))
        guard !Task.isCancelled else { return }

        try? await Task.sleep(for: .milliseconds(voiceOverEnabled ? 1_800 : 650))
        guard !Task.isCancelled else { return }

        withAnimation(.easeIn(duration: reduceMotion ? 0.18 : 0.36)) {
            phase = .exiting
        }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 180 : 360))
        guard !Task.isCancelled else { return }
        onFinished()
    }
}

// MARK: - Spending

/// Choosing how much of the balance to spend.
///
/// Home has no start button — the design's spend row *is* the affordance — so the durations live
/// here, one tap in.
struct SpendSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedMinutes: Int
    var onStarted: () -> Void = {}

    private var presetDurations: [Int] {
        let maximum = env.maximumStartableMinutes
        guard maximum > 0 else { return [] }
        var durations = env.supportedSessionDurations.filter { $0 <= maximum }
        if maximum < (env.supportedSessionDurations.last ?? maximum),
           !durations.contains(maximum) {
            durations.append(maximum)
        }
        return durations
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("session.chooseDuration")
                .font(.sans(11))
                .textCase(.uppercase)
                .kerning(1.5)
                .foregroundStyle(Theme.muted)

            HStack(spacing: Theme.Space.s) {
                ForEach(presetDurations, id: \.self) { minutes in
                    let isSelected = selectedMinutes == minutes
                    Button {
                        selectedMinutes = minutes
                    } label: {
                        Text("common.minutesValue \(minutes)")
                            .font(.sans(15, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.white : Theme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Theme.minTouchTarget)
                            .background(
                                isSelected ? Theme.cobalt : Theme.stone.opacity(0.7),
                                in: .capsule
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            Stepper(value: $selectedMinutes, in: 1...max(1, env.maximumStartableMinutes)) {
                HStack {
                    Text("session.customDuration")
                        .font(.sans(14))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text("common.minutesValue \(selectedMinutes)")
                        .font(.sans(16, weight: .semibold))
                        .monospacedDigit()
                }
            }

            Text("session.clockDisclaimer")
                .font(.sans(12.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task {
                    await env.startSession(durationMinutes: selectedMinutes)
                    if env.lastError == nil {
                        dismiss()
                        onStarted()
                    }
                }
            } label: {
                HStack(spacing: Theme.Space.s) {
                    if env.isStartingSession {
                        ProgressView().tint(Color.white).accessibilityHidden(true)
                    }
                    Text("session.start \(selectedMinutes)")
                }
            }
            .buttonStyle(.pill(.sage))
            .disabled(env.isStartingSession || selectedMinutes > env.maximumStartableMinutes)

            if let error = env.lastError {
                Text(error)
                    .font(.sans(12.5))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, Theme.Space.xl)
        .padding(.bottom, Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Theme.ink)
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            selectedMinutes = min(max(1, selectedMinutes), max(1, env.maximumStartableMinutes))
        }
    }
}

// MARK: - Pieces

/// The soft label that floats over an illustration.
struct Chip: View {
    let text: Text
    var color: Color = Theme.ink

    var body: some View {
        text
            .font(.sans(12.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(Theme.paper.opacity(0.8), in: .capsule)
    }
}

/// A number with its meaning underneath.
struct StatPair: View {
    let value: Text
    let caption: LocalizedStringKey
    var color: Color = Theme.ink
    var numericValue: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            value
                .font(.sans(15.5, weight: .bold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .contentTransition(.numericText(value: numericValue ?? 0))
                .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: numericValue)
            Text(caption)
                .font(.sans(11.5, weight: .semibold))
                .textCase(.uppercase)
                .kerning(1)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct JourneyResultView: View {
    @Environment(\.locale) private var locale
    let journey: ThirtyDayJourney
    let result: ThirtyDayJourney.FinalizedResult
    let onDone: () -> Void

    /// How far the month actually got — the Guardian the whole sheet is painted at.
    private var progress: Double {
        result.reachedTarget
            ? 1
            : min(1, Double(result.cumulativeSteps) / Double(max(1, journey.target)))
    }

    var body: some View {
        ZStack {
            GuardianAtmosphere(progress: progress)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GuardianPortrait(progress: progress)
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)

                    Text("YOU EARNED YOUR MONTH").eyebrowStyle(Theme.cobaltDeep).padding(.top, Theme.Space.l)
                    Text("That’s what happens when your phone gives you a reason to move.")
                        .font(.serif(39))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)

                    VStack(spacing: 0) {
                        resultRow(
                            "figure.walk",
                            Text(result.cumulativeSteps.formatted(.number.locale(locale))),
                            Text("steps"),
                            Theme.cobaltDeep
                        )
                        Hairline()
                        resultRow("timer", durationText(result.earnedSeconds), Text("earned"), Theme.cobaltDeep)
                        Hairline()
                        resultRow(
                            "flame.fill",
                            Text("\(result.activeDays)"),
                            Text("active days"),
                            Theme.cobaltDeep
                        )
                        Hairline()
                        resultRow(
                            "trophy.fill",
                            Text("\(result.goalHitDays)"),
                            Text("days hitting your goal"),
                            Theme.ink
                        )
                    }
                    .padding(.top, Theme.Space.l)

                    Button("Keep earning", action: onDone)
                        .buttonStyle(.pill)
                        .padding(.top, Theme.Space.xl)
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.bottom, Theme.Space.xl)
            }
        }
    }

    private func resultRow(_ icon: String, _ value: Text, _ label: Text, _ color: Color) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 30).accessibilityHidden(true)
            value.font(.serif(29)).foregroundStyle(color)
            Spacer()
            label.font(.sans(13.5, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .combine)
    }

    private func durationText(_ seconds: Int) -> Text {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return Text("\(hours)h \(minutes)m")
    }
}

#Preview {
    DashboardView()
        .environment(AppEnvironment(
            screenTime: MockScreenTimeService(status: .approved),
            health: MockHealthKitService(hasRequested: true, steps: 3_842)
        ))
}

#Preview("Earned feedback") {
    ZStack {
        PaperBackground()
        EarnFeedbackOverlay(
            feedback: EarnPresentationFeedback(event: .screenTimeEarned(minutes: 5)),
            onFinished: {}
        )
    }
}

#Preview("Goal feedback - Reduce Motion") {
    ZStack {
        PaperBackground()
        EarnFeedbackOverlay(
            feedback: EarnPresentationFeedback(event: .dailyGoalCompleted(minutes: 5)),
            onFinished: {},
            reduceMotionOverride: true
        )
    }
}
