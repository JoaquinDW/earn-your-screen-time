import SwiftUI

struct EarnPrimaryButton: View {
    let label: Text
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .font(.sans(16, weight: .semibold))
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
            .background(configuration.isPressed ? Night.cobaltLift : Night.cobalt, in: .capsule)
            .shadow(color: Night.cobalt.opacity(isEnabled ? 0.34 : 0), radius: 18, y: 8)
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
            .foregroundStyle(Night.text)
            .padding(.horizontal, Theme.Space.l)
            .frame(minHeight: Theme.minTouchTarget)
            .background(Night.cobaltWash, in: .capsule)
            .overlay(Capsule().stroke(Night.cobalt.opacity(0.7), lineWidth: 1))
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
                    .foregroundStyle(Night.cobaltText)
            }

            // The same tick rule Earn time uses, so distance-to-reward reads identically
            // wherever it is shown.
            TickMeter(progress: progress, height: 18)

            Text("shield.detail.remaining \(max(0, targetValue - currentValue)) \(estimatedRemaining)")
                .font(.sans(13))
                .foregroundStyle(Night.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Night.text)
        .accessibilityElement(children: .combine)
    }
}
