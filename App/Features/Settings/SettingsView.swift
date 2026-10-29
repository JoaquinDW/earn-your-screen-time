import EarnDomain
import SwiftUI

private enum SettingsDestination: Hashable {
    case apps
    case blocking
    #if DEBUG
    case spike
    #endif
}

/// Rule configuration (PRD §16) plus the developer tools for the remaining phases.
///
/// **Tier 3: no artwork.** Settings is where the identity has to hold up on typography, surface
/// and spacing alone — if it only looks like Earnit when there is an illustration on it, the
/// system is not doing its job. So this screen keeps native `Form` controls (a Stepper is a
/// Stepper; reimplementing one would be worse, not more designed) and changes only what it sits
/// on: forest rows on the night ground, eyebrow section headers, one cobalt accent.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var showsDoneButton = true
    var onNavigationDepthChange: ((Bool) -> Void)? = nil

    @State private var stepsRequired: Int = EarningRule.default.amountRequired
    @State private var rewardMinutes: Int = EarningRule.default.rewardMinutes
    @State private var dailyStepGoal = GoalRecommendationEngine.minimumGoal
    @State private var isShowingRuleChangeConfirm = false
    @State private var isShowingPaywall = false
    @State private var isShowingCustomerCenter = false
    @State private var isShowingWidgetOffer = false
    @State private var isShowingStrictRuleRefusal = false
    @State private var path: [SettingsDestination] = []

    private let stepOptions = [250, 500, 750, 1_000, 1_500, 2_000, 3_000]
    private let rewardOptions = [1, 2, 3, 5, 10, 15, 20]

    private var editedRule: EarningRule {
        EarningRule(source: .steps, amountRequired: stepsRequired, rewardSeconds: rewardMinutes * 60)
    }

    private var hasChanges: Bool { editedRule != env.ledger.rule }

    /// Deep-links straight to the write-a-review sheet on the app's own App Store page.
    private static let appStoreReviewURL = URL(
        string: "https://apps.apple.com/us/app/earn-screen-time-earnit/id6804905841?action=write-review"
    )!

    var body: some View {
        NavigationStack(path: $path) {
            Form {
              Group {
                Section {
                    Picker("settings.language", selection: languageBinding) {
                        ForEach(AppLanguage.allCases) { language in
                            languageLabel(language).tag(language)
                        }
                    }
                } header: {
                    sectionHeader("settings.language.section")
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
                            value: String(
                                localized: "\(dailyStepGoal.formatted(.number.locale(env.appLanguage.locale))) steps",
                                locale: env.appLanguage.locale
                            )
                        )
                    }
                    if dailyStepGoal != env.dailyStepGoal {
                        Button("Save daily goal") {
                            track("daily_goal_saved", ["previous_goal": .int(env.dailyStepGoal), "new_goal": .int(dailyStepGoal)])
                            env.updateDailyGoal(dailyStepGoal)
                        }
                    }
                } header: {
                    sectionHeader("Movement goal")
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
                    sectionHeader("settings.rule")
                } footer: {
                    Text("settings.rule.footer \(stepsRequired) \(rewardMinutes)")
                }

                if hasChanges {
                    Section {
                        Button("settings.saveRule") {
                            track("rule_save_tapped", ["steps": .int(stepsRequired), "minutes": .int(rewardMinutes)])
                            requestRuleChange()
                        }
                    } footer: {
                        Text("settings.rule.changeWarning")
                    }
                }

                Section {
                    NavigationLink("settings.apps", value: SettingsDestination.apps)
                } header: {
                    sectionHeader("settings.apps.section")
                } footer: {
                    Text("settings.apps.footer")
                }

                Section {
                    NavigationLink(value: SettingsDestination.blocking) {
                        LabeledContent("settings.blocking", value: blockingSummary)
                    }
                } footer: {
                    Text("settings.blocking.footer")
                }

                Section {
                    Toggle("settings.reminder.toggle", isOn: reminderEnabledBinding)
                    if env.dailyReminder.isEnabled {
                        DatePicker(
                            "settings.reminder.time",
                            selection: reminderTimeBinding,
                            displayedComponents: .hourAndMinute
                        )
                    }
                    if !env.hasWalletWidget {
                        Button("settings.widget.add") {
                            track("widget_offer_opened")
                            isShowingWidgetOffer = true
                        }
                    }
                } header: {
                    sectionHeader("settings.reminder.section")
                } footer: {
                    Text("settings.reminder.footer")
                }

                Section {
                    LabeledContent("settings.subscription.status", value: subscriptionStatusLabel)

                    if env.subscriptionManager.isPro,
                       env.subscriptionManager.isRevenueCatConfigured {
                        Button("settings.subscription.manage") {
                            track("subscription_manage_tapped")
                            isShowingCustomerCenter = true
                        }
                        if env.subscriptionManager.canUpgradeToLifetime {
                            Button("Switch to Lifetime") {
                                track("lifetime_upgrade_tapped")
                                isShowingPaywall = true
                            }
                        }
                    } else {
                        Button("settings.subscription.upgrade") {
                            track("subscription_upgrade_tapped")
                            isShowingPaywall = true
                        }
                    }
                } header: {
                    sectionHeader("settings.subscription.section")
                } footer: {
                    if env.subscriptionManager.hasLifetimeAccess,
                       env.subscriptionManager.hasActiveSubscription {
                        Text("Lifetime is active. If your subscription is still set to renew, cancel it in the App Store to avoid further charges.")
                    }
                }

                Section {
                    Button("settings.rateApp") {
                        env.analytics.track(.rateAppTapped)
                        openURL(SettingsView.appStoreReviewURL)
                    }
                }

                #if DEBUG
                Section {
                    LabeledContent("settings.screenTimeStatus", value: statusLabel)
                    LabeledContent("settings.monitoring", value: env.screenTime.isMonitoring
                        ? String(localized: "common.yes", locale: env.appLanguage.locale)
                        : String(localized: "common.no", locale: env.appLanguage.locale))
                    NavigationLink("settings.spike", value: SettingsDestination.spike)
                } header: {
                    sectionHeader("settings.developer")
                }

                Section {
                    Button {
                        isShowingPaywall = true
                    } label: {
                        Text(verbatim: "Debug: show Pro paywall")
                    }
                    Button("settings.debugCredit") { env.grantDebugCredit(seconds: 300) }
                    Button("settings.resetDay", role: .destructive) { env.resetToday() }
                    Button("settings.replayOnboarding", role: .destructive) { env.replayOnboarding() }
                    Button("Debug: replay push-ups intro") { env.replayPushupsIntro() }
                    Button("Debug: +5 min earned") { env.triggerDebugFeedback(.screenTimeEarned(minutes: 5)) }
                    Button("Debug: goal complete") { env.triggerDebugFeedback(.dailyGoalCompleted(minutes: 5)) }
                    Button("Debug: apps unlocked") { env.triggerDebugFeedback(.appUnlocked) }
                    Button("Debug: balance expired") { env.triggerDebugFeedback(.appLocked) }
                    Button("Debug: error") { env.triggerDebugFeedback(.error) }
                } header: {
                    sectionHeader("settings.debug")
                } footer: {
                    Text("settings.debug.footer")
                }
                #endif
              }
              .listRowBackground(Night.panel)
            }
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, Theme.Space.xxl, for: .scrollContent)
            .background(Night.ground.ignoresSafeArea())
            .settingsSurface()
            .tint(Night.cobalt)
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Night.ground, for: .navigationBar)
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .apps:
                    AppSelectionView()
                case .blocking:
                    BlockingPolicyView()
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
                Button("settings.rule.confirmApply") {
                    if env.updateRule(editedRule) {
                        track("rule_changed", ["steps": .int(stepsRequired), "minutes": .int(rewardMinutes)])
                    } else {
                        isShowingStrictRuleRefusal = true
                    }
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("settings.rule.confirmMessage")
            }
            .fullScreenCover(
                isPresented: $isShowingPaywall,
                onDismiss: {
                    env.setFeedbackPresentationSuspended(false, by: "settings.paywall")
                    if env.subscriptionManager.isPro, hasChanges {
                        isShowingRuleChangeConfirm = true
                    }
                },
                content: { ProPaywallView(source: .settings) }
            )
            .alert("strictMode.refusal.title", isPresented: $isShowingStrictRuleRefusal) {
                Button("common.close", role: .cancel) {
                    stepsRequired = env.ledger.rule.amountRequired
                    rewardMinutes = env.ledger.rule.rewardMinutes
                }
            } message: {
                Text("strictMode.refusal.rule")
            }
            .sheet(isPresented: $isShowingWidgetOffer) {
                WidgetOfferView(source: "settings")
            }
            .sheet(isPresented: $isShowingCustomerCenter, onDismiss: {
                env.setFeedbackPresentationSuspended(false, by: "settings.customerCenter")
            }) {
                SubscriptionCustomerCenterView()
            }
        }
        .onChange(of: path) { _, path in
            onNavigationDepthChange?(!path.isEmpty)
            // Four of five people who finished onboarding in 1.2.2 opened Settings within a
            // minute; the app list is the likeliest reason, and the one worth knowing about.
            if path.last == .apps { track("apps_opened") }
        }
        .onChange(of: isShowingRuleChangeConfirm) { _, isPresented in
            env.setFeedbackPresentationSuspended(isPresented, by: "settings.ruleConfirmation")
        }
        .onChange(of: isShowingPaywall) { _, isPresented in
            guard isPresented else { return }
            env.setFeedbackPresentationSuspended(true, by: "settings.paywall")
        }
        .onChange(of: isShowingCustomerCenter) { _, isPresented in
            guard isPresented else { return }
            env.setFeedbackPresentationSuspended(true, by: "settings.customerCenter")
        }
        .onDisappear {
            onNavigationDepthChange?(false)
        }
        .trackScreen("settings", analytics: env.analytics)
    }

    /// Section headers in the design's eyebrow rather than the system's grey caps — the one
    /// piece of Earnit's voice a settings screen gets to keep.
    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.sans(11, weight: .medium))
            .textCase(.uppercase)
            .kerning(1.9)
            .foregroundStyle(Night.textMuted)
            .padding(.bottom, 2)
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

    /// "Always", "09:00–18:00", plus "Strict" while strict mode runs.
    private var blockingSummary: String {
        let locale = env.appLanguage.locale
        var summary: String
        if let schedule = env.blockSchedule {
            let style = Date.FormatStyle.dateTime.hour().minute().locale(locale)
            let start = Calendar.current.date(bySettingHour: schedule.startMinute / 60, minute: schedule.startMinute % 60, second: 0, of: Date()) ?? Date()
            let end = Calendar.current.date(bySettingHour: schedule.endMinute / 60, minute: schedule.endMinute % 60, second: 0, of: Date()) ?? Date()
            summary = "\(start.formatted(style))–\(end.formatted(style))"
        } else {
            summary = String(localized: "settings.blocking.always", locale: locale)
        }
        if env.isStrictModeActive {
            summary += " · " + String(localized: "settings.blocking.strict", locale: locale)
        }
        return summary
    }

    private var subscriptionStatusLabel: String {
        switch env.subscriptionManager.status {
        case .unknown:
            String(localized: "subscription.status.checking", locale: env.appLanguage.locale)
        case .free:
            String(localized: "subscription.status.free", locale: env.appLanguage.locale)
        case .pro:
            String(localized: env.subscriptionManager.hasLifetimeAccess
                ? "Lifetime Pro" : "subscription.status.pro", locale: env.appLanguage.locale)
        }
    }

    /// Every language but "System" names itself, the way iOS Settings does: someone hunting
    /// for their own language recognises "Deutsch" without already reading the current one.
    @ViewBuilder
    private func languageLabel(_ language: AppLanguage) -> some View {
        if language == .korean {
            Text(verbatim: "한국어")
        } else if let identifier = language.localeIdentifier {
            let locale = Locale(identifier: identifier)
            Text(locale.localizedString(forIdentifier: identifier)?.capitalized(with: locale) ?? identifier)
        } else {
            Text("settings.language.system")
        }
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { env.appLanguage },
            set: {
                track("language_changed", ["language": .string($0.rawValue)])
                env.setAppLanguage($0)
            }
        )
    }

    private var hapticFeedbackBinding: Binding<Bool> {
        Binding(
            get: { env.hapticFeedbackEnabled },
            set: {
                track("haptics_toggled", ["enabled": .bool($0)])
                env.setHapticFeedbackEnabled($0)
            }
        )
    }

    /// Turning the reminder on is also the moment to ask for permission, for anyone who said
    /// "Not now" during onboarding.
    private var reminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { env.dailyReminder.isEnabled },
            set: { isEnabled in
                var preference = env.dailyReminder
                preference.isEnabled = isEnabled
                Task {
                    if isEnabled { _ = await env.requestNotificationPermission(source: "settings") }
                    await env.setDailyReminder(preference)
                }
            }
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                let preference = env.dailyReminder
                return Calendar.current.date(
                    bySettingHour: preference.hour,
                    minute: preference.minute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                var preference = env.dailyReminder
                preference.hour = components.hour ?? preference.hour
                preference.minute = components.minute ?? preference.minute
                Task { await env.setDailyReminder(preference) }
            }
        )
    }

    private func track(_ action: String, _ properties: AnalyticsProperties = [:]) {
        env.analytics.track(.settingsAction.withProperties(properties.merging(["action": .string(action)]) { $1 }))
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
