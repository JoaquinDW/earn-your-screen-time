import EarnDomain
import SwiftUI

private enum SettingsDestination: Hashable {
    case apps
    #if DEBUG
    case spike
    #endif
}

/// Rule configuration (PRD §16) plus the developer tools for the remaining phases.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var showsDoneButton = true
    var onNavigationDepthChange: ((Bool) -> Void)? = nil

    @State private var stepsRequired: Int = EarningRule.default.amountRequired
    @State private var rewardMinutes: Int = EarningRule.default.rewardMinutes
    @State private var dailyStepGoal = GoalRecommendationEngine.minimumGoal
    @State private var isShowingRuleChangeConfirm = false
    @State private var isShowingPaywall = false
    @State private var isShowingCustomerCenter = false
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
                    Picker("settings.language", selection: languageBinding) {
                        Text("settings.language.system").tag(AppLanguage.system)
                        Text("settings.language.english").tag(AppLanguage.english)
                        Text("settings.language.spanish").tag(AppLanguage.spanish)
                    }
                } header: {
                    Text("settings.language.section")
                } footer: {
                    Text("settings.language.footer")
                }

                Section {
                    Toggle("settings.haptics", isOn: hapticFeedbackBinding)
                } footer: {
                    Text("settings.haptics.footer")
                }

                Section {
                    Stepper(value: $dailyStepGoal, in: 2_000...20_000, step: 500) {
                        LabeledContent(
                            "Daily movement goal",
                            value: "\(dailyStepGoal.formatted(.number.locale(env.appLanguage.locale))) steps"
                        )
                    }
                    if dailyStepGoal != env.dailyStepGoal {
                        Button("Save daily goal") { env.updateDailyGoal(dailyStepGoal) }
                    }
                } header: {
                    Text("Movement goal")
                } footer: {
                    Text("Your goal tracks daily progress. It does not change how quickly you earn minutes.")
                }

                Section {
                    Picker("settings.stepsRequired", selection: $stepsRequired) {
                        ForEach(stepOptions, id: \.self) { steps in
                            Text(steps.formatted(.number.locale(env.appLanguage.locale))).tag(steps)
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
                        Button("settings.subscription.manage") {
                            isShowingCustomerCenter = true
                        }
                    } else {
                        Button("settings.subscription.upgrade") { isShowingPaywall = true }
                    }
                }

                #if DEBUG
                Section("settings.developer") {
                    LabeledContent("settings.screenTimeStatus", value: statusLabel)
                    LabeledContent("settings.monitoring", value: env.screenTime.isMonitoring
                        ? String(localized: "common.yes", locale: env.appLanguage.locale)
                        : String(localized: "common.no", locale: env.appLanguage.locale))
                    NavigationLink("settings.spike", value: SettingsDestination.spike)
                }

                Section {
                    Button("settings.debugCredit") { env.grantDebugCredit(seconds: 300) }
                    Button("settings.resetDay", role: .destructive) { env.resetToday() }
                    Button("Debug: +5 min earned") { env.triggerDebugFeedback(.screenTimeEarned(minutes: 5)) }
                    Button("Debug: goal complete") { env.triggerDebugFeedback(.dailyGoalCompleted(minutes: 5)) }
                    Button("Debug: apps unlocked") { env.triggerDebugFeedback(.appUnlocked) }
                    Button("Debug: balance expired") { env.triggerDebugFeedback(.appLocked) }
                    Button("Debug: error") { env.triggerDebugFeedback(.error) }
                } header: {
                    Text("settings.debug")
                } footer: {
                    Text("settings.debug.footer")
                }
                #endif
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
                #if DEBUG
                case .spike:
                    SpikeView()
                #endif
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
                dailyStepGoal = env.dailyStepGoal
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
            .sheet(isPresented: $isShowingCustomerCenter) {
                SubscriptionCustomerCenterView()
            }
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
        if status.isApproved {
            return String(localized: "spike.auth.approved", locale: env.appLanguage.locale)
        }
        if status == .denied {
            return String(localized: "spike.auth.denied", locale: env.appLanguage.locale)
        }
        return String(localized: "spike.auth.notDetermined", locale: env.appLanguage.locale)
    }

    private var subscriptionStatusLabel: String {
        switch env.subscriptionManager.status {
        case .unknown:
            String(localized: "subscription.status.checking", locale: env.appLanguage.locale)
        case .free:
            String(localized: "subscription.status.free", locale: env.appLanguage.locale)
        case .pro:
            String(localized: "subscription.status.pro", locale: env.appLanguage.locale)
        }
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { env.appLanguage },
            set: { env.setAppLanguage($0) }
        )
    }

    private var hapticFeedbackBinding: Binding<Bool> {
        Binding(
            get: { env.hapticFeedbackEnabled },
            set: { env.setHapticFeedbackEnabled($0) }
        )
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

#Preview("Settings - English") {
    SettingsView()
        .environment(AppEnvironment(
            screenTime: MockScreenTimeService(status: .approved),
            health: MockHealthKitService(hasRequested: true),
            appLanguage: .english
        ))
        .environment(\.locale, Locale(identifier: "en"))
}

#Preview("Settings - Spanish") {
    SettingsView()
        .environment(AppEnvironment(
            screenTime: MockScreenTimeService(status: .approved),
            health: MockHealthKitService(hasRequested: true),
            appLanguage: .spanish
        ))
        .environment(\.locale, Locale(identifier: "es"))
}
