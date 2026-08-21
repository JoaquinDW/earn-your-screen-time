import SwiftUI

/// The paused state. Same walk, seen from a standstill.
///
/// Deliberately not an alarm: no red, no lock icon, no scolding. It answers the only question
/// worth asking at that moment — how much further to the next few minutes.
struct LockedView: View {
    let onCheckSteps: () -> Void
    let onShowWeek: () -> Void
    let onShowSettings: () -> Void
    var showsNavigationLinks = true

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("locked.eyebrow")
                    .eyebrowStyle()
                    .padding(.bottom, 12)

                SerifHeadline(
                    upright: "locked.title",
                    italic: "locked.title.emphasis",
                    size: 38
                )

                Text("locked.subtitle")
                    .font(.serif(17, italic: true, relativeTo: .body))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 290, alignment: .leading)
                    .padding(.top, 10)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, Theme.Space.l)
            .padding(.bottom, Theme.Space.l)

            TrailView(progress: env.milestoneProgress)
                .frame(height: 226)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(env.nextMilestone.remainingAmount.formatted())")
                        .font(.serif(38))
                        .contentTransition(.numericText(value: Double(env.nextMilestone.remainingAmount)))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: env.nextMilestone.remainingAmount)
                    Text("locked.stepsToReward \(env.nextMilestone.rewardMinutes)")
                        .font(.sans(17))
                        .foregroundStyle(Theme.muted)
                        .contentTransition(.numericText(value: Double(env.nextMilestone.rewardMinutes)))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: env.nextMilestone.rewardMinutes)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)

                progressBar
                    .padding(.top, 18)

                Text("locked.restingApps \(env.state.restrictedItemCount)")
                    .font(.sans(13.5))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                Spacer(minLength: 22)

                Button("locked.cta", action: onCheckSteps)
                    .buttonStyle(.pill)
                    .disabled(env.isRefreshing)

                if showsNavigationLinks {
                    HStack(spacing: Theme.Space.l) {
                        Button("dashboard.thisWeek", action: onShowWeek)
                            .buttonStyle(.quietLink)
                        Button("settings.title", action: onShowSettings)
                            .buttonStyle(.quietLink)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, Theme.Space.l)
            .padding(.bottom, Theme.Space.s)
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule()
                    .fill(Theme.coral)
                    .frame(width: max(6, geometry.size.width * env.milestoneProgress))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.8), value: env.milestoneProgress)
            }
        }
        .frame(height: 12)
        .accessibilityElement()
        .accessibilityLabel(Text("locked.progress.a11y"))
        .accessibilityValue(Text("\(Int(env.milestoneProgress * 100))%"))
    }
}
