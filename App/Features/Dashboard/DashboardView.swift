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
        case study
    }

    @State private var path: [HomeDestination] = []
    @State private var isShowingApps = false
    @State private var isShowingSpend = false
    @State private var isShowingJourneyResult = false
    @State private var selection = FamilyActivitySelection()
    @State private var selectedSessionMinutes = 5
    @State private var didStartSession = false
    @State private var isShowingPushupsPaywall = false
    @State private var isShowingStudyPaywall = false
    @State private var isShowingUnlockPaywall = false

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
                        guard !env.requiresSubscription else {
                            isShowingUnlockPaywall = true
                            return
                        }
                        isShowingSpend = true
                    },
                    onEarnMore: { path.append(.earnTime) },
                    onPushups: { openPushups(source: "home") }
                )

            }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $isShowingPushupsPaywall) {
                ProPaywallView(source: .pushups)
            }
            .fullScreenCover(isPresented: $isShowingStudyPaywall) {
                ProPaywallView(source: .study)
            }
            .fullScreenCover(isPresented: $isShowingUnlockPaywall) {
                ProPaywallView(source: .unlockAttempt)
            }
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .earnTime:
                    EarnTimeView(
                        onPushups: { openPushups(source: "earn_time") },
                        onStudy: openStudy
                    )
                case .pushups:
                    PushupsToEarnView(onUseMinutes: openSpendAfterReward)
                case .study:
                    StudyToEarnView(onUseMinutes: openSpendAfterReward)
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
            if env.profile.pendingGoalRecommendation != nil {
                env.setFeedbackPresentationSuspended(true, by: "dashboard.goalRecommendation")
            }
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
        .onChange(of: isShowingApps) { _, isPresented in
            guard isPresented else { return }
            env.setFeedbackPresentationSuspended(true, by: "dashboard.apps")
        }
        .onChange(of: isShowingSpend) { _, isPresented in
            guard isPresented else { return }
            env.setFeedbackPresentationSuspended(true, by: "dashboard.spend")
        }
        .onChange(of: isShowingJourneyResult) { _, isPresented in
            guard isPresented else { return }
            env.setFeedbackPresentationSuspended(true, by: "dashboard.journey")
        }
        .onChange(of: env.profile.pendingGoalRecommendation != nil) { _, isPresented in
            guard isPresented else { return }
            env.setFeedbackPresentationSuspended(true, by: "dashboard.goalRecommendation")
        }
        .sheet(isPresented: $isShowingApps, onDismiss: {
            selection = env.screenTime.selection
            env.setFeedbackPresentationSuspended(false, by: "dashboard.apps")
        }) {
            AppSelectionView()
        }
        .sheet(isPresented: $isShowingSpend, onDismiss: {
            env.setFeedbackPresentationSuspended(false, by: "dashboard.spend")
            guard didStartSession else { return }
            didStartSession = false
            env.presentSessionStartedFeedback()
        }) {
            SpendSheet(
                selectedMinutes: $selectedSessionMinutes,
                onStarted: { didStartSession = true }
            )
                .presentationDetents([.height(560), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingJourneyResult, onDismiss: {
            env.acknowledgeJourneyCompletion()
            env.setFeedbackPresentationSuspended(false, by: "dashboard.journey")
        }) {
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
        ), onDismiss: {
            env.setFeedbackPresentationSuspended(false, by: "dashboard.goalRecommendation")
        }) {
            GoalRecommendationView()
                .interactiveDismissDisabled()
        }
    }

    /// Pushups lives in this stack, so deep links are resolved here rather than in `RootView`.
    private func applyPendingRoute(_ route: AppRoute?) {
        guard route == .pushups else { return }
        isShowingSpend = false
        env.consumePendingRoute()
        guard env.featureAccess.canUseWorkoutEarning else {
            isShowingPushupsPaywall = true
            return
        }
        path = [.pushups]
    }

    /// Someone who has not paid gets one push-up reward. Once it is used, push-ups open a paywall
    /// they can close rather than a challenge the server would refuse at the claim.
    private func openPushups(source: String) {
        env.analytics.track(.pushupsEntryTapped.withProperties([
            "source": .string(source),
            "has_access": .bool(env.featureAccess.canUseWorkoutEarning)
        ]))
        guard env.featureAccess.canUseWorkoutEarning else {
            isShowingPushupsPaywall = true
            return
        }
        path.append(.pushups)
    }

    private func openStudy() {
        guard env.featureAccess.canUseFocusEarning else {
            isShowingStudyPaywall = true
            return
        }
        path.append(.study)
    }

    private func openSpendAfterReward() {
        path.removeAll()
        if env.screenTime.selection.isEmpty {
            isShowingApps = true
        } else if env.requiresSubscription {
            isShowingUnlockPaywall = true
        } else {
            isShowingSpend = true
        }
    }
}

// MARK: - Spending

/// Choosing how much of the balance to spend.
///
/// The duration, selected apps, and resulting balance are visible before the reservation begins.
struct SpendSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    private var minutesAfterSession: Int {
        max(0, env.wallet.availableMinutes - selectedMinutes)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    NightEyebrow(text: "session.chooseDuration")
                    Text("home.useMinutes")
                        .font(.serif(35))
                        .foregroundStyle(Night.text)
                }

                HStack(alignment: .firstTextBaseline) {
                    balanceFigure(env.wallet.availableMinutes, label: "session.available")
                    Spacer(minLength: Theme.Space.s)
                    Image(systemName: "arrow.right")
                        .font(.sans(14, weight: .semibold))
                        .foregroundStyle(Night.textDim)
                    Spacer(minLength: Theme.Space.s)
                    balanceFigure(minutesAfterSession, label: "session.after")
                }
                .padding(Theme.Space.m)
                .background(Night.panel, in: .rect(cornerRadius: Night.cardRadius))

                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack(spacing: Theme.Space.s) {
                        ForEach(presetDurations, id: \.self) { minutes in
                            let isSelected = selectedMinutes == minutes
                            Button {
                                guard selectedMinutes != minutes else { return }
                                selectedMinutes = minutes
                                HapticManager.trigger(.light)
                            } label: {
                                Text("common.minutesValue \(minutes)")
                                    .font(.sans(15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: Theme.minTouchTarget)
                            }
                            .buttonStyle(DurationChoiceButtonStyle(isSelected: isSelected))
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }

                    Stepper(value: $selectedMinutes, in: 1...max(1, env.maximumStartableMinutes)) {
                        HStack {
                            Text("session.customDuration")
                                .font(.sans(14))
                                .foregroundStyle(Night.textMuted)
                            Spacer()
                            Text("common.minutesValue \(selectedMinutes)")
                                .font(.sans(16, weight: .semibold))
                                .foregroundStyle(Night.text)
                                .monospacedDigit()
                                .contentTransition(.numericText(value: Double(selectedMinutes)))
                        }
                    }
                    .tint(Night.cobalt)
                }
                .animation(reduceMotion ? nil : .snappy(duration: EarnMotion.quick), value: selectedMinutes)

                Label("appSelection.count \(env.screenTime.selection.itemCount)", systemImage: "square.grid.2x2")
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Night.textSoft)

                Text("session.clockDisclaimer")
                    .font(.sans(12.5))
                    .foregroundStyle(Night.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = env.lastError {
                    Text(error)
                        .font(.sans(12.5))
                        .foregroundStyle(Night.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, Theme.Space.xl)
            .padding(.bottom, Theme.Space.m)
        }
        .safeAreaInset(edge: .bottom) {
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
                        ProgressView().tint(.white).accessibilityHidden(true)
                    }
                    Text("session.start \(selectedMinutes)")
                }
            }
            .buttonStyle(.nightPill)
            .disabled(env.isStartingSession || selectedMinutes > env.maximumStartableMinutes)
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.s)
            .background(Night.ground)
        }
        .foregroundStyle(Night.text)
        .background(Night.ground.ignoresSafeArea())
        .onAppear {
            selectedMinutes = min(max(1, selectedMinutes), max(1, env.maximumStartableMinutes))
        }
    }

    private func balanceFigure(_ minutes: Int, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(minutes.formatted())
                .font(.serif(32))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(minutes)))
            Text(label)
                .font(.sans(12))
                .foregroundStyle(Night.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DurationChoiceButtonStyle: ButtonStyle {
    let isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.white : Night.textSoft)
            .background(isSelected ? Night.cobalt : Night.forestLift, in: .capsule)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
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
