import SwiftUI

struct EarnPrimaryButton: View {
    let label: Text
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .font(.sans(17, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Theme.buttonHeight)
        }
        .buttonStyle(EarnPrimaryButtonStyle())
        .disabled(!isEnabled)
    }
}

private struct EarnPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.cobaltPressed : Theme.cobalt, in: .capsule)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct EarnedTimeBadge: View {
    let minutes: Int

    var body: some View {
        Text("shield.detail.availableBadge \(minutes)")
            .font(.sans(12, weight: .bold))
            .textCase(.uppercase)
            .kerning(1.4)
            .foregroundStyle(Color.white)
            .padding(.horizontal, Theme.Space.l)
            .frame(minHeight: Theme.minTouchTarget)
            .background(Theme.cobalt.opacity(0.18), in: .capsule)
            .overlay(Capsule().stroke(Theme.cobalt.opacity(0.8), lineWidth: 1))
            .accessibilityLabel(Text("shield.detail.availableA11y \(minutes)"))
    }
}

struct EarnProgressView: View {
    let currentValue: Int
    let targetValue: Int
    let estimatedRemaining: Int
    let rewardMinutes: Int

    @Environment(\.locale) private var locale

    private var progress: Double {
        guard targetValue > 0 else { return 0 }
        return min(1, max(0, Double(currentValue) / Double(targetValue)))
    }

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            HStack {
                Text("shield.detail.progress \(currentValue.formatted(.number.locale(locale))) \(targetValue.formatted(.number.locale(locale)))")
                    .font(.sans(14, weight: .semibold))
                    .monospacedDigit()
                Spacer()
                Text("shield.detail.reward \(rewardMinutes)")
                    .font(.sans(12, weight: .bold))
                    .foregroundStyle(Theme.cobalt)
            }

            GeometryReader { geometry in
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.cobalt)
                            .frame(width: geometry.size.width * progress)
                    }
            }
            .frame(height: 8)

            Text("shield.detail.remaining \(max(0, targetValue - currentValue)) \(estimatedRemaining)")
                .font(.sans(13))
                .foregroundStyle(Color.white.opacity(0.68))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color.white)
        .accessibilityElement(children: .combine)
    }
}
