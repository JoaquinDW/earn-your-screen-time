import EarnDomain
import SwiftUI

private enum SettingsDestination: Hashable {
    case apps
    case subscription
    case spike
}

/// Rule configuration (PRD §16) plus the developer tools for the remaining phases.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var showsDoneButton = true
    var onNavigationDepthChange: ((Bool) -> Void)? = nil

    @State private var stepsRequired: Int = EarningRule.default.amountRequired
    @State private var rewardMinutes: Int = EarningRule.default.rewardMinutes
    @State private var isShowingRuleChangeConfirm = false
    @State private var isShowingPaywall = false
    @State private var path: [SettingsDestination] = []

    private let stepOptions = [250, 500, 750, 1_000, 1_500, 2_000, 3_000]
    private let rewardOptions = [1, 2, 3, 5, 10, 15, 20]

    private var editedRule: EarningRule {
        EarningRule(source: .steps, amountRequired: stepsRequired, rewardSeconds: rewardMinutes * 60)
    }

    private var hasChanges: Bool { editedRule != env.ledger.rule }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    Picker("settings.stepsRequired", selection: $stepsRequired) {
                        ForEach(stepOptions, id: \.self) { steps in
                            Text(steps.formatted()).tag(steps)
                        }
                    }
                    Picker("settings.reward", selection: $rewardMinutes) {
                        ForEach(rewardOptions, id: \.self) { minutes in
                            Text("common.minutesValue \(minutes)").tag(minutes)
                        }
                    }
                } header: {
                    Text("settings.rule")
                } footer: {
                    Text("settings.rule.footer \(stepsRequired) \(rewardMinutes)")
                }

                if hasChanges {
                    Section {
                        Button("settings.saveRule") {
                            requestRuleChange()
                        }
                    } footer: {
                        Text("settings.rule.changeWarning")
                    }
                }

                Section {
                    NavigationLink("settings.apps", value: SettingsDestination.apps)
                } header: {
                    Text("settings.apps.section")
                } footer: {
                    Text("settings.apps.footer")
                }

                Section("settings.subscription.section") {
                    LabeledContent("settings.subscription.status", value: subscriptionStatusLabel)

                    if env.subscriptionManager.isPro,
                       env.subscriptionManager.isRevenueCatConfigured {
                        NavigationLink(
                            "settings.subscription.manage",
                            value: SettingsDestination.subscription
                        )
                    } else {
                        Button("settings.subscription.upgrade") { isShowingPaywall = true }
                    }
                }

                Section("settings.developer") {
                    LabeledContent("settings.screenTimeStatus", value: statusLabel)
                    LabeledContent("settings.monitoring", value: env.screenTime.isMonitoring
                        ? String(localized: "common.yes")
                        : String(localized: "common.no"))
                    NavigationLink("settings.spike", value: SettingsDestination.spike)
                }

                Section {
                    Button("settings.debugCredit") { env.grantDebugCredit(seconds: 300) }
                    Button("settings.resetDay", role: .destructive) { env.resetToday() }
                } header: {
                    Text("settings.debug")
                } footer: {
                    Text("settings.debug.footer")
                }
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .tint(Theme.coralDeep)
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .apps:
                    AppSelectionView()
                case .subscription:
                    SubscriptionCustomerCenterView()
                case .spike:
                    SpikeView()
                }
            }
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.done") { dismiss() }
                    }
                }
            }
            .onAppear {
                stepsRequired = env.ledger.rule.amountRequired
                rewardMinutes = env.ledger.rule.rewardMinutes
            }
            .confirmationDialog(
                "settings.rule.confirmTitle",
                isPresented: $isShowingRuleChangeConfirm,
                titleVisibility: .visible
            ) {
                Button("settings.rule.confirmApply") { env.updateRule(editedRule) }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("settings.rule.confirmMessage")
            }
            .fullScreenCover(
                isPresented: $isShowingPaywall,
                onDismiss: {
                    if env.subscriptionManager.isPro, hasChanges {
                        isShowingRuleChangeConfirm = true
                    }
                },
                content: { ProPaywallView() }
            )
        }
        .onChange(of: path) { _, path in
            onNavigationDepthChange?(!path.isEmpty)
        }
        .onDisappear {
            onNavigationDepthChange?(false)
        }
    }

    private var statusLabel: String {
        let status = env.screenTime.authorizationStatus
        if status.isApproved { return String(localized: "spike.auth.approved") }
        if status == .denied { return String(localized: "spike.auth.denied") }
        return String(localized: "spike.auth.notDetermined")
    }

    private var subscriptionStatusLabel: String {
        switch env.subscriptionManager.status {
        case .unknown:
            String(localized: "subscription.status.checking")
        case .free:
            String(localized: "subscription.status.free")
        case .pro:
            String(localized: "subscription.status.pro")
        }
    }

    private func requestRuleChange() {
        switch env.subscriptionManager.status {
        case .pro:
            isShowingRuleChangeConfirm = true
        case .free:
            isShowingPaywall = true
        case .unknown:
            Task {
                await env.subscriptionManager.refresh()
                if env.subscriptionManager.isPro {
                    isShowingRuleChangeConfirm = true
                } else {
                    isShowingPaywall = true
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppEnvironment(
            screenTime: MockScreenTimeService(status: .approved),
            health: MockHealthKitService(hasRequested: true)
        ))
}
