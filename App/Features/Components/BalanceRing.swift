import SwiftUI

/// The central element of the product: the balance, wrapped in the progress that produces it.
///
/// Two things in one glance — the ring is *earning* (how close the next reward is), the number is
/// *spending* (what is in the wallet). That is the "Earn → Spend" concept made visual.
struct BalanceRing: View {
    let availableMinutes: Int
    /// 0...1 progress toward the next reward.
    let progress: Double
    let isLocked: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 78
    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 240

    /// Both are capped: at accessibility text sizes the unclamped values grow past the screen
    /// and push the ring off-canvas. The text inside still scales, it just wraps instead.
    private var resolvedRingSize: CGFloat { min(ringSize, 300) }
    private var resolvedNumberSize: CGFloat { min(numberSize, 104) }

    private var tint: Color { isLocked ? Theme.locked : Theme.earned }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, style: StrokeStyle(lineWidth: 9, lineCap: .round))

            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(Theme.activity.opacity(0.85), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .snappy(duration: 0.4), value: progress)

            VStack(spacing: Theme.Space.xs) {
                Text(availableMinutes, format: .number)
                    .font(.system(size: resolvedNumberSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .snappy, value: availableMinutes)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Text("dashboard.minutesAvailable")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    // Uppercase + tracking costs width; at accessibility sizes that
                    // turns into ugly hyphenation, so drop it there.
                    .textCase(typeSize.isAccessibilitySize ? nil : .uppercase)
                    .kerning(typeSize.isAccessibilitySize ? 0 : 0.5)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(3)
            }
            .padding(.horizontal, Theme.Space.l)
            .frame(maxWidth: resolvedRingSize - Theme.Space.l)
        }
        .frame(width: resolvedRingSize, height: resolvedRingSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("dashboard.balance.a11y \(availableMinutes)"))
        .accessibilityValue(Text(isLocked
            ? "dashboard.state.locked"
            : "dashboard.state.available"))
    }
}

#Preview {
    VStack(spacing: 40) {
        BalanceRing(availableMinutes: 24, progress: 0.72, isLocked: false)
        BalanceRing(availableMinutes: 0, progress: 0.15, isLocked: true)
    }
    .padding()
    .background(Theme.background)
}
