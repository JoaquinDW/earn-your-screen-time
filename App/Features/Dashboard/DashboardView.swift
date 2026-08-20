import SwiftUI

/// The home screen (PRD §15). The balance is the one thing you see first.
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var isShowingSettings = false
    @State private var isShowingAppPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.xl) {
                    BalanceRing(
                        availableMinutes: env.wallet.availableMinutes,
                        progress: env.milestoneProgress,
                        isLocked: env.isLocked
                    )
                    .padding(.top, Theme.Space.s)

                    nextRewardBanner

                    todayCard

                    restrictedAppsCard

                    if let error = env.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, Theme.Space.m)
                .padding(.bottom, Theme.Space.xl)
            }
            .background(Theme.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text("settings.title"))
                }
            }
            .refreshable { await env.refresh() }
            .task { await env.refresh() }
            .sheet(isPresented: $isShowingSettings) { SettingsView() }
            .sheet(isPresented: $isShowingAppPicker) { AppSelectionView() }
        }
    }

    // MARK: - Sections

    private var nextRewardBanner: some View {
        let next = env.nextMilestone
        return HStack(spacing: Theme.Space.s) {
            Image(systemName: "arrow.up.forward.circle.fill")
                .foregroundStyle(Theme.activity)
                .accessibilityHidden(true)
            Text("dashboard.nextReward \(next.remainingAmount) \(next.rewardMinutes)")
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(Theme.activity.opacity(0.12), in: .capsule)
        .accessibilityElement(children: .combine)
    }

    private var todayCard: some View {
        CardSection(title: "dashboard.today") {
            StatRow(
                symbol: "figure.walk",
                label: "dashboard.steps",
                value: "\(env.ledger.activityAmount.formatted()) / \(env.nextMilestone.targetAmount.formatted())",
                tint: Theme.activity
            )
            StatRow(
                symbol: "plus.circle",
                label: "dashboard.earned",
                value: minutes(env.wallet.earnedSeconds),
                tint: Theme.earned
            )
            StatRow(
                symbol: "minus.circle",
                label: "dashboard.used",
                value: minutes(env.wallet.consumedSeconds),
                tint: Theme.locked,
                showsDivider: false
            )
        }
    }

    private var restrictedAppsCard: some View {
        CardSection(title: "dashboard.restrictedApps") {
            Button {
                isShowingAppPicker = true
            } label: {
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: env.state.hasRestrictedApps ? "lock.square.stack" : "square.dashed")
                        .foregroundStyle(env.state.hasRestrictedApps ? Theme.earned : .secondary)
                        .frame(width: 28)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(env.state.hasRestrictedApps
                             ? "dashboard.appsSelected \(env.state.restrictedItemCount)"
                             : "dashboard.noAppsSelected")
                            .font(.body)
                            .foregroundStyle(.primary)
                        if !env.state.hasRestrictedApps {
                            Text("dashboard.noAppsHint")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: Theme.Space.s)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Theme.Space.m)
                .frame(minHeight: Theme.minTouchTarget + 16)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("dashboard.manageApps"))
        }
    }

    private func minutes(_ seconds: Int) -> String {
        String(localized: "common.minutesValue \(seconds / 60)")
    }
}

#Preview {
    DashboardView()
        .environment(AppEnvironment(
            screenTime: MockScreenTimeService(status: .approved),
            health: MockHealthKitService(hasRequested: true, steps: 3_842)
        ))
}
