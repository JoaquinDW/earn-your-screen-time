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
/// The state machine, the copy keys and every action are unchanged from v5: this is a redress of
/// `ShieldViewModel`, not a new behaviour.
struct BlockedAppDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onDismiss: () -> Void
    @State private var isChoosingDuration = false
    @State private var selectedMinutes = 5

    private static let scene = IllustratedScene.blockedBench

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
        .sheet(isPresented: $isChoosingDuration) {
            SpendSheet(selectedMinutes: $selectedMinutes, onStarted: onDismiss)
                .presentationDetents([.height(430)])
                .presentationDragIndicator(.visible)
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
            EarnPrimaryButton(
                label: primaryLabel,
                isEnabled: !env.isRefreshing && !env.isStartingSession,
                action: primaryAction
            )

            Button("shield.detail.notNow", action: onDismiss)
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

    // MARK: - Copy
    //
    // Unchanged from v5 — the states and their strings were already written to be a boundary
    // rather than a punishment, and they stay exactly as translated.

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
        if viewModel.state == .rewardAvailable {
            return Text("session.chooseDuration")
        }
        return Text("shield.detail.action.update")
    }

    private func primaryAction() {
        Task {
            if !env.screenTime.authorizationStatus.isApproved {
                try? await env.screenTime.requestAuthorization()
                env.reload()
            } else if !env.health.hasRequestedAuthorization {
                try? await env.health.requestAuthorization()
                await env.refresh()
            } else if viewModel.state == .rewardAvailable {
                selectedMinutes = min(max(1, selectedMinutes), viewModel.availableMinutes)
                isChoosingDuration = true
            } else {
                await env.refresh()
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
