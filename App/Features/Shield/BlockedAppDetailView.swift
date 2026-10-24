import EarnDomain
import FamilyControls
import SwiftUI

/// What you see when you reach for a blocked app (design v6).
///
/// This is the screen the whole product turns on, and the one most easily got wrong. The
/// illustration is the man with the phone face-down on the bench, looking at the trees instead:
/// **a boundary drawn as calm, not as denial.** Nothing here scolds — there is no red, no lock
/// icon, no "you've used up your time". It says where you are, what it costs, and how to get it,
/// and then stops talking.
///
/// The artwork is full-bleed and the copy lives in the empty night above him, so the composition
/// never covers the person. The actions sit in a footer that fades into the ground rather than
/// cutting him off with an edge.
///
/// `ShieldViewModel` still owns the presentation state. When no minutes are available, this surface
/// also offers the existing Pushups flow as the fastest route back to earned time.
struct BlockedAppDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onDismiss: () -> Void
    var onSessionStarted: () -> Void = {}
    var onPushups: () -> Void = {}
    @State private var isChoosingDuration = false
    @State private var selectedMinutes = 5
    @State private var didStartSession = false
    @State private var isShowingUnlockPaywall = false
    /// Seconds left in the breathing pause; zero once it has run or when it does not apply.
    @State private var pauseRemaining = 0
    @State private var didPause = false

    private static let scene = IllustratedScene.blockedBench
    /// one sec's pause: long enough for one slow breath, short enough not to feel like a penalty.
    private static let pauseSeconds = 5

    private var isPausing: Bool { pauseRemaining > 0 }

    private var viewModel: ShieldViewModel { ShieldViewModel(sharedState: env.state) }

    var body: some View {
        ZStack(alignment: .top) {
            SceneBackdrop(scene: Self.scene, veil: 0.06).ignoresSafeArea()

            VStack(spacing: 0) {
                closeRow

                ScrollView {
                    message.padding(.horizontal, Theme.Space.gutter)
                }
                .scrollBounceBehavior(.basedOnSize)
                // Everything above the bench. Below it, the evening is left alone.
                .clearOfFigure(in: Self.scene)

                Spacer(minLength: 0)

                actions
            }
        }
        .foregroundStyle(Night.text)
        .tint(Night.cobalt)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: viewModel.state)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: isPausing)
        // Keyed on eligibility: the balance may only arrive after a refresh.
        .task(id: shouldPause) { await runPauseIfNeeded() }
        .sheet(isPresented: $isChoosingDuration, onDismiss: {
            guard didStartSession else { return }
            didStartSession = false
            onSessionStarted()
        }) {
            SpendSheet(
                selectedMinutes: $selectedMinutes,
                onStarted: { didStartSession = true }
            )
                .presentationDetents([.height(560), .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $isShowingUnlockPaywall) {
            ProPaywallView(
                source: .unlockAttempt,
                freePlanNote: "Your free unlock comes back tomorrow. With Pro, unlock whenever you've earned it."
            )
        }
    }

    private var closeRow: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Night.textSoft)
                    .frame(width: Theme.minTouchTarget, height: Theme.minTouchTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("common.close"))
            Spacer()
        }
        .padding(.horizontal, Theme.Space.m)
    }

    // MARK: - The message
    //
    // Eyebrow, headline, one sentence, and then whatever this state actually needs to show —
    // the balance, the distance, or the permission that is missing.

    private var message: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: Theme.Space.l)

            Text(eyebrow).eyebrowStyle(Night.textMuted)

            Text(headline)
                .font(.serif(38, relativeTo: .largeTitle))
                .foregroundStyle(Night.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)

            Text(supportingCopy)
                .font(.sans(16))
                .foregroundStyle(Night.textSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            stateContent.padding(.top, Theme.Space.l)

            if let error = env.lastError {
                Text(error)
                    .font(.sans(13))
                    .foregroundStyle(Night.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Space.m)
                    .transition(.opacity)
            }

            Spacer(minLength: Theme.Space.m)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var stateContent: some View {
        if !env.screenTime.authorizationStatus.isApproved {
            note("shield.detail.restoreAccess")
        } else if !env.health.hasRequestedAuthorization {
            note("shield.detail.connectHealth")
        } else if !viewModel.hasActivityData {
            HStack(spacing: Theme.Space.s) {
                ProgressView().tint(Night.textMuted)
                Text("shield.detail.updating")
                    .font(.sans(14))
                    .foregroundStyle(Night.textMuted)
            }
            .accessibilityElement(children: .combine)
        } else if isPausing {
            BreathingPause(seconds: Self.pauseSeconds, remaining: pauseRemaining)
        } else if viewModel.state == .rewardAvailable {
            EarnedTimeBadge(minutes: viewModel.availableMinutes)
        } else {
            EarnProgressView(
                currentValue: viewModel.currentSteps,
                targetValue: viewModel.targetSteps,
                estimatedRemaining: viewModel.estimatedWalkMinutes,
                rewardMinutes: viewModel.rewardMinutes
            )
        }
    }

    private func note(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.sans(14))
            .foregroundStyle(Night.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 4) {
            if canOfferPushups {
                EarnPrimaryButton(
                    label: Text("shield.detail.action.pushups"),
                    action: onPushups
                )

                Button(action: primaryAction) {
                    primaryLabel
                }
                .buttonStyle(.quiet)
                .disabled(env.isRefreshing || env.isStartingSession)
                .frame(maxWidth: .infinity)
            } else {
                EarnPrimaryButton(
                    label: primaryLabel,
                    isEnabled: !env.isRefreshing && !env.isStartingSession && !isPausing,
                    action: primaryAction
                )
            }

            Button("shield.detail.notNow", action: skip)
                .buttonStyle(.quiet)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.s)
        .background(alignment: .top) {
            // The ground arrives under the buttons instead of a plate, so the bench and the
            // grass keep coming through until the very last moment.
            VStack(spacing: 0) {
                GroundFade(edge: .bottom, height: 110, opacity: 0.94)
                Night.ground.opacity(0.94)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var canOfferPushups: Bool {
        env.screenTime.authorizationStatus.isApproved && viewModel.availableMinutes == 0
    }

    // MARK: - Copy
    //
    // The state copy remains a boundary rather than a punishment; only the actions below it adapt
    // to whether the user already has time available.

    private var eyebrow: LocalizedStringKey {
        return switch viewModel.state {
        case .noTime, .progress: "shield.detail.eyebrow.earn"
        case .almostThere: "shield.detail.eyebrow.almost"
        case .rewardAvailable: "shield.detail.eyebrow.reward"
        case .sessionExpired: "shield.detail.eyebrow.expired"
        case .dailyGoalCompleted: "shield.detail.eyebrow.goal"
        }
    }

    private var headline: LocalizedStringKey {
        if env.health.hasRequestedAuthorization, !viewModel.hasActivityData {
            return "shield.detail.updating"
        }
        return switch viewModel.state {
        case .noTime, .progress: "shield.detail.headline.notYet"
        case .almostThere: "shield.detail.headline.almost \(viewModel.stepsRemaining)"
        case .rewardAvailable: "shield.detail.headline.reward \(viewModel.availableMinutes)"
        case .sessionExpired: "shield.detail.headline.expired \(viewModel.sessionDurationMinutes ?? 0)"
        case .dailyGoalCompleted: "shield.detail.headline.goal"
        }
    }

    private var supportingCopy: LocalizedStringKey {
        if env.health.hasRequestedAuthorization, !viewModel.hasActivityData {
            return "shield.detail.updatingSupport"
        }
        if isPausing { return "shield.detail.pause.breathe" }
        if didPause, viewModel.state == .rewardAvailable { return "shield.detail.pause.ask" }
        return switch viewModel.state {
        case .noTime, .progress:
            "shield.detail.support.progress \(viewModel.stepsRemaining) \(viewModel.rewardMinutes)"
        case .almostThere:
            "shield.detail.support.almost \(viewModel.rewardMinutes)"
        case .rewardAvailable:
            "shield.detail.support.reward"
        case .sessionExpired:
            "shield.detail.support.expired \(viewModel.stepsRemaining)"
        case .dailyGoalCompleted:
            "shield.detail.support.goal \(viewModel.currentSteps) \(viewModel.earnedMinutesToday)"
        }
    }

    private var primaryLabel: Text {
        if !env.screenTime.authorizationStatus.isApproved {
            return Text("shield.detail.action.restore")
        }
        if !env.health.hasRequestedAuthorization {
            return Text("shield.detail.action.connectHealth")
        }
        if isPausing {
            return Text("shield.detail.pause.countdown \(pauseRemaining)")
        }
        if viewModel.state == .rewardAvailable {
            return Text("session.chooseDuration")
        }
        return Text("shield.detail.action.update")
    }

    // MARK: - The pause
    //
    // The shield already stopped the reflex; this is the moment between it and the unlock. With
    // minutes in the bank nothing else stands between the person and the app, so a breath is
    // the one thing that turns a reflex into a choice. Without minutes, earning them is the pause.

    private var shouldPause: Bool {
        env.screenTime.authorizationStatus.isApproved
            && env.health.hasRequestedAuthorization
            && viewModel.hasActivityData
            && viewModel.state == .rewardAvailable
    }

    private func runPauseIfNeeded() async {
        guard shouldPause, !didPause else { return }
        didPause = true
        pauseRemaining = Self.pauseSeconds
        while pauseRemaining > 0 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                // Never leave the unlock disabled behind an interrupted pause.
                pauseRemaining = 0
                return
            }
            pauseRemaining -= 1
        }
        HapticManager.trigger(.light)
    }

    /// Leaving without the app is the outcome the pause exists for, so it is counted.
    private func skip() {
        if didPause {
            env.analytics.track(.mindfulPauseFinished.withProperties([
                "outcome": .string(isPausing ? "skipped_during_pause" : "skipped_after_pause")
            ]))
        }
        env.recordSkippedOpen()
        onDismiss()
    }

    private func primaryAction() {
        Task {
            if !env.screenTime.authorizationStatus.isApproved {
                try? await env.screenTime.requestAuthorization()
                env.reload()
            } else if !env.health.hasRequestedAuthorization {
                try? await env.health.requestAuthorization()
                await env.refresh()
            } else if viewModel.state == .rewardAvailable, env.requiresSubscription {
                isShowingUnlockPaywall = true
            } else if viewModel.state == .rewardAvailable {
                if didPause {
                    env.analytics.track(.mindfulPauseFinished.withProperties(["outcome": .string("unlocked")]))
                }
                selectedMinutes = min(max(1, selectedMinutes), viewModel.availableMinutes)
                isChoosingDuration = true
            } else {
                await env.refresh()
            }
        }
    }
}

/// One slow breath: the ring grows for the in-breath and settles for the out-breath, once.
private struct BreathingPause: View {
    let seconds: Int
    let remaining: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isInhaling = false

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ZStack {
                Circle()
                    .stroke(Night.cobalt.opacity(0.35), lineWidth: 1)
                Circle()
                    .fill(Night.cobaltWash)
                    .overlay(Circle().stroke(Night.cobalt.opacity(0.8), lineWidth: 1.5))
                    .scaleEffect(reduceMotion ? 0.8 : (isInhaling ? 1 : 0.45))
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)

            Text(isInhaling ? LocalizedStringKey("shield.detail.pause.in") : "shield.detail.pause.out")
                .font(.sans(15, weight: .semibold))
                .foregroundStyle(Night.textSoft)
                .contentTransition(.opacity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("shield.detail.pause.countdown \(remaining)"))
        .task {
            // In for a little under half the pause, out for the rest. Reduce Motion keeps the
            // words and drops the movement.
            let inhale = Double(seconds) * 0.45
            withAnimation(reduceMotion ? nil : .easeInOut(duration: inhale)) { isInhaling = true }
            try? await Task.sleep(for: .seconds(inhale))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: Double(seconds) - inhale)) {
                isInhaling = false
            }
        }
    }
}

#Preview {
    BlockedAppDetailView(onDismiss: {})
        .environment(AppEnvironment(
            screenTime: MockScreenTimeService(status: .approved),
            health: MockHealthKitService(hasRequested: true, steps: 1_688)
        ))
}
