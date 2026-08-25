import EarnDomain
import FamilyControls
import SwiftUI

/// Developer harness for authorization, app selection, and wallet states without walking.
/// Reachable from Settings › Developer.
struct SpikeView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var isPickerPresented = false
    @State private var selection = FamilyActivitySelection()
    @State private var errorMessage: String?
    @State private var isRequesting = false

    var body: some View {
        Form {
            statusSection
            appsSection
            walletSection

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("spike.title")
        .navigationBarTitleDisplayMode(.inline)
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
        .onChange(of: selection) { _, newValue in
            env.updateRestrictedSelection(newValue)
        }
        .onAppear {
            selection = env.screenTime.selection
            env.reload()
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section("spike.section.permissions") {
            LabeledContent("spike.screenTimeAccess", value: authorizationLabel)
            if !env.screenTime.authorizationStatus.isApproved {
                Button {
                    Task { await requestAuthorization() }
                } label: {
                    if isRequesting {
                        ProgressView()
                    } else {
                        Text("spike.grantAccess")
                    }
                }
                .disabled(isRequesting)
            }
            if !env.isAppGroupConfigured {
                Label("spike.appGroupMissing", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.activity)
            }
        }
    }

    private var appsSection: some View {
        Section("spike.section.restrictedApps") {
            LabeledContent("spike.selectedCount", value: "\(selection.itemCount)")
            Button("spike.chooseApps") { isPickerPresented = true }
                .disabled(!env.screenTime.authorizationStatus.isApproved)
        }
    }

    private var walletSection: some View {
        Section("spike.section.wallet") {
            LabeledContent("spike.available", value: minutes(env.wallet.availableSeconds))
            LabeledContent("spike.earned", value: minutes(env.wallet.earnedSeconds))
            LabeledContent("spike.used", value: minutes(env.wallet.consumedSeconds))
            LabeledContent("spike.state", value: env.isLocked
                ? localized("dashboard.state.locked")
                : localized("dashboard.state.available"))
            Button("settings.debugCredit") { env.grantDebugCredit(seconds: 300) }
            Button("settings.resetDay", role: .destructive) { env.resetToday() }
        }
    }

    // MARK: - Helpers

    private var authorizationLabel: String {
        let status = env.screenTime.authorizationStatus
        if status.isApproved { return localized("spike.auth.approved") }
        if status == .denied { return localized("spike.auth.denied") }
        return localized("spike.auth.notDetermined")
    }

    private func minutes(_ seconds: Int) -> String {
        String(localized: "common.minutesValue \(seconds / 60)", locale: env.appLanguage.locale)
    }

    private func requestAuthorization() async {
        isRequesting = true
        errorMessage = nil
        defer { isRequesting = false }
        do {
            try await env.screenTime.requestAuthorization()
        } catch {
            errorMessage = String(
                localized: "spike.auth.failed \(error.localizedDescription)",
                locale: env.appLanguage.locale
            )
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: env.appLanguage.locale)
    }
}

#Preview {
    NavigationStack {
        SpikeView()
    }
    .environment(AppEnvironment(
        screenTime: MockScreenTimeService(status: .approved),
        health: MockHealthKitService(hasRequested: true)
    ))
}
