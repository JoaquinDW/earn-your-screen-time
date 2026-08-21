import RevenueCatUI
import SwiftUI

/// Keeps RevenueCat Customer Center callbacks inside the monetization boundary.
struct SubscriptionCustomerCenterView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        CustomerCenterView()
            .onCustomerCenterRestoreCompleted { customerInfo in
                env.subscriptionManager.applyCustomerInfo(
                    customerInfo,
                    source: "customer center restore"
                )
            }
            .onCustomerCenterRestoreFailed { error in
                env.subscriptionManager.record(
                    error,
                    operation: "Customer Center restore"
                )
            }
            .task {
                await env.subscriptionManager.refresh()
            }
    }
}
