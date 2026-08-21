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

    private var isApproved: Bool { env.screenTime.authorizationStatus.isApproved }
    private var canContinue: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        !selection.isEmpty
        #endif
    }

    var body: some View {
        OnboardingScaffold(onBack: onBack) {
            Text("BUILD YOUR PLAN").eyebrowStyle(Theme.coralDeep)
            Text("Which apps should you earn?")
                .font(.serif(41))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Text("Pick the apps that steal more time than you would like.")
                .font(.sans(15))
                .foregroundStyle(Theme.muted)
                .padding(.top, 12)

            if isApproved {
                VStack(spacing: 0) {
                    RestrictedAppsList(selection: $selection)
                    ChooseAppsRow(count: selection.itemCount) { isPickerPresented = true }
                    Hairline()
                }
                .padding(.top, Theme.Space.m)
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack(spacing: Theme.Space.m) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Theme.sageDeep)
                            .frame(width: 52, height: 52)
                            .background(Theme.sageLight, in: .circle)
                        Text("To build your plan, Earn needs Screen Time access to show Apple’s app picker.")
                            .font(.sans(15, weight: .semibold))
                    }
                    Text("Your app activity stays private. Earn only stores Apple’s opaque selections on this device.")
                        .font(.sans(13.5))
                        .foregroundStyle(Theme.muted)
                    Button {
                        requestAuthorization()
                    } label: {
                        HStack {
                            if isRequesting { ProgressView().tint(Theme.paper) }
                            Text(isRequesting ? "Requesting access" : "Enable Screen Time")
                        }
                    }
                    .buttonStyle(.pill(.sage))
                    .disabled(isRequesting)
                    if let error {
                        Text(error)
                            .font(.sans(13))
                            .foregroundStyle(Theme.coralDeep)
                    }
                }
                .padding(.top, Theme.Space.l)
            }
        } action: {
            Button("Continue") {
                env.analytics.track(.appsSelected.withProperties(["count": .int(selection.itemCount)]))
                onContinue()
            }
            .buttonStyle(.pill)
            .disabled(!canContinue)
        }
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
        .onAppear { selection = env.screenTime.selection }
        .onChange(of: selection) { _, updated in env.updateRestrictedSelection(updated) }
    }

    private func requestAuthorization() {
        guard !isRequesting else { return }
        isRequesting = true
        error = nil
        env.analytics.track(.familyControlsRequested)
        Task {
            defer { isRequesting = false }
            do {
                try await env.screenTime.requestAuthorization()
                env.analytics.track(.familyControlsGranted)
                isPickerPresented = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
