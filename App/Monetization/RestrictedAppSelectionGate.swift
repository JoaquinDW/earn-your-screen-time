import FamilyControls
import SwiftUI

private struct RestrictedAppSelectionGate: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Binding var isPickerPresented: Bool
    @Binding var selection: FamilyActivitySelection

    @State private var pendingSelection: FamilyActivitySelection?
    @State private var isPaywallPresented = false

    func body(content: Content) -> some View {
        content
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
            .fullScreenCover(
                isPresented: $isPaywallPresented,
                onDismiss: {
                    if !env.subscriptionManager.isPro { pendingSelection = nil }
                },
                content: { ProPaywallView() }
            )
            .onChange(of: selection) { _, updated in
                handle(updated)
            }
            .onChange(of: env.subscriptionManager.status) { _, status in
                resolvePendingSelection(for: status)
            }
    }

    private func handle(_ updated: FamilyActivitySelection) {
        let savedSelection = env.screenTime.selection

        // Loading a previously saved selection is not a new selection attempt.
        guard updated != savedSelection else { return }

        if env.featureAccess.allowsRestrictedSelection(count: updated.itemCount) {
            pendingSelection = nil
            save(updated)
            return
        }

        pendingSelection = updated
        selection = savedSelection

        switch env.subscriptionManager.status {
        case .free:
            presentPaywallAfterPicker()
        case .pro:
            save(updated)
            pendingSelection = nil
        case .unknown:
            Task {
                await env.subscriptionManager.refresh()
                if env.subscriptionManager.status == .unknown {
                    presentPaywallAfterPicker()
                }
            }
        }
    }

    private func resolvePendingSelection(for status: SubscriptionStatus) {
        guard let pendingSelection else { return }

        switch status {
        case .pro:
            selection = pendingSelection
            save(pendingSelection)
            self.pendingSelection = nil
        case .free:
            presentPaywallAfterPicker()
        case .unknown:
            break
        }
    }

    private func save(_ updated: FamilyActivitySelection) {
        env.updateRestrictedSelection(updated)
    }

    private func presentPaywallAfterPicker() {
        isPickerPresented = false
        Task { @MainActor in
            await Task.yield()
            isPaywallPresented = true
        }
    }
}

extension View {
    func restrictedAppSelectionGate(
        isPickerPresented: Binding<Bool>,
        selection: Binding<FamilyActivitySelection>
    ) -> some View {
        modifier(RestrictedAppSelectionGate(
            isPickerPresented: isPickerPresented,
            selection: selection
        ))
    }
}
