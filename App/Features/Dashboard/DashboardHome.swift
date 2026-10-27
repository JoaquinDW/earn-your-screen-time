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
/// Under the button there are only two blocks: what the balance unlocks, and one *Earn more* card
/// that holds the day's totals, the next reward and the ways to earn. Friends moved to the tab
/// bar; Home only mentions them when there is news.
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
    let onFriends: () -> Void

    private static let scene = IllustratedScene.homeEvening
    private static let entrance = "home"

    /// Bumped to make the balance numeral swell and glow once: the minutes you just earned
    /// landing in it.
    @State private var balancePulse = 0
    /// Minutes are usually earned on a pushed screen or under the reward overlay, where a pulse
    /// would play unseen; it is held until Home is actually in front of the reader.
    @State private var owesBalancePulse = false
    @State private var isOnScreen = false
    /// True when the column runs past the figure line (small phones, large text): its bottom edge
    /// then fades into the scene instead of being sliced off mid-button.
    @State private var overflowsViewport = false

    var body: some View {
        ScrollView {
            // The first time Home appears it builds itself top to bottom, the balance first and
            // the ways to earn last, instead of arriving as one finished frame.
            VStack(spacing: 0) {
                header
                    .staggeredAppear(0, in: Self.entrance)
                balance
                    .staggeredAppear(1, in: Self.entrance)
                    .padding(.top, Theme.Space.l)
                if env.activeSession == nil {
                    earnCard
                        .staggeredAppear(3, in: Self.entrance)
                        .padding(.top, Theme.Space.m)
                    if env.socialUnreadCount > 0 {
                        friendsNews
                            .staggeredAppear(4, in: Self.entrance)
                            .padding(.top, Theme.Space.s)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, Theme.Space.m)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height > Theme.Space.m
        } action: { _, overflows in
            overflowsViewport = overflows
        }
        // The initial viewport stops where the man begins; larger text can scroll within it.
        .clearOfFigure(in: Self.scene)
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: overflowsViewport ? 40 : 0)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: env.socialUnreadCount > 0)
        .onAppear {
            isOnScreen = true
            payOwedBalancePulse()
        }
        .onDisappear { isOnScreen = false }
        .onChange(of: env.earnedMinutesToday) { old, new in
            guard new > old, !reduceMotion else { return }
            owesBalancePulse = true
            payOwedBalancePulse()
        }
        .onChange(of: env.presentationFeedback == nil) { _, isClear in
            if isClear { payOwedBalancePulse() }
        }
    }

    private func payOwedBalancePulse() {
        guard owesBalancePulse, isOnScreen, env.presentationFeedback == nil else { return }
        owesBalancePulse = false
        // A beat after Home settles, so the eye is already on the number when it moves.
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            balancePulse += 1
        }
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
                    StreakBadge(days: env.streakDays, isCompact: true)
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
                        .font(.serif(100))
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
                .keyframeAnimator(initialValue: 1.0, trigger: balancePulse) { content, scale in
                    content
                        .scaleEffect(scale)
                        .shadow(color: Night.cobalt.opacity(min(0.6, max(0, (scale - 1) * 5))), radius: 28)
                } keyframes: { _ in
                    SpringKeyframe(1.1, duration: 0.22, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.6, spring: .bouncy)
                }
                .padding(.top, 10)

                Text("home.toSpendOnYourApps")
                    .font(.sans(14))
                    .foregroundStyle(Night.textMuted)
                    .padding(.top, 6)

                action
                    .staggeredAppear(2, in: Self.entrance)
                    .padding(.top, 22)

                if env.activeSession == nil {
                    if !selection.isEmpty {
                        unlocksRow.padding(.top, Theme.Space.s)
                    }
                } else {
                    // While a session runs the card is away, so the totals stay under the band.
                    todayTotals(consumed: consumed).padding(.top, Theme.Space.m)
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
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
        } else if !selection.isEmpty, let schedule = env.blockSchedule, !schedule.isBlocking(at: .now) {
            // Outside blocking hours the apps are open; spending minutes would only waste them.
            freeHoursBand(resumesAt: schedule.nextChange(after: .now))
                .transition(.opacity)
        } else if env.wallet.availableMinutes > 0 {
            Button(action: selection.isEmpty ? onChooseApps : onSpend) {
                Label(
                    selection.isEmpty ? "home.chooseApps" : "home.useMinutes",
                    systemImage: selection.isEmpty ? "square.grid.2x2" : "play.fill"
                )
            }
            .buttonStyle(.nightPill)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
        } else {
            Button(action: onEarnMore) {
                Label("home.earnMoreTime", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.nightPill)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    private func freeHoursBand(resumesAt: Date?) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "moon.stars")
                .foregroundStyle(Night.moss)
                .accessibilityHidden(true)
            Group {
                if let resumesAt {
                    Text("home.schedule.free \(resumeLabel(resumesAt))")
                } else {
                    Text("home.schedule.freeNow")
                }
            }
            .font(.sans(14, weight: .semibold))
            .foregroundStyle(Night.textSoft)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(minHeight: 52)
        .background(Night.panel, in: .capsule)
    }

    /// "18:00" later today, "Mon 09:00" on another day.
    private func resumeLabel(_ date: Date) -> String {
        let time = Date.FormatStyle.dateTime.hour().minute().locale(locale)
        return Calendar.current.isDateInToday(date)
            ? date.formatted(time)
            : date.formatted(time.weekday(.abbreviated))
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
    // Not a status readout: this is what the balance *buys*, one line under the button that
    // spends it, so it never lands on the figure as a heading with nothing under it.

    private var unlocksRow: some View {
        HStack(spacing: 10) {
            Button(action: onSpend) {
                HStack(spacing: 8) {
                    Text("home.unlocks")
                        .font(.sans(12.5, weight: .medium))
                        .foregroundStyle(Night.textDim)
                    if spendableTokens.isEmpty {
                        // A category-only selection has no app token row to draw.
                        Text("appSelection.count \(selection.itemCount)")
                            .font(.sans(12.5, weight: .medium))
                            .foregroundStyle(Night.textSoft)
                    } else {
                        ForEach(spendableTokens, id: \.self) { token in
                            Label(token)
                                .labelStyle(SpendIconLabelStyle())
                        }
                    }
                }
                .frame(minHeight: Theme.minTouchTarget)
                .contentShape(.rect)
            }
            .buttonStyle(SpendListRowButtonStyle())
            .disabled(env.wallet.availableMinutes <= 0)
            .accessibilityHint(Text("home.spend.a11y"))

            Button("home.edit", action: onChooseApps)
                .font(.sans(12.5, weight: .semibold))
                .foregroundStyle(Night.cobaltText)
                .buttonStyle(.plain)
                .frame(minHeight: Theme.minTouchTarget)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    // MARK: - Earn more
    //
    // The day's totals, the next reward and the ways to earn were three loose lines in three
    // styles; they are one question ("how do I get more?"), so they are one card.

    private var earnCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text("home.earnMore.title")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Night.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                todayTotals(consumed: 0)
            }

            Button(action: onEarnMore) {
                VStack(spacing: 8) {
                    HStack {
                        Text("earn.nextReward \(env.nextMilestone.remainingAmount) \(env.nextMilestone.rewardMinutes)")
                            .font(.sans(12.5, weight: .medium))
                            .foregroundStyle(Night.textSoft)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: Theme.Space.s)
                        Image(systemName: "chevron.right")
                            .font(.sans(10, weight: .semibold))
                            .foregroundStyle(Night.cobaltText)
                            .accessibilityHidden(true)
                    }
                    TickMeter(progress: env.milestoneProgress, height: 11, tickCount: 38)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("home.earnMoreTime"))

            HStack(spacing: Theme.Space.s) {
                earnWay("home.earnMore.walk", systemImage: "figure.walk", action: onEarnMore)
                earnWay("home.earnMore.exercise", systemImage: "figure.strengthtraining.traditional", action: onPushups)
            }
        }
        .padding(12)
        .background(Night.panel.opacity(0.78), in: .rect(cornerRadius: Night.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Night.cardRadius).stroke(Night.edge, lineWidth: 1)
        }
    }

    private func earnWay(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Night.cobaltText)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Night.textSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget)
            .background(Night.forestLift.opacity(0.85), in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(SpendListRowButtonStyle())
    }

    // MARK: - Friends

    /// Only when a friend nudged, cheered, added you or missed their goal: the tab's dot says the
    /// same thing, this line says it where you already are.
    private var friendsNews: some View {
        Button(action: onFriends) {
            HStack(spacing: 10) {
                Image(systemName: "person.2.fill")
                    .font(.sans(12, weight: .semibold))
                    .foregroundStyle(Night.moss)
                    .accessibilityHidden(true)
                Text("home.friendsNews \(env.socialUnreadCount)")
                    .font(.sans(13, weight: .medium))
                    .foregroundStyle(Night.textSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.sans(10, weight: .semibold))
                    .foregroundStyle(Night.textGhost)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: Theme.minTouchTarget)
            .background(Night.moss.opacity(0.08), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14).stroke(Night.moss.opacity(0.2), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .transition(.opacity)
    }

    /// Screen Time hands us opaque tokens; three of them is what the compact list has room for above
    /// the figure, and the rest live behind *Edit* (PRD §27).
    private var spendableTokens: [ApplicationToken] {
        Array(selection.applicationTokens.prefix(3))
    }
}

// MARK: - Pieces

/// Keep the system-rendered title available to accessibility while showing only the real app icon.
private struct SpendIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.icon
            .frame(width: 26, height: 26)
            .clipShape(.rect(cornerRadius: 7))
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
            .pressFeedback(configuration.isPressed, scale: 0.98)
    }
}

/// The running session, in the slot the *Earn more time* button occupies at rest.
private struct ActiveSessionBand: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: ScreenTimeSession
    /// Bumped once as the band arrives, so the open lock jumps as the apps unlock.
    @State private var unlockBounce = 0

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "lock.open.fill")
                    .font(.sans(11, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: unlockBounce)
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
        .task {
            guard !reduceMotion else { return }
            // After the band's own entrance, so the lock moves once it is already in view.
            try? await Task.sleep(for: .seconds(0.3))
            unlockBounce += 1
        }
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
