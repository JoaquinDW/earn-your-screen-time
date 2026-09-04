import SwiftUI

@main
struct EarnYourScreenTimeApp: App {
    @State private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(\.locale, environment.appLanguage.locale)
                .tint(Night.cobalt)
                .task { environment.synchronizeLiveActivity() }
                .onOpenURL { environment.handleDeepLink($0) }
                .onChange(of: scenePhase) { _, phase in
                    // The monitor extension may have spent credits while we were closed.
                    guard phase == .active else { return }
                    Task {
                        await environment.refreshAfterBecomingActive()
                        await environment.subscriptionManager.refresh()
                    }
                }
        }
    }
}
