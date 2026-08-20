import FamilyControls
import SwiftUI

/// Both permissions, each explained before it is asked, each recoverable if denied (PRD §6).
struct PermissionsStep: View {
    let onFinish: () -> Void
    @Environment(AppEnvironment.self) private var env

    @State private var screenTimeState: RequestState = .idle
    @State private var healthState: RequestState = .idle

    enum RequestState: Equatable {
        case idle, requesting, granted, failed(String)
    }

    private var screenTimeGranted: Bool {
        env.screenTime.authorizationStatus.isApproved
    }

    private var canFinish: Bool { screenTimeGranted }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Text("onboarding.permissions.title")
                        .font(.largeTitle.bold())
                        .padding(.top, Theme.Space.l)

                    Text("onboarding.permissions.subtitle")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    PermissionCard(
                        symbol: "hourglass",
                        title: "onboarding.permission.screenTime.title",
                        explanation: "onboarding.permission.screenTime.why",
                        deniedHelp: "onboarding.permission.screenTime.denied",
                        state: screenTimeGranted ? .granted : screenTimeState,
                        action: requestScreenTime
                    )

                    PermissionCard(
                        symbol: "figure.walk",
                        title: "onboarding.permission.health.title",
                        explanation: "onboarding.permission.health.why",
                        deniedHelp: "onboarding.permission.health.denied",
                        state: env.health.hasRequestedAuthorization ? .granted : healthState,
                        action: requestHealth
                    )
                }
                .padding(.horizontal, Theme.Space.m)
            }

            VStack(spacing: Theme.Space.s) {
                Button(action: onFinish) {
                    Text("onboarding.start")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.earned)
                .disabled(!canFinish)

                if !canFinish {
                    Text("onboarding.screenTimeRequired")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.bottom, Theme.Space.m)
        }
    }

    private func requestScreenTime() {
        Task {
            screenTimeState = .requesting
            do {
                try await env.screenTime.requestAuthorization()
                screenTimeState = .granted
            } catch {
                screenTimeState = .failed(error.localizedDescription)
            }
        }
    }

    private func requestHealth() {
        Task {
            healthState = .requesting
            do {
                try await env.health.requestAuthorization()
                healthState = .granted
            } catch {
                healthState = .failed(error.localizedDescription)
            }
        }
    }
}

private struct PermissionCard: View {
    let symbol: String
    let title: LocalizedStringKey
    let explanation: LocalizedStringKey
    let deniedHelp: LocalizedStringKey
    let state: PermissionsStep.RequestState
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(Theme.earned)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                Text(title).font(.headline)

                Spacer()

                if state == .granted {
                    // Icon plus label: never colour alone.
                    Label("onboarding.permission.granted", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(Theme.earned)
                        .accessibilityLabel(Text("onboarding.permission.granted"))
                }
            }

            Text(explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch state {
            case .granted:
                EmptyView()
            case .requesting:
                ProgressView().frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget)
            case .failed(let message):
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Label(deniedHelp, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.activity)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("onboarding.permission.retry", action: action)
                        .buttonStyle(.bordered)
                }
            case .idle:
                Button(action: action) {
                    Text("onboarding.permission.allow").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.cornerRadius))
    }
}
