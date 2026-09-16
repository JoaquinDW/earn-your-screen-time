import EarnDomain
import FamilyControls
import SwiftUI

/// The Home tab's host (design v6).
///
/// The screen itself is `DashboardHome`; this type keeps everything that is not drawing —
/// refresh, the session lifecycle, the sheets, the goal recommendation, the deep-link route —
/// unchanged from v5, and adds the one new destination v6 introduces: `EarnTimeView`.
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Lets `RootView` pull the tab bar away while a destination is pushed, the same way
    /// `SettingsView` already does.
    var onNavigationDepthChange: ((Bool) -> Void)? = nil

    private enum HomeDestination: Hashable {
        case earnTime
        case pushups
    }

    @State private var path: [HomeDestination] = []
    @State private var isShowingApps = false
    @State private var isShowingSpend = false
    @State private var isShowingJourneyResult = false
    @State private var selection = FamilyActivitySelection()
    @State private var selectedSessionMinutes = 5

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                // The evening is the ground, not a decoration behind a card: it owns the whole
                // screen and `SceneBackdrop` washes its edges back into `Night.ground`.
                SceneBackdrop(scene: .homeEvening).ignoresSafeArea()

                DashboardHome(
                    selection: selection,
                    onChooseApps: { isShowingApps = true },
                    onSpend: {
                        guard env.wallet.availableMinutes > 0 else { return }
                        isShowingSpend = true
                    },
                    onEarnMore: { path.append(.earnTime) }
                )

                if let feedback = env.presentationFeedback {
                    EarnFeedbackOverlay(
                        feedback: feedback,
                        onFinished: { env.dismissPresentationFeedback(feedback) }
                    )
                    .zIndex(1)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .earnTime:
                    EarnTimeView(
                        onPushups: { path.append(.pushups) }
                    )
                case .pushups:
                    PushupsToEarnView(onUseMinutes: {
                        path.removeAll()
                        isShowingSpend = true
                    })
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: EarnMotion.standard), value: env.isLocked)
        .trackScreen("dashboard", analytics: env.analytics)
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
        .onChange(of: env.pendingRoute) { _, route in
            applyPendingRoute(route)
        }
        .onAppear {
            applyPendingRoute(env.pendingRoute)
            // Report the depth on entry too, not only when it changes: coming back to the tab
            // with a destination still pushed has to keep the tab bar away.
            onNavigationDepthChange?(!path.isEmpty)
            selection = env.screenTime.selection
            isShowingJourneyResult = env.journey?.finalizedResult != nil
                && env.journey?.completionAcknowledged == false
        }
        .onChange(of: path) { _, path in
            onNavigationDepthChange?(!path.isEmpty)
        }
        .onDisappear { onNavigationDepthChange?(false) }
        .onChange(of: env.wallet.availableMinutes) { _, availableMinutes in
            if selectedSessionMinutes > availableMinutes {
                selectedSessionMinutes = max(1, availableMinutes)
            }
        }
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

    /// The push-up route is deep in this stack, so it is resolved here rather than in `RootView`.
    private func applyPendingRoute(_ route: AppRoute?) {
        guard route == .pushups else { return }
        isShowingSpend = false
        path = [.earnTime, .pushups]
        env.consumePendingRoute()
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
                        .foregroundStyle(Night.cobaltText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: .capsule)
                        .background(Night.panel.opacity(0.9), in: .capsule)
                        .overlay {
                            Capsule()
                                .stroke(Night.cobalt.opacity(borderOpacity), lineWidth: 1)
                        }
                        .shadow(color: Night.cobalt.opacity(shadowOpacity), radius: 14, y: 5)
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
        case .arrived: 0.55
        case .settled: 0.22
        }
    }

    private var shadowOpacity: Double {
        switch phase {
        case .arrived: 0.22
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
                            .foregroundStyle(isSelected ? Color.white : Night.textSoft)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Theme.minTouchTarget)
                            .background(
                                isSelected ? Night.cobalt : Night.forestLift,
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
            .buttonStyle(.pill)
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
        .background(Night.ground.ignoresSafeArea())
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

    /// How far the month actually got.
    private var progress: Double {
        result.reachedTarget
            ? 1
            : min(1, Double(result.cumulativeSteps) / Double(max(1, journey.target)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Thirty days is the one completion moment the product has, so it gets the
                // aspirational frame — and it is the only place outside onboarding and the
                // paywall that does.
                SceneHero(scene: .freedomRidge, share: 0.40) {
                    Text("YOU EARNED YOUR MONTH").eyebrowStyle(Night.textSoft)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("That’s what happens when your phone gives you a reason to move.")
                        .font(.serif(36))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Space.l)

                    VStack(spacing: 0) {
                        resultRow(
                            "figure.walk",
                            Text(result.cumulativeSteps.formatted(.number.locale(locale))),
                            Text("steps"),
                            Night.text
                        )
                        Hairline()
                        resultRow("timer", durationText(result.earnedSeconds), Text("earned"), Night.cobaltText)
                        Hairline()
                        resultRow(
                            "flame.fill",
                            Text("\(result.activeDays)"),
                            Text("active days"),
                            Night.text
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
        .scrollBounceBehavior(.basedOnSize)
        .ignoresSafeArea(edges: .top)
        .background(Night.ground.ignoresSafeArea())
        .foregroundStyle(Night.text)
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
        SceneBackdrop(scene: .homeEvening).ignoresSafeArea()
        EarnFeedbackOverlay(
            feedback: EarnPresentationFeedback(event: .screenTimeEarned(minutes: 5)),
            onFinished: {}
        )
    }
}

#Preview("Goal feedback - Reduce Motion") {
    ZStack {
        SceneBackdrop(scene: .homeEvening).ignoresSafeArea()
        EarnFeedbackOverlay(
            feedback: EarnPresentationFeedback(event: .dailyGoalCompleted(minutes: 5)),
            onFinished: {},
            reduceMotionOverride: true
        )
    }
}
