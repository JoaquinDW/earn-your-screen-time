import SwiftUI

/// The first thing anyone sees of Earnit (design v6).
///
/// This is one of only two illustrated moments in onboarding — a ridge above the city at dusk,
/// the phone small in his hand — and it earns the artwork because it is the only screen whose
/// job is the idea rather than a setting. The first screen gives one concrete earn rate; the
/// following questions and mechanism screen explain the rest of the loop.
struct OnboardingHookStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SceneHero(scene: .freedomRidge, share: 0.52) {
                        Text("app.name")
                            .eyebrowStyle(Night.textSoft)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text("onboarding.hook.headline")
                            .font(.serif(42, relativeTo: .largeTitle))
                            .foregroundStyle(Night.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)

                        Text("onboarding.hook.subtitle")
                            .font(.sans(16))
                            .foregroundStyle(Night.textSoft)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 14)

                        Label("5 min / 500 steps", systemImage: "figure.walk")
                            .font(.sans(14, weight: .semibold))
                            .foregroundStyle(Night.cobaltText)
                            .padding(.horizontal, Theme.Space.m)
                            .frame(minHeight: Theme.minTouchTarget)
                            .background(Night.cobaltWash, in: .capsule)
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
