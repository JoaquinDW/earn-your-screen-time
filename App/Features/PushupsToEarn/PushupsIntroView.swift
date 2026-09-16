import SwiftUI

/// Shown once to people who were already using Earnit when Pushups to Earn shipped.
/// Newer users meet push-ups during onboarding and never see this.
struct PushupsIntroView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let onStart: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    NightEyebrow(text: "pushups.intro.eyebrow", tableName: PushupsLocalization.tableName)
                    PushupsText("pushups.intro.title")
                        .font(.serif(38, relativeTo: .largeTitle))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    PushupsText("pushups.intro.detail")
                        .font(.sans(16))
                        .foregroundStyle(Night.textSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: Theme.Space.m) {
                        step("iphone.gen3", "pushups.intro.step.camera", "pushups.intro.step.camera.detail")
                        step("figure.strengthtraining.traditional", "pushups.intro.step.reps", "pushups.intro.step.reps.detail")
                        step("timer", "pushups.intro.step.reward", "pushups.intro.step.reward.detail")
                    }
                    .padding(Theme.Space.m)
                    .background(Night.panel, in: .rect(cornerRadius: Theme.cornerRadius))
                    .overlay { RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Night.edge) }

                    PushupsText("pushups.intro.privacy")
                        .font(.sans(13))
                        .foregroundStyle(Night.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Space.gutter)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Theme.Space.s) {
                    Button {
                        env.analytics.track(.pushupsIntroAccepted)
                        env.markPushupsIntroSeen()
                        dismiss()
                        onStart()
                    } label: {
                        PushupsText("pushups.intro.cta")
                    }
                    .buttonStyle(.nightPill)

                    Button {
                        env.analytics.track(.pushupsIntroDismissed)
                        env.markPushupsIntroSeen()
                        dismiss()
                    } label: {
                        PushupsText("pushups.intro.later")
                    }
                    .buttonStyle(.quietLink)
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.vertical, Theme.Space.s)
                .background(Night.ground)
            }
            .background(Night.ground.ignoresSafeArea())
        }
        .task { env.analytics.track(.pushupsIntroShown) }
    }

    private func step(
        _ icon: String,
        _ title: LocalizedStringKey,
        _ detail: LocalizedStringKey
    ) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Night.cobaltText)
                .frame(width: 44, height: 44)
                .background(Night.cobaltWash, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                PushupsText(title).font(.sans(16, weight: .semibold))
                PushupsText(detail)
                    .font(.sans(13))
                    .foregroundStyle(Night.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
