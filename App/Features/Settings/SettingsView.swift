import EarnDomain
import SwiftUI

/// Rule configuration (PRD §16) plus the developer tools for the remaining phases.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var stepsRequired: Int = EarningRule.default.amountRequired
    @State private var rewardMinutes: Int = EarningRule.default.rewardMinutes
    @State private var isShowingRuleChangeConfirm = false

    private let stepOptions = [250, 500, 750, 1_000, 1_500, 2_000, 3_000]
    private let rewardOptions = [1, 2, 3, 5, 10, 15, 20]

    private var editedRule: EarningRule {
        EarningRule(source: .steps, amountRequired: stepsRequired, rewardSeconds: rewardMinutes * 60)
    }

    private var hasChanges: Bool { editedRule != env.ledger.rule }

    var body: some View {
        NavigationStack {
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
                        Button("settings.saveRule") { isShowingRuleChangeConfirm = true }
                    } footer: {
                        Text("settings.rule.changeWarning")
                    }
                }

                Section("settings.developer") {
                    LabeledContent("settings.screenTimeStatus", value: statusLabel)
                    LabeledContent("settings.monitoring", value: env.screenTime.isMonitoring
                        ? String(localized: "common.yes")
                        : String(localized: "common.no"))
                    NavigationLink("settings.spike") { SpikeView() }
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
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
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
        }
    }

    private var statusLabel: String {
        let status = env.screenTime.authorizationStatus
        if status.isApproved { return String(localized: "spike.auth.approved") }
        if status == .denied { return String(localized: "spike.auth.denied") }
        return String(localized: "spike.auth.notDetermined")
    }
}

#Preview {
    SettingsView()
        .environment(AppEnvironment(
            screenTime: MockScreenTimeService(status: .approved),
            health: MockHealthKitService(hasRequested: true)
        ))
}
