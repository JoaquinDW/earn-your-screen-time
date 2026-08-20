import SwiftUI

/// First launch: explain the idea, then ask for the two permissions it needs (PRD §5.1, §6).
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .concept

    private enum Step: Hashable { case concept, permissions }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch step {
            case .concept:
                ConceptStep(onContinue: advance)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .push(from: .trailing)
                    ))
            case .permissions:
                PermissionsStep(onFinish: env.completeOnboarding)
                    .transition(.push(from: .trailing))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: step)
    }

    private func advance() { step = .permissions }
}

// MARK: - Concept

private struct ConceptStep: View {
    let onContinue: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var markSize: CGFloat = 68

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Theme.Space.l)

            Image(systemName: "figure.walk.motion")
                .font(.system(size: markSize, weight: .light))
                .foregroundStyle(Theme.earned)
                .accessibilityHidden(true)
                .padding(.bottom, Theme.Space.l)

            Text("onboarding.title")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text("onboarding.tagline")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, Theme.Space.s)

            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Bullet(symbol: "square.grid.2x2", text: "onboarding.step1")
                Bullet(symbol: "figure.walk", text: "onboarding.step2")
                Bullet(symbol: "hourglass", text: "onboarding.step3")
                Bullet(symbol: "lock", text: "onboarding.step4")
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.xxl)

            Spacer(minLength: Theme.Space.l)

            Button(action: onContinue) {
                Text("onboarding.continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.earned)
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.m)
        }
        .padding(.horizontal, Theme.Space.m)
    }
}

private struct Bullet: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.earned)
                .frame(width: 32)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
