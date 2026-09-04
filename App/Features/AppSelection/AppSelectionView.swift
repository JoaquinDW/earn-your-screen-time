import FamilyControls
import SwiftUI

/// The apps whose minutes come out of the wallet, outside of onboarding.
///
/// Apple's picker is the only way to choose them, and the tokens it returns are opaque by
/// design (PRD §27) — so this screen frames the picker rather than replacing it.
struct AppSelectionView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var showsDoneButton = true

    @State private var selection = FamilyActivitySelection()
    @State private var isPickerPresented = false

    private var isApproved: Bool { env.screenTime.authorizationStatus.isApproved }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SerifHeadline(
                upright: "appSelection.title",
                italic: "appSelection.title.emphasis",
                size: 38
            )

            Text("appSelection.explanation")
                .font(.sans(14.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300, alignment: .leading)
                .padding(.top, 14)
                .padding(.bottom, 22)

            ScrollView {
                VStack(spacing: 0) {
                    RestrictedAppsList(selection: $selection)
                    ChooseAppsRow(count: selection.itemCount) { isPickerPresented = true }
                        .disabled(!isApproved)
                    Hairline()
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            if !isApproved {
                Text("appSelection.needsAuthorization")
                    .font(.sans(13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Space.m)
            }

            Spacer(minLength: 20)

            Text("appSelection.count \(selection.itemCount)")
                .font(.sans(13))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)

            if showsDoneButton {
                Button("common.done") { dismiss() }
                    .buttonStyle(.pill)
            }
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.xl)
        .padding(.bottom, Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Theme.ink)
        .background(Night.ground.ignoresSafeArea())
        .restrictedAppSelectionGate(
            isPickerPresented: $isPickerPresented,
            selection: $selection
        )
        .onAppear { selection = env.screenTime.selection }
    }
}

#Preview {
    AppSelectionView()
        .environment(AppEnvironment(
            screenTime: MockScreenTimeService(status: .approved),
            health: MockHealthKitService()
        ))
}
