import SwiftUI

/// A once-per-day welcome beat. It dismisses itself quickly and can always be skipped immediately.
struct StreakCelebrationView: View {
    let days: Int
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var hasArrived = false
    @State private var isDismissing = false

    var body: some View {
        ZStack {
            Night.ground.opacity(0.96).ignoresSafeArea()

            VStack(spacing: Theme.Space.l) {
                Spacer(minLength: Theme.Space.xxl)

                ZStack {
                    Circle()
                        .fill(Night.cobaltWash)
                        .frame(width: 176, height: 176)
                        .scaleEffect(hasArrived ? 1 : 0.72)
                        .opacity(hasArrived ? 1 : 0)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 88, weight: .bold))
                        .foregroundStyle(Night.cobaltText)
                        .rotationEffect(.degrees(hasArrived || reduceMotion ? 0 : -8))
                        .scaleEffect(hasArrived || reduceMotion ? 1 : 0.72)
                        .shadow(color: Night.cobalt.opacity(0.3), radius: Theme.Space.m)
                        .accessibilityHidden(true)
                }

                VStack(spacing: Theme.Space.s) {
                    Text("dashboard.streak \(days)")
                        .font(.serif(56))
                        .foregroundStyle(Night.text)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(days)))

                    Text("streak.celebration.title")
                        .font(.sans(17, weight: .semibold, relativeTo: .headline))
                        .foregroundStyle(Night.textSoft)

                    Text("streak.celebration.message")
                        .font(.sans(14))
                        .foregroundStyle(Night.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Space.gutter)

                Spacer(minLength: Theme.Space.xxl)

                Button("streak.celebration.skip", action: dismiss)
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Night.textMuted)
                    .frame(minWidth: Theme.minTouchTarget, minHeight: Theme.minTouchTarget)
                    .buttonStyle(.plain)
                    .padding(.bottom, Theme.Space.l)
            }
            .opacity(isDismissing ? 0 : 1)
            .scaleEffect(isDismissing && !reduceMotion ? 0.98 : 1)
        }
        .accessibilityElement(children: .contain)
        .task {
            withAnimation(reduceMotion ? nil : .snappy(duration: EarnMotion.reward)) {
                hasArrived = true
            }
            HapticManager.trigger(.light)

            guard !voiceOverEnabled else { return }
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private func dismiss() {
        guard !isDismissing else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: EarnMotion.standard)) {
            isDismissing = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 320))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}
