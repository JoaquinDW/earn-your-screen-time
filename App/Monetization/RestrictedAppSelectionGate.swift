import FamilyControls
import SwiftUI

private struct RestrictedAppSelectionGate: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Binding var isPickerPresented: Bool
    @Binding var selection: FamilyActivitySelection

    @State private var pendingSelection: FamilyActivitySelection?
    @State private var pendingRemoval: FamilyActivitySelection?
    @State private var isRemovalPromptPresented = false
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
            .sheet(
                isPresented: $isRemovalPromptPresented,
                onDismiss: { pendingRemoval = nil }
            ) {
                AppRemovalReflectionSheet(
                    onKeepProtected: keepProtected,
                    onConfirmRemoval: confirmRemoval
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
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

        if removesItems(from: savedSelection, in: updated) {
            pendingRemoval = updated
            selection = savedSelection
            presentRemovalPromptAfterPicker()
            return
        }

        process(updated)
    }

    private func process(_ updated: FamilyActivitySelection) {
        if env.featureAccess.allowsRestrictedSelection(count: updated.itemCount) {
            pendingSelection = nil
            save(updated)
            return
        }

        pendingSelection = updated
        selection = env.screenTime.selection

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

    private func removesItems(
        from saved: FamilyActivitySelection,
        in updated: FamilyActivitySelection
    ) -> Bool {
        !saved.applicationTokens.isSubset(of: updated.applicationTokens)
            || !saved.categoryTokens.isSubset(of: updated.categoryTokens)
            || !saved.webDomainTokens.isSubset(of: updated.webDomainTokens)
    }

    private func keepProtected() {
        pendingRemoval = nil
        isRemovalPromptPresented = false
    }

    private func confirmRemoval() {
        guard let updated = pendingRemoval else { return }
        pendingRemoval = nil
        isRemovalPromptPresented = false

        Task { @MainActor in
            await Task.yield()
            selection = updated
            process(updated)
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

    private func presentRemovalPromptAfterPicker() {
        isPickerPresented = false
        Task { @MainActor in
            await Task.yield()
            guard pendingRemoval != nil else { return }
            isRemovalPromptPresented = true
        }
    }
}

private struct AppRemovalReflectionSheet: View {
    let onKeepProtected: () -> Void
    let onConfirmRemoval: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Night.cobaltText)
                .frame(width: 48, height: 48)
                .background(Night.cobaltWash, in: .circle)
                .accessibilityHidden(true)

            Text("appSelection.removal.title")
                .font(.serif(30))
                .foregroundStyle(Night.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.l)

            Text("appSelection.removal.message")
                .font(.sans(15))
                .foregroundStyle(Night.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.s)

            Spacer(minLength: Theme.Space.l)

            Button("appSelection.removal.keep", action: onKeepProtected)
                .buttonStyle(.nightPill)

            Button("appSelection.removal.confirm", action: onConfirmRemoval)
                .buttonStyle(.quietLink)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.l)
        .padding(.bottom, Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Night.ground.ignoresSafeArea())
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
