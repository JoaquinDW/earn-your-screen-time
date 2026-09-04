import EarnDomain
import SwiftUI

/// Earn time (design v6) — where movement turns into minutes.
///
/// Home answers *how much do I have*; this screen answers *how do I get more*. The illustration
/// is the man walking away down a path, and the layout is built so that he walks **toward** the
/// step count: the artwork is the background of the hero band, the readout sits at the foot of it
/// where the wash has already gone dark, and every rule below is on solid ground where nothing
/// competes with the reading.
///
/// It is deliberately not a fitness screen. There is no ring, no calories, no wall of closed
/// goals — the steps exist only as the price of the minutes, and it is the *minutes* the copy
/// keeps returning to.
struct EarnTimeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let heroShare: CGFloat = 0.54

    private var rule: EarningRule { env.ledger.rule }

    private var stepsText: String {
        env.ledger.activityAmount.formatted(.number.locale(locale))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                rules.padding(.top, Theme.Space.xl)
                footnote.padding(.top, Theme.Space.xl)
            }
            .padding(.bottom, Theme.Space.xxl)
        }
        // The artwork has to reach the status bar, so the scroll content owns the top edge and
        // the hero pads itself back down to safety.
        .ignoresSafeArea(edges: .top)
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await env.refresh() }
        .background(Night.ground.ignoresSafeArea())
        .foregroundStyle(Night.text)
        .tint(Night.cobalt)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("earn.title")
                    .font(.sans(16.5, weight: .semibold))
                    .foregroundStyle(Night.text)
            }
        }
        .task { await env.refresh() }
    }

    // MARK: - Hero

    private var hero: some View {
        SceneHero(scene: .earnPath, share: Self.heroShare) {
            VStack(alignment: .leading, spacing: 0) {
                NightEyebrow(text: "earn.today")

                stepsReadout.padding(.top, 10)

                TickMeter(progress: env.dayProgress, height: 20)
                    .padding(.top, Theme.Space.m)

                HStack(alignment: .firstTextBaseline) {
                    Text("earn.goalProgress \(env.dailyStepGoal.formatted(.number.locale(locale)))")
                        .foregroundStyle(Night.textDim)
                    Spacer(minLength: Theme.Space.s)
                    Text("earn.minutesEarnedToday \(env.earnedMinutesToday)")
                        .foregroundStyle(env.earnedMinutesToday > 0 ? Night.moss : Night.textFaint)
                        .contentTransition(.numericText(value: Double(env.earnedMinutesToday)))
                }
                .font(.sans(12.5))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.top, 10)
            }
        }
    }

    /// The step count, and the only place on this screen that pulls fresh data from HealthKit.
    private var stepsReadout: some View {
        Button {
            Task { await env.refresh() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(stepsText)
                    .font(.serif(58))
                    .foregroundStyle(Night.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: Double(env.ledger.activityAmount)))
                Text("earn.stepsUnit")
                    .font(.sans(16))
                    .foregroundStyle(Night.textMuted)
                if env.isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Night.textMuted)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(env.isRefreshing)
        .accessibilityLabel(Text("earn.stepsToday \(stepsText)"))
        .accessibilityHint(Text("dashboard.refreshSteps"))
    }

    // MARK: - Rules

    private var rules: some View {
        VStack(alignment: .leading, spacing: 12) {
            NightEyebrow(text: "earn.chooseHowToEarn")
                .padding(.horizontal, 4)

            EarningRuleCard(
                title: "earn.source.steps",
                detail: Text(
                    "earn.rule \(rule.amountRequired.formatted(.number.locale(locale))) \(rule.rewardMinutes)"
                ),
                glyph: "figure.walk",
                state: .active(
                    trailingLabel: "earn.today",
                    trailingValue: Text(stepsText),
                    progress: env.milestoneProgress
                )
            )

            // The domain models these sources but cannot measure them yet (`EarningSource`), so
            // they are shown as what they are rather than as a zero that reads like a failure.
            EarningRuleCard(
                title: "earn.source.workout",
                detail: Text("earn.comingSoon"),
                glyph: "figure.run",
                state: .planned
            )

            EarningRuleCard(
                title: "earn.source.focus",
                detail: Text("earn.comingSoon"),
                glyph: "hourglass",
                state: .planned
            )
        }
        .padding(.horizontal, Theme.Space.l)
    }

    private var footnote: some View {
        VStack(spacing: 10) {
            Text("earn.nextReward \(env.nextMilestone.remainingAmount) \(env.nextMilestone.rewardMinutes)")
                .font(.sans(13.5, weight: .medium))
                .foregroundStyle(Night.textSoft)
                .contentTransition(.numericText(value: Double(env.nextMilestone.remainingAmount)))

            Text("earn.footnote \(ScreenTimeWallet.maximumCarryOverSeconds / 60)")
                .font(.sans(12.5))
                .foregroundStyle(Night.textFaint)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: env.nextMilestone)
    }
}

/// One way of earning: what it costs, what it pays, and how far today has got.
///
/// The implemented source gets the cobalt edge and a live bar; the ones the domain models but
/// cannot yet measure are dimmed and carry no numbers at all.
private struct EarningRuleCard: View {
    enum State {
        case active(trailingLabel: LocalizedStringKey, trailingValue: Text, progress: Double)
        case planned
    }

    let title: LocalizedStringKey
    let detail: Text
    let glyph: String
    let state: State

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isActive: Bool {
        if case .active = state { return true }
        return false
    }

    private var progress: Double {
        if case let .active(_, _, value) = state { min(1, max(0, value)) } else { 0 }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 13) {
                Image(systemName: glyph)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isActive ? Night.cobaltText : Night.textMuted)
                    .frame(width: 34, height: 34)
                    .background(
                        isActive ? Night.cobaltWash : Night.text.opacity(0.06),
                        in: .rect(cornerRadius: 10)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.sans(15.5, weight: .semibold))
                        .foregroundStyle(isActive ? Night.text : Night.textSoft)
                    detail
                        .font(.sans(12.5))
                        .foregroundStyle(Night.textDim)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                if case let .active(trailingLabel, trailingValue, _) = state {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(trailingLabel)
                            .font(.sans(10.5, weight: .medium))
                            .textCase(.uppercase)
                            .kerning(1.2)
                            .foregroundStyle(Night.textFaint)
                        trailingValue
                            .font(.sans(14, weight: .medium))
                            .foregroundStyle(Night.text)
                            .monospacedDigit()
                    }
                    .layoutPriority(1)
                }
            }

            // A solid rule, not ticks: the tick meter belongs to the one headline measure at the
            // top of the screen, and repeating it four times would flatten the hierarchy.
            Capsule()
                .fill(Night.text.opacity(0.1))
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Night.cobalt)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: progress)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.top, Theme.Space.m)
        .padding(.bottom, 18)
        .background(Night.panel, in: .rect(cornerRadius: Night.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Night.cardRadius)
                .stroke(isActive ? Night.cobalt.opacity(0.4) : Night.edge, lineWidth: 1)
        }
        .opacity(isActive ? 1 : 0.66)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        EarnTimeView()
            .environment(AppEnvironment(
                screenTime: MockScreenTimeService(status: .approved),
                health: MockHealthKitService(hasRequested: true, steps: 4_328)
            ))
    }
}
