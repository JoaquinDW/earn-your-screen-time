import FamilyControls
import SwiftUI

/// Apple's own picker. The tokens it returns are opaque by design — we store them and never
/// try to resolve which apps they are (PRD §27).
struct AppSelectionView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var selection = FamilyActivitySelection()
    @State private var isPickerPresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Space.l) {
                Image(systemName: "hand.raised.app")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Theme.earned)
                    .accessibilityHidden(true)
                    .padding(.top, Theme.Space.xl)

                Text("appSelection.explanation")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Space.l)

                Text("appSelection.count \(selection.itemCount)")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()

                Button {
                    isPickerPresented = true
                } label: {
                    Text(selection.isEmpty ? "appSelection.choose" : "appSelection.change")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.earned)
                .padding(.horizontal, Theme.Space.l)
                .disabled(!env.screenTime.authorizationStatus.isApproved)

                if !env.screenTime.authorizationStatus.isApproved {
                    Label("appSelection.needsAuthorization", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Space.l)
                }

                Spacer()
            }
            .background(Theme.background)
            .navigationTitle("appSelection.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
            .onAppear { selection = env.screenTime.selection }
            .onChange(of: selection) { _, newValue in
                env.screenTime.selection = newValue
                env.reload()
            }
        }
    }
}
