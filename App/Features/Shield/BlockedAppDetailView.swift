import EarnDomain
import FamilyControls
import SwiftUI

struct BlockedAppDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onDismiss: () -> Void
    @State private var isChoosingDuration = false
    @State private var selectedMinutes = 5

    private var viewModel: ShieldViewModel { ShieldViewModel(sharedState: env.state) }

    private var guardianProgress: Double {
        return switch viewModel.state {
        case .rewardAvailable, .dailyGoalCompleted: 1
        case .almostThere: 0.86
        case .sessionExpired: 0.24
        case .noTime, .progress: max(0.08, viewModel.progress)
        }
    }

    var body: some View {
        ZStack {
            Color(red: 41 / 255, green: 40 / 255, blue: 36 / 255)
                .ignoresSafeArea()

            Circle()
                .fill(Theme.cobalt.opacity(0.16))
                .frame(width: 310, height: 310)
                .blur(radius: 64)
                .offset(y: -190)
                .accessibilityHidden(true)

            ScrollView {
                VStack(spacing: 0) {
                    GuardianPortrait(progress: guardianProgress)
                        .frame(maxWidth: 310, maxHeight: 260)
                        .padding(.top, Theme.Space.m)
                        .offset(y: reduceMotion ? 0 : -2)

                    Text(eyebrow)
                        .font(.sans(12, weight: .bold))
                        .textCase(.uppercase)
                        .kerning(1.8)
                        .foregroundStyle(Theme.cobalt)
                        .padding(.top, Theme.Space.m)

                    Text(headline)
                        .font(.system(.largeTitle, design: .default, weight: .bold))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Space.s)

                    Text(supportingCopy)
                        .font(.sans(17))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Space.s)

                    stateContent
                        .padding(.top, Theme.Space.l)

                    if let error = env.lastError {
                        Text(error)
                            .font(.sans(13))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Theme.Space.m)
                            .transition(.opacity)
                    }

                    EarnPrimaryButton(
                        label: primaryLabel,
                        isEnabled: !env.isRefreshing && !env.isStartingSession,
                        action: primaryAction
                    )
                    .padding(.top, Theme.Space.xl)

                    Button("shield.detail.notNow", action: onDismiss)
                        .buttonStyle(.quiet)
                        .foregroundStyle(Color.white.opacity(0.65))
                        .padding(.top, Theme.Space.s)
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.bottom, Theme.Space.xl)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: viewModel.state)
        .sheet(isPresented: $isChoosingDuration) {
            SpendSheet(selectedMinutes: $selectedMinutes, onStarted: onDismiss)
                .presentationDetents([.height(430)])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        if !env.screenTime.authorizationStatus.isApproved {
            Text("shield.detail.restoreAccess")
                .font(.sans(14))
                .foregroundStyle(Color.white.opacity(0.68))
                .multilineTextAlignment(.center)
        } else if !env.health.hasRequestedAuthorization {
            Text("shield.detail.connectHealth")
                .font(.sans(14))
                .foregroundStyle(Color.white.opacity(0.68))
                .multilineTextAlignment(.center)
        } else if !viewModel.hasActivityData {
            ProgressView()
                .tint(Theme.cobalt)
                .controlSize(.large)
                .accessibilityLabel(Text("shield.detail.updating"))
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
