import EarnDomain
import FamilyControls
import ManagedSettings
import SwiftUI

/// Home (design v6) — *there is a life outside the screen.*
///
/// The screen is one painted evening: a man on a chair under a huge tree, his phone the only cold
/// light in it. The artwork is full-bleed rather than a header image, because the whole point of
/// the composition is the empty middle — and that emptiness is where the balance goes. Nothing is
/// drawn on top of the figure; the UI column is bounded by the scene's own `figureBand`, so the
/// bottom quarter of every device is left to the illustration.
///
/// The hierarchy inverts v5's. v5 led with *how far to the next reward* and kept the balance in a
/// footnote; v6 leads with **the balance** — one serif numeral, the largest thing on the screen —
/// and demotes the step distance to a line under the button. The reward loop is still one tap
/// away, on `EarnTimeView`.
///
/// Nothing about earning, spending, shielding or persistence moved: this file only re-draws what
/// `AppEnvironment` already publishes.
struct DashboardHome: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    let selection: FamilyActivitySelection
    let onChooseApps: () -> Void
    let onSpend: () -> Void
    let onEarnMore: () -> Void
    let onPushups: () -> Void

    private static let scene = IllustratedScene.homeEvening

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                balance.padding(.top, Theme.Space.xxl)
                if env.activeSession == nil && !selection.isEmpty {
                    spendSection.padding(.top, Theme.Space.xl)
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, Theme.Space.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The initial viewport stops where the man begins; larger text can scroll within it.
        .clearOfFigure(in: Self.scene)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(Date.now.formatted(.dateTime.weekday(.wide).locale(locale)))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: "Earnit")
                .font(.serif(21, relativeTo: .title3))
                .foregroundStyle(Night.text)

            Group {
                if env.streakDays > 0 {
                    StreakBadge(days: env.streakDays)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.sans(12.5, weight: .medium))
        .foregroundStyle(Night.textMuted)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    // MARK: - Balance
    //
    // The strongest element on the screen, and the only display type here. It is centred because
    // the artwork's negative space is centred: anywhere else and it sits on a tree.

    private var balance: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let available = env.currentWalletBalanceSeconds(at: context.date) / 60
            let consumed = env.currentConsumedSeconds(at: context.date) / 60

            VStack(spacing: 0) {
                NightEyebrow(text: "home.availableTime")

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(available.formatted(.number.locale(locale)))
                        .font(.serif(112))
                        .foregroundStyle(Night.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(available)))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: available)
                    Text("home.unit.minutes")
                        .font(.sans(19))
                        .foregroundStyle(Night.textMuted)
                }
                .padding(.top, 10)

                Text("home.toSpendOnYourApps")
                    .font(.sans(14))
                    .foregroundStyle(Night.textMuted)
                    .padding(.top, 6)

                action.padding(.top, 28)

                if env.activeSession == nil && available == 0 {
                    quickPushupsAction.padding(.top, Theme.Space.xs)
                }

                todayTotals(consumed: consumed).padding(.top, Theme.Space.m)

                if env.activeSession == nil {
                    Button(action: onEarnMore) {
                        VStack(spacing: 8) {
                            HStack {
                                Text("earn.nextReward \(env.nextMilestone.remainingAmount) \(env.nextMilestone.rewardMinutes)")
                                    .font(.sans(12.5, weight: .medium))
                                    .foregroundStyle(Night.textSoft)
                                Spacer(minLength: Theme.Space.s)
                                Image(systemName: "chevron.right")
                                    .font(.sans(10, weight: .semibold))
                                    .foregroundStyle(Night.cobaltText)
                            }
                            TickMeter(progress: env.milestoneProgress, height: 11, tickCount: 38)
                        }
                        .frame(minHeight: Theme.minTouchTarget)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Theme.Space.s)
                    .accessibilityHint(Text("home.earnMoreTime"))
                }

                if let error = env.lastError {
                    Text(error)
                        .font(.sans(12.5))
                        .foregroundStyle(Night.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Space.s)
                        .transition(.opacity)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                Text("wallet.summary \(available) \(env.earnedMinutesToday) \(consumed)")
            )
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: env.lastError)
    }

    /// The next action follows the balance: earn at zero, choose apps if needed, then spend.
    @ViewBuilder
    private var action: some View {
        if let session = env.activeSession {
            ActiveSessionBand(session: session)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        } else if env.wallet.availableMinutes > 0 {
            Button(action: selection.isEmpty ? onChooseApps : onSpend) {
                Label(
                    selection.isEmpty ? "home.chooseApps" : "home.useMinutes",
                    systemImage: selection.isEmpty ? "square.grid.2x2" : "play.fill"
                )
            }
            .buttonStyle(.nightPill)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        } else {
            Button(action: onEarnMore) {
                Label("home.earnMoreTime", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.nightPill)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private var quickPushupsAction: some View {
        Button(action: onPushups) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .accessibilityHidden(true)
                PushupsText("pushups.entry.quick")
                Image(systemName: "chevron.right")
                    .font(.sans(10, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .font(.sans(13.5, weight: .semibold))
            .foregroundStyle(Night.cobaltText)
            .frame(minHeight: Theme.minTouchTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("pushups.entry.hint", tableName: PushupsLocalization.tableName))
    }

    /// The day's totals, and the only place on Home that pulls fresh steps — this screen has no
    /// scroll to refresh, exactly as in v5.
    private func todayTotals(consumed: Int) -> some View {
        Button {
            Task { await env.refresh() }
        } label: {
            HStack(spacing: 6) {
                Text("home.stepsTodayCount \(env.ledger.activityAmount.formatted(.number.locale(locale)))")
                    .contentTransition(.numericText(value: Double(env.ledger.activityAmount)))
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.5),
                        value: env.ledger.activityAmount
                    )
                Text(verbatim: "·").opacity(0.5)
                Text("earn.minutesEarnedToday \(env.earnedMinutesToday)")
                    .foregroundStyle(env.earnedMinutesToday > 0 ? Night.moss : Night.textGhost)
                    .contentTransition(.numericText(value: Double(env.earnedMinutesToday)))
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.5),
                        value: env.earnedMinutesToday
                    )
                if consumed > 0 {
                    Text(verbatim: "·").opacity(0.5)
                    Text("home.minutesUsed \(consumed)")
                }
                if env.isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Night.textGhost)
                        .accessibilityHidden(true)
                }
            }
            .font(.sans(12))
            .foregroundStyle(Night.textGhost)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(minHeight: 30)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(env.isRefreshing)
        .accessibilityHint(Text("dashboard.refreshSteps"))
    }

    // MARK: - Ready to spend
    //
    // Not a status readout: this is what the balance *buys*. The rows stay directly on the scene
    // so the app icons do not turn into one large block over the illustration.

    private var spendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                NightEyebrow(text: "home.protectedApps")
                Spacer(minLength: Theme.Space.s)
                Button("home.edit", action: onChooseApps)
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Night.cobaltText)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            if spendableTokens.isEmpty {
                VStack(spacing: 0) {
                    NightHairline()
                    Button(action: onSpend) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.grid.2x2")
                                .font(.sans(13, weight: .semibold))
                                .foregroundStyle(Night.textMuted)
                                .frame(width: 34, height: 34)
                                .background(Night.forestLift.opacity(0.62), in: .rect(cornerRadius: 10))
                                .accessibilityHidden(true)
                            // A category-only selection has no app token row to draw.
                            Text("appSelection.count \(selection.itemCount)")
                            .font(.sans(14, weight: .medium))
                            .foregroundStyle(Night.textSoft)
                            .lineLimit(2)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.sans(11, weight: .semibold))
                                .foregroundStyle(Night.textGhost)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 4)
                        .frame(minHeight: 54)
                        .contentShape(.rect)
                    }
                    .buttonStyle(SpendListRowButtonStyle())
                    .disabled(env.wallet.availableMinutes <= 0)
                    NightHairline()
                }
            } else {
                VStack(spacing: 0) {
                    NightHairline()
                    SpendIconStrip(
                        tokens: spendableTokens,
                        availableMinutes: env.wallet.availableMinutes,
                        action: onSpend
                    )
                    NightHairline()
                }
            }
        }
    }

    /// Screen Time hands us opaque tokens; three of them is what the compact list has room for above
    /// the figure, and the rest live behind *Edit* (PRD §27).
    private var spendableTokens: [ApplicationToken] {
        Array(selection.applicationTokens.prefix(3))
    }
}

// MARK: - Pieces

/// The selected apps are one destination: every icon spends from the same wallet in one session.
private struct SpendIconStrip: View {
    let tokens: [ApplicationToken]
    let availableMinutes: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ForEach(tokens, id: \.self) { token in
                    Label(token)
                        .labelStyle(SpendIconLabelStyle())
                }
                Spacer(minLength: Theme.Space.s)
                Image(systemName: "chevron.right")
                    .font(.sans(11, weight: .semibold))
                    .foregroundStyle(Night.textGhost)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 60)
            .contentShape(.rect)
        }
        .buttonStyle(SpendListRowButtonStyle())
        .disabled(availableMinutes <= 0)
        .accessibilityHint(Text("home.spend.a11y"))
    }
}

/// Keep the system-rendered title available to accessibility while showing only the real app icon.
private struct SpendIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.icon
            .frame(width: 42, height: 42)
            .clipShape(.rect(cornerRadius: 12))
            .accessibilityRepresentation {
                configuration.title
            }
    }
}

/// A quiet press state without rebuilding the large surface the compact list replaces.
private struct SpendListRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Night.text.opacity(0.05) : .clear,
                in: .rect(cornerRadius: 10)
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The running session, in the slot the *Earn more time* button occupies at rest.
private struct ActiveSessionBand: View {
    @Environment(AppEnvironment.self) private var env
    let session: ScreenTimeSession

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "lock.open.fill")
                    .font(.sans(11, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text("session.active")
                    .font(.sans(11, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(1.5)
                Spacer(minLength: Theme.Space.m)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(clock(session.remainingSeconds(at: context.date)))
                        .font(.sans(20, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(Night.cobaltText)

            Text("session.active.explanation")
                .font(.sans(12.5))
                .foregroundStyle(Night.textMuted)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await env.pauseSession() }
            } label: {
                HStack(spacing: Theme.Space.s) {
                    if env.isPausingSession {
                        ProgressView().controlSize(.small).tint(Night.cobaltText).accessibilityHidden(true)
                    }
                    Text("session.endAndSave")
                    Spacer(minLength: 0)
                    Image(systemName: "stop.fill").accessibilityHidden(true)
                }
                .font(.sans(14, weight: .semibold))
                .foregroundStyle(Night.cobaltText)
                .frame(minHeight: Theme.minTouchTarget)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(env.isPausingSession)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, 12)
        .background(Night.panel.opacity(0.82), in: .rect(cornerRadius: Night.panelRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Night.panelRadius)
                .stroke(Night.cobalt.opacity(0.35), lineWidth: 1)
        }
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
