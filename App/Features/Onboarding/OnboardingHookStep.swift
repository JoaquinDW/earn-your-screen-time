import SwiftUI

/// The first thing anyone sees of Earnit (design v6).
///
/// This is one of only two illustrated moments in onboarding — a ridge above the city at dusk,
/// the phone small in his hand — and it earns the artwork because it is the only screen whose
/// job is the idea rather than a setting. The first screen gives one concrete earn rate; the
/// following questions and mechanism screen explain the rest of the loop.
struct OnboardingHookStep: View {
    let onContinue: () -> Void

    /// The first impression builds itself in beats, as slowly as a first look deserves: the
    /// scene lands, the line arrives, the earn rate slaps down like a sticker, and the button
    /// comes last so the eye has somewhere to go once everything is read.
    private static let entrance = "onboarding.hook"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SceneHero(scene: .freedomRidge, share: 0.52) {
                        Text("app.name")
                            .eyebrowStyle(Night.textSoft)
                    }
                    .staggeredAppear(0, in: Self.entrance, style: .settle)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("onboarding.hook.headline")
                            .font(.serif(42, relativeTo: .largeTitle))
                            .foregroundStyle(Night.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .staggeredAppear(2, in: Self.entrance)

                        Text("onboarding.hook.subtitle")
                            .font(.sans(16))
                            .foregroundStyle(Night.textSoft)
                            .fixedSize(horizontal: false, vertical: true)
                            .staggeredAppear(4, in: Self.entrance)
                            .padding(.top, 14)

                        Label("5 min / 500 steps", systemImage: "figure.walk")
                            .font(.sans(14, weight: .semibold))
                            .foregroundStyle(Night.cobaltText)
                            .padding(.horizontal, Theme.Space.m)
                            .frame(minHeight: Theme.minTouchTarget)
                            .background(Night.cobaltWash, in: .capsule)
                            .staggeredAppear(7, in: Self.entrance, style: .sticker)
                            .padding(.top, Theme.Space.l)
                    }
                    .padding(.horizontal, Theme.Space.gutter)
                    .padding(.top, Theme.Space.l)
                }
                .padding(.bottom, Theme.Space.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .ignoresSafeArea(edges: .top)

            Button("onboarding.hook.action", action: onContinue)
                .buttonStyle(.pill)
                .staggeredAppear(9, in: Self.entrance)
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.top, Theme.Space.s)
                .padding(.bottom, Theme.Space.s)
                .background(alignment: .top) {
                    VStack(spacing: 0) {
                        GroundFade(edge: .bottom, height: 28)
                        Night.ground
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
        }
    }
}

#Preview {
    OnboardingHookStep(onContinue: {})
}
