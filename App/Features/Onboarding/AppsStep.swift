import FamilyControls
import SwiftUI

struct AppsStep: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var selection = FamilyActivitySelection()
    @State private var isPickerPresented = false
    @State private var isRequesting = false
    @State private var error: String?
    @State private var denial: ScreenTimeDenial?
    @State private var attempts = 0

    private var isApproved: Bool { env.screenTime.authorizationStatus.isApproved }
    private var canContinue: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        !selection.isEmpty
        #endif
    }

    var body: some View {
        OnboardingScaffold(
            onBack: onBack,
            progress: Double(OnboardingView.Route.apps.progress) / Double(OnboardingView.Route.progressCount)
        ) {
            Text("Which apps should stay paused?")
                .font(.serif(41))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if isApproved {
                VStack(spacing: 0) {
                    RestrictedAppsList(selection: $selection)
                    ChooseAppsRow(count: selection.itemCount) { isPickerPresented = true }
                    Hairline()
                }
                .padding(.top, Theme.Space.l)
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack(spacing: Theme.Space.m) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Theme.sageDeep)
                            .frame(width: 52, height: 52)
                            .background(Theme.sageLight, in: .circle)
                        Text("To build your plan, Earnit needs Screen Time access to show Apple’s app picker.")
                            .font(.sans(15, weight: .semibold))
                    }
                    Text("Your app activity stays private. Earnit only stores Apple’s opaque selections on this device.")
                        .font(.sans(13.5))
                        .foregroundStyle(Theme.muted)
                    if let denial {
                        denialRecovery(denial)
                    } else if let error {
                        Text(error)
                            .font(.sans(13))
                            .foregroundStyle(Theme.coralDeep)
                    }
                }
                .padding(.top, Theme.Space.l)
            }
        } action: {
            if isApproved {
                Button("Continue") {
                    env.analytics.track(.appsSelected.withProperties(["count": .int(selection.itemCount)]))
                    onContinue()
                }
                .buttonStyle(.pill)
                .disabled(!canContinue)
            } else {
                Button {
                    requestAuthorization()
                } label: {
                    HStack {
                        if isRequesting { ProgressView().tint(Color.white) }
                        if isRequesting {
                            Text("Requesting access")
                        } else if denial == nil {
                            Text("Enable Screen Time")
                        } else {
                            Text("Try again")
                        }
                    }
                }
                .buttonStyle(.pill)
                .disabled(isRequesting)
                if denial?.needsSettings == true {
                    Button("Open Settings") {
                        env.analytics.track(.familyControlsDenied.withProperties([
                            "reason": .string(denial?.rawValue ?? "unknown"),
                            "action": .string("open_settings")
                        ]))
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.quiet)
                }
            }
        }
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
        .onAppear { selection = env.screenTime.selection }
        .onChange(of: selection) { _, updated in env.updateRestrictedSelection(updated) }
    }

    private func requestAuthorization() {
        guard !isRequesting else { return }
        isRequesting = true
        error = nil
        env.analytics.track(.familyControlsRequested.withProperties([
            "attempt": .int(attempts + 1)
        ]))
        attempts += 1
        // The onboarding-funnel name for the same moment, so the activation funnel reads
        // end to end without joining two differently-named events.
        env.analytics.track(.onboardingScreenTimePermissionRequested)
        Task {
            defer { isRequesting = false }
            do {
                try await env.screenTime.requestAuthorization()
                env.analytics.track(.familyControlsGranted.withProperties([
                    "attempt": .int(attempts)
                ]))
                denial = nil
                isPickerPresented = true
            } catch {
                // A refusal used to leave only Apple's error string, and the one way out was
                // Back — which sent people round the whole flow again. Say what happened and
                // how to get past it, right here.
                let reason = ScreenTimeDenial(error)
                denial = reason
                self.error = error.localizedDescription
                env.analytics.track(.familyControlsDenied.withProperties([
                    "reason": .string(reason.rawValue),
                    "attempt": .int(attempts)
                ]))
            }
        }
    }

    private func denialRecovery(_ denial: ScreenTimeDenial) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(denial.title)
                .font(.sans(15, weight: .bold))
                .foregroundStyle(Theme.coralDeep)
            Text(denial.guidance)
                .font(.sans(13.5))
                .foregroundStyle(Night.textSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Night.panel, in: .rect(cornerRadius: Night.panelRadius))
        .accessibilityElement(children: .combine)
    }
}

/// Why Screen Time access did not come through, in terms of what the person can do next.
private enum ScreenTimeDenial: String {
    case declined
    case needsPasscode = "needs_passcode"
    case restricted
    case network
    case unavailable
    case other

    init(_ error: Error) {
        guard let error = error as? FamilyControlsError else {
            self = .other
            return
        }
        switch error {
        case .authorizationCanceled: self = .declined
        case .authenticationMethodUnavailable: self = .needsPasscode
        case .restricted, .invalidAccountType, .authorizationConflict: self = .restricted
        case .networkError: self = .network
        case .unavailable: self = .unavailable
        default: self = .other
        }
    }

    /// The system prompt can be shown again for every case but these, which Settings must fix.
    var needsSettings: Bool { self == .needsPasscode || self == .restricted }

    var title: LocalizedStringKey {
        switch self {
        case .declined: "Screen Time access wasn't allowed"
        case .needsPasscode: "Your iPhone needs a passcode"
        case .restricted: "Screen Time is restricted on this iPhone"
        case .network: "Couldn't reach Apple"
        case .unavailable, .other: "Screen Time access didn't go through"
        }
    }

    var guidance: LocalizedStringKey {
        switch self {
        case .declined:
            "Earnit can only pause apps with it. Tap Try again and choose Continue, then confirm with Face ID or your passcode."
        case .needsPasscode:
            "Apple only grants Screen Time access on a device with a passcode. Set one in Settings, then come back and try again."
        case .restricted:
            "Another Screen Time setup or a parental restriction is blocking access. Check Settings › Screen Time, then try again."
        case .network:
            "Apple checks this request online. Connect to the internet and tap Try again."
        case .unavailable, .other:
            "Tap Try again. If it keeps failing, restart your iPhone and come back — your answers are saved."
        }
    }
}
