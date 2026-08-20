import EarnDomain
import FamilyControls
import SwiftUI

/// Phase 1 harness: prove authorization → picker → shield → unshield on a real iPhone.
///
/// This is intentionally a plain, unpolished screen. The product UI (PRD §15/§28) comes later,
/// once the blocking loop is verified on hardware.
struct SpikeView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var isPickerPresented = false
    @State private var selection = FamilyActivitySelection()
    @State private var errorMessage: String?
    @State private var isRequesting = false

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                appsSection
                walletSection
                shieldSection
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("spike.title")
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
            .onChange(of: selection) { _, newValue in
                env.screenTime.selection = newValue
                env.refresh()
            }
            .onAppear {
                selection = env.screenTime.selection
                env.refresh()
            }
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
                    .foregroundStyle(.orange)
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
            LabeledContent("spike.available", value: minutes(env.state.ledger.wallet.availableSeconds))
            LabeledContent("spike.earned", value: minutes(env.state.ledger.wallet.earnedSeconds))
            LabeledContent("spike.used", value: minutes(env.state.ledger.wallet.consumedSeconds))
            LabeledContent("spike.state", value: env.state.ledger.restrictionState == .locked
                ? String(localized: "spike.state.locked")
                : String(localized: "spike.state.available"))
            Button("spike.addFiveMinutes") { env.grantDebugCredit(seconds: 300) }
            Button("spike.resetDay", role: .destructive) { env.resetToday() }
        }
    }

    private var shieldSection: some View {
        Section {
            Button("spike.blockNow") {
                env.screenTime.shieldNow()
                env.refresh()
            }
            Button("spike.unblockNow") {
                env.screenTime.unshieldNow()
                env.refresh()
            }
        } header: {
            Text("spike.section.manualShield")
        } footer: {
            Text("spike.manualShieldHint")
        }
        .disabled(selection.isEmpty)
    }

    // MARK: - Helpers

    private var authorizationLabel: String {
        let status = env.screenTime.authorizationStatus
        if status.isApproved { return String(localized: "spike.auth.approved") }
        if status == .denied { return String(localized: "spike.auth.denied") }
        return String(localized: "spike.auth.notDetermined")
    }

    private func minutes(_ seconds: Int) -> String {
        String(localized: "spike.minutesValue \(seconds / 60)")
    }

    private func requestAuthorization() async {
        isRequesting = true
        errorMessage = nil
        defer { isRequesting = false }
        do {
            try await env.screenTime.requestAuthorization()
        } catch {
            errorMessage = String(localized: "spike.auth.failed \(error.localizedDescription)")
        }
    }
}

#Preview {
    SpikeView()
        .environment(AppEnvironment(screenTime: MockScreenTimeService(status: .approved)))
}
