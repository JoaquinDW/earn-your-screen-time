import SwiftUI

/// Onboarding until it is done, then the dashboard.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if env.hasCompletedOnboarding {
                DashboardView()
            } else {
                OnboardingView()
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: env.hasCompletedOnboarding)
    }
}
