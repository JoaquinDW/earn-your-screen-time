import SwiftUI

struct HealthPermissionStep: View {
    let onContinue: (Int?) -> Void
    let onBack: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var isRequesting = false
    @State private var error: String?

    var body: some View {
        OnboardingScaffold(onBack: onBack) {
            Text("AUTOMATIC EARNING").eyebrowStyle(Theme.coralDeep)
            Text("Turn your steps into screen time.")
                .font(.serif(42))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Text("Earnit uses Apple Health to automatically convert your movement into screen-time credit.")
                .font(.sans(15))
                .foregroundStyle(Theme.muted)
                .padding(.top, 12)

            VStack(spacing: Theme.Space.l) {
                permissionNode(icon: "heart.fill", label: "Apple Health", color: Theme.coralDeep)
                Image(systemName: "arrow.down").foregroundStyle(Theme.muted).accessibilityHidden(true)
                permissionNode(icon: "figure.walk", label: "Your steps", color: Theme.coralDeep)
                Image(systemName: "arrow.down").foregroundStyle(Theme.muted).accessibilityHidden(true)
                permissionNode(icon: "timer", label: "Earned minutes", color: Theme.sageDeep)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.xl)

            Text("Health data stays in Apple Health and on your device.")
                .font(.sans(13.5))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .center)
            if let error {
                Text(error).font(.sans(13)).foregroundStyle(Theme.coralDeep).padding(.top, 8)
            }
        } action: {
            Button {
                connect()
            } label: {
                HStack {
                    if isRequesting { ProgressView().tint(Theme.paper) }
                    if isRequesting {
                        Text("Connecting")
                    } else {
                        Text("Connect Apple Health")
                    }
                }
            }
            .buttonStyle(.pill)
            .disabled(isRequesting)
        }
    }

    private func permissionNode(icon: String, label: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.1), in: .circle)
            Text(label).font(.serif(24))
        }
        .accessibilityElement(children: .combine)
    }

    private func connect() {
        guard !isRequesting else { return }
        isRequesting = true
        error = nil
        env.analytics.track(.healthKitRequested)
        Task {
            do {
                if !env.health.hasRequestedAuthorization {
                    try await env.health.requestAuthorization()
                }
                // HealthKit cannot reveal read denial; this event means the request completed.
                env.analytics.track(.healthKitGranted.withProperties(["read_status_verifiable": .bool(false)]))
                let average = try? await env.health.recentAverageSteps()
                onContinue(average ?? nil)
            } catch HealthKitError.unavailable {
                self.error = String(
                    localized: "health.error.unavailable",
                    locale: env.appLanguage.locale
                )
                isRequesting = false
            } catch {
                self.error = error.localizedDescription
                isRequesting = false
            }
        }
    }
}
