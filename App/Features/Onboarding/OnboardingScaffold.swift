import SwiftUI

/// The shape every *functional* onboarding step takes: scrolling content, then the actions.
///
/// v6 keeps the illustrations for the two emotional beats — the opening and the first walk — and
/// leaves every step in between on the plain ground. What makes those steps feel like Earnit is
/// this scaffold: one gutter, one type scale, one action footer that fades into the ground
/// instead of sitting on a plate.
struct OnboardingScaffold<Content: View, Action: View>: View {
    let onBack: (() -> Void)?
    @ViewBuilder let content: Content
    @ViewBuilder let action: Action

    init(
        onBack: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action
    ) {
        self.onBack = onBack
        self.content = content()
        self.action = action()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.horizontal, Theme.Space.gutter)
                    .padding(.top, Theme.Space.l)
                    .padding(.bottom, Theme.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 2) {
                action
                if let onBack {
                    Button("Back", action: onBack)
                        .buttonStyle(.quiet)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.s)
            .background(alignment: .top) {
                // The footer is the ground arriving, not a bar laid on top of it, so content
                // scrolling underneath dissolves rather than being cut off by an edge.
                VStack(spacing: 0) {
                    GroundFade(edge: .bottom, height: 28)
                    Night.ground
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

/// A row of small facts under an onboarding headline — a checkmark and a sentence, no card.
struct OnboardingPoint: View {
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 13) {
            Image(systemName: "checkmark")
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(Night.moss)
                .accessibilityHidden(true)
            Text(text)
                .font(.sans(15.5))
                .foregroundStyle(Night.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
