import SwiftUI

@main
struct EarnYourScreenTimeApp: App {
    @State private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            SpikeView()
                .environment(environment)
                .onChange(of: scenePhase) { _, phase in
                    // The monitor extension may have changed the balance while we were closed.
                    if phase == .active { environment.refresh() }
                }
        }
    }
}
