import EarnDomain
import SwiftUI

struct AdaptiveExistingUserView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var recommendation: Int?
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    GuardianPanel(
                        progress: GuardianState.awakening.anchor,
                        height: 190,
                        cornerRadius: Theme.sheetRadius
                    )
                    Text("EARNIT NOW ADAPTS TO YOU").eyebrowStyle(Theme.coralDeep)
                    Text("Start where you are. Get slightly better over time.")
                        .font(.serif(38, relativeTo: .largeTitle))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("We can use your recent walking activity to suggest a more achievable daily goal. Your earn rate and existing balance will not change.")
                        .font(.sans(16))
                        .foregroundStyle(Theme.muted)

                    if let recommendation {
                        HStack {
                            goalValue(env.dailyStepGoal, label: "Current")
                            Image(systemName: "arrow.right").foregroundStyle(Theme.cobaltDeep)
                            goalValue(recommendation, label: "Suggested")
                        }
                        .padding(Theme.Space.m)
                        .background(Theme.paper, in: .rect(cornerRadius: Theme.cornerRadius))
                        .overlay { RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.line) }
                    } else if let message {
                        Text(message)
                            .font(.sans(14.5))
                            .foregroundStyle(Theme.muted)
                            .padding(Theme.Space.m)
                            .background(Theme.sageLight, in: .rect(cornerRadius: Theme.cornerRadius))
                    }
                }
                .padding(Theme.Space.gutter)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Theme.Space.s) {
                    if let recommendation {
                        Button("Use recommendation") {
                            env.updateDailyGoal(recommendation)
                            finish()
                        }
                        .buttonStyle(.pill)
                    } else {
                        Button {
                            calculateRecommendation()
                        } label: {
                            HStack {
                                if isLoading { ProgressView().tint(Theme.paper) }
                                Text(isLoading ? "Checking your activity" : "Create my recommendation")
                            }
                        }
                        .buttonStyle(.pill)
                        .disabled(isLoading)
                    }
                    Button("Keep current setup", action: finish)
                        .buttonStyle(.quiet)
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.vertical, Theme.Space.s)
                .background(Theme.background)
            }
            .paperBackground()
        }
    }

    private func calculateRecommendation() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            guard let result = try? await env.health.recentDailySteps(),
                  let baseline = result.baselineSteps else {
                message = String(localized: "We couldn't find enough recent walking data. Your current setup stays exactly as it is.", locale: env.appLanguage.locale)
                return
            }
            recommendation = GoalRecommendationEngine.recommend(forBaseline: baseline)
        }
    }

    private func finish() {
        env.markAdaptiveIntroSeen()
        dismiss()
    }

    private func goalValue(_ value: Int, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.sans(12, weight: .semibold)).foregroundStyle(Theme.muted)
            Text(value.formatted()).font(.serif(25)).monospacedDigit()
            Text("steps/day").font(.sans(12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
