import SwiftUI

/// Offers the Home Screen widget, then says how to add it — iOS has no way to add one for you.
///
/// The pattern is the one BePresent, Bend and Duolingo use: one screen, the widget itself as the
/// picture (showing this person's real number, not a mock-up), one action, and a way out. After
/// "Add the widget" the same sheet becomes the three steps, as Moonlitt and One Year Journal do,
/// so nobody has to remember instructions read on a screen they already closed.
struct WidgetOfferView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    /// Where the offer was opened from, for `widget_prompt` events.
    let source: String
    @State private var isShowingSteps = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    Text(isShowingSteps ? "Add Earnit to your Home Screen" : "Keep your minutes on your Home Screen")
                        .font(.serif(34, relativeTo: .largeTitle))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if isShowingSteps {
                        steps
                    } else {
                        Text("See what's ready to spend and how far the next minutes are, without opening the app.")
                            .font(.sans(15))
                            .foregroundStyle(Night.textSoft)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        preview
                            .padding(.top, Theme.Space.m)
                    }
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.top, Theme.Space.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 2) {
                if isShowingSteps {
                    Button("Done") {
                        track("done")
                        dismiss()
                    }
                    .buttonStyle(.pill)
                } else {
                    Button("Add the widget") {
                        track("add_tapped")
                        withAnimation(.snappy) { isShowingSteps = true }
                    }
                    .buttonStyle(.pill)
                    Button("Not now") {
                        track("dismissed")
                        dismiss()
                    }
                    .buttonStyle(.quiet)
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.vertical, Theme.Space.s)
        }
        .foregroundStyle(Night.text)
        .background(Night.ground.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .onAppear { track("viewed") }
    }

    /// The real widget view, fed this person's numbers, at the small widget's size.
    private var preview: some View {
        let entry = EarnWalletEntry.load()
        return EarnWalletWidgetView(entry: entry, family: .systemSmall)
            .frame(width: 170, height: 170)
            .background { EarnWalletBackground(entry: entry) }
            .clipShape(.rect(cornerRadius: 26))
            .overlay { RoundedRectangle(cornerRadius: 26).stroke(Night.edge) }
            .shadow(color: Night.cobalt.opacity(0.35), radius: 30, y: 12)
            .rotationEffect(.degrees(-3))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Preview of the Earnit widget")
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            stepRow(1, "Touch and hold an empty area of your Home Screen until the apps jiggle.")
            stepRow(2, "Tap Edit in the top corner, then Add Widget.")
            stepRow(3, "Search for Earnit, pick a size and tap Add Widget.")
            Text("On the Lock Screen: touch and hold it, tap Customize, then tap the space under the clock.")
                .font(.sans(13.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.s)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepRow(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Text(verbatim: "\(number)")
                .font(.sans(15, weight: .bold))
                .foregroundStyle(Night.cobaltText)
                .frame(width: 32, height: 32)
                .background(Night.panel, in: .circle)
            Text(text)
                .font(.sans(16))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
        }
        .accessibilityElement(children: .combine)
    }

    private func track(_ action: String) {
        env.analytics.track(.widgetPrompt.withProperties([
            "action": .string(action),
            "source": .string(source)
        ]))
    }
}
