import SwiftUI

@main
struct EarnYourScreenTimeApp: App {
    @State private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .tint(Theme.earned)
                .onChange(of: scenePhase) { _, phase in
                    // The monitor extension may have spent credits while we were closed.
                    guard phase == .active else { return }
                    Task { await environment.refresh() }
                }
        }
    }
}
