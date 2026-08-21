import SwiftUI

/// The arrival frame of the same scene: sun risen, flag reached, one number.
///
/// No confetti and no coins — the reward is the time itself, so the screen says how much and
/// gets out of the way.
struct RewardView: View {
    let reward: AppEnvironment.Reward
    let onDismiss: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasArrived = false

    /// How many rewards a full day at the user's own goal would be — the marks along the bottom.
    private var milestonesInGoal: Int {
        max(1, min(10, env.dailyStepGoal / max(1, env.ledger.rule.amountRequired)))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Theme.sageLight)
                    .frame(width: 236, height: 236)
                    .scaleEffect(hasArrived && !reduceMotion ? 1.06 : 1)
                    .opacity(hasArrived && !reduceMotion ? 0.6 : 0.35)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                        value: hasArrived
                    )
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    Text("reward.title")
                        .font(.serif(48))
                        .scaleEffect(pop ? 1 : 0.86)
                        .opacity(pop ? 1 : 0)

                    Text("reward.amount \(reward.minutes)")
                        .font(.serif(80))
                        .foregroundStyle(Theme.coralDeep)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .padding(.top, 18)
                        .scaleEffect(pop ? 1 : 0.86)
                        .opacity(pop ? 1 : 0)
                        .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.7).delay(0.12),
                                   value: hasArrived)

                    Text("reward.walletReady \(env.wallet.availableMinutes)")
                        .font(.serif(22, italic: true, relativeTo: .title3))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 12)
                        .opacity(pop ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.26), value: hasArrived)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            }
            .padding(.top, Theme.Space.xxl)

            Spacer(minLength: Theme.Space.l)

            TrailView(progress: 1)
                .frame(height: 258)

            VStack(spacing: 0) {
                unlockMarks
                    .padding(.bottom, 22)

                Button("reward.cta", action: onDismiss)
                    .buttonStyle(.pill(.sage))

                Text("reward.footnote \(env.ledger.milestonesRewarded) \(milestonesInGoal)")
                    .font(.sans(13))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, Theme.Space.l)
            .padding(.bottom, Theme.Space.s)
            .background(Theme.paper)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperBackground(color: Theme.paper))
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.7)) {
                hasArrived = true
            }
        }
    }

    private var pop: Bool { hasArrived || reduceMotion }

    /// One mark per reward earned today, against a full day at the user's own goal.
    private var unlockMarks: some View {
        HStack(spacing: 6) {
            ForEach(0..<milestonesInGoal, id: \.self) { index in
                Capsule()
                    .fill(index < env.ledger.milestonesRewarded ? Theme.coral : Theme.sageLight)
                    .frame(width: 26, height: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)      // the footnote below says the same thing
    }
}
