import SwiftUI

struct GoalRecommendationView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private var recommendation: Int { env.profile.pendingGoalRecommendation ?? env.dailyStepGoal }
    private var isIncrease: Bool { recommendation > env.dailyStepGoal }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Spacer(minLength: 0)
            Text(isIncrease ? "READY FOR A LITTLE MORE" : "LET'S MAKE THIS ACHIEVABLE")
                .eyebrowStyle(Night.textMuted)
            Text(isIncrease ? "Your walking rhythm is getting stronger." : "Your current goal looks ambitious right now.")
                .font(.serif(34, relativeTo: .largeTitle))
                .fixedSize(horizontal: false, vertical: true)
            Text(isIncrease
                 ? "You've reached your goal on at least 6 of the last 7 active days."
                 : "A smaller target can help you build momentum without giving up.")
                .font(.sans(16))
                .foregroundStyle(Theme.muted)
            HStack(spacing: Theme.Space.m) {
                goal(env.dailyStepGoal, label: "Current")
                Image(systemName: isIncrease ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Night.cobaltText)
                goal(recommendation, label: "Suggested")
            }
            Spacer(minLength: Theme.Space.m)
            Button(isIncrease ? "Increase goal" : "Adjust goal") {
                env.respondToGoalRecommendation(accept: true)
                dismiss()
            }
            .buttonStyle(.pill)
            Button("Keep current goal") {
                env.respondToGoalRecommendation(accept: false)
                dismiss()
            }
            .buttonStyle(.quiet)
        }
        .padding(Theme.Space.gutter)
        .background(Night.ground.ignoresSafeArea())
    }

    private func goal(_ value: Int, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.sans(12, weight: .semibold)).foregroundStyle(Theme.muted)
            Text(value.formatted()).font(.serif(26)).monospacedDigit()
            Text("steps/day").font(.sans(12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.m)
        .background(Night.panel, in: .rect(cornerRadius: Theme.cornerRadius))
        .overlay { RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Night.edge) }
    }
}
