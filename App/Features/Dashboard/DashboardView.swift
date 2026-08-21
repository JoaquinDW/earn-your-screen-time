import EarnDomain
import FamilyControls
import SwiftUI

/// Home. One hero sentence, one hairline of numbers, no cards.
///
/// The trail above it means exactly one thing — distance to your next reward — and the sentence
/// under it says the same thing in words. When the wallet runs out the screen becomes the paused
/// state instead; that is not an error screen, it is the same walk seen from a standstill.
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onNavigate: ((AppSection) -> Void)? = nil

    @State private var isShowingSettings = false
    @State private var isShowingWeek = false
    @State private var isShowingApps = false
    @State private var isShowingJourneyResult = false
    @State private var selection = FamilyActivitySelection()
    @State private var selectedSessionMinutes = 5

    var body: some View {
        ZStack {
            PaperBackground()

            home

            if let reward = env.pendingReward {
                RewardView(reward: reward, onDismiss: env.dismissReward)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .foregroundStyle(Theme.ink)
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: env.isLocked)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: env.pendingReward)
        .task { await env.refresh() }
        .task(id: env.activeSession?.id) {
            guard let session = env.activeSession else { return }
            try? await Task.sleep(for: .seconds(max(0, session.endsAt.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            env.reload()
        }
        .onAppear {
            selection = env.screenTime.selection
            isShowingJourneyResult = env.journey?.finalizedResult != nil
                && env.journey?.completionAcknowledged == false
        }
        .onChange(of: env.wallet.availableMinutes) { _, availableMinutes in
            if selectedSessionMinutes > availableMinutes {
                selectedSessionMinutes = env.supportedSessionDurations.first {
                    $0 <= availableMinutes
                } ?? 5
            }
        }
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
        .sheet(isPresented: $isShowingWeek) { WeekView() }
        .sheet(isPresented: $isShowingApps, onDismiss: { selection = env.screenTime.selection }) {
            AppSelectionView()
        }
        .sheet(isPresented: $isShowingJourneyResult, onDismiss: env.acknowledgeJourneyCompletion) {
            if let journey = env.journey, let result = journey.finalizedResult {
                JourneyResultView(journey: journey, result: result) {
                    env.acknowledgeJourneyCompletion()
                    isShowingJourneyResult = false
                }
            }
        }
    }

    // MARK: - Home

    private var home: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    trailHeader(topInset: geometry.safeAreaInsets.top)

                    VStack(alignment: .leading, spacing: 0) {
                        hero

                        Hairline().padding(.top, 34)

                        numbers

                        Hairline()

                        if let journey = env.journey, let progress = env.journeyProgress {
                            journeySection(journey: journey, progress: progress)
                                .padding(.top, Theme.Space.l)
                        }

                        RestrictedAppsStrip(selection: selection) { isShowingApps = true }
                            .padding(.top, Theme.Space.m)

                        if let session = env.activeSession {
                            activeSessionView(session)
                                .padding(.top, Theme.Space.m)
                                .transition(.opacity)
                        } else if !selection.isEmpty, env.wallet.availableMinutes >= 5 {
                            sessionStarter
                                .padding(.top, Theme.Space.m)
                                .transition(.opacity)
                        } else {
                            refreshStepsButton
                                .padding(.top, Theme.Space.m)
                                .transition(.opacity)
                        }

                        monthSection
                            .padding(.top, Theme.Space.xl)

                        Spacer(minLength: 20)

                        if let error = env.lastError {
                            Text(error)
                                .font(.sans(12.5))
                                .foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, Theme.Space.s)
                                .transition(.opacity)
                        }

                        if onNavigate == nil {
                            footerLinks
                        }
                    }
                    .padding(.horizontal, Theme.Space.gutter)
                    .padding(.top, Theme.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.background)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: env.lastError)
                }
            }
            .ignoresSafeArea(edges: .top)
            .refreshable { await env.refresh() }
        }
    }

    private func trailHeader(topInset: CGFloat) -> some View {
        TrailHeader(
            progress: env.milestoneProgress,
            height: 300,
            overlayInset: topInset + Theme.Space.s,
            lip: Theme.sheetRadius
        ) {
            HStack {
                Chip(text: Text(Date.now.formatted(.dateTime.weekday(.wide))))
                Spacer()
                if env.streakDays > 0 {
                    Chip(text: Text("dashboard.streak \(env.streakDays)"), color: Theme.coralDeep)
                }
            }
            .padding(.horizontal, Theme.Space.l)
        }
    }

    /// Available time is the immediate payoff; movement explains where it came from.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AVAILABLE BECAUSE YOU EARNED IT")
                .eyebrowStyle(Theme.sageDeep)
                .padding(.bottom, 10)

            Text("\(env.wallet.availableMinutes) min")
                .font(.serif(52))
                .foregroundStyle(Theme.sageDeep)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(env.wallet.availableMinutes)))

            HStack(alignment: .firstTextBaseline) {
                Text("\(env.ledger.activityAmount.formatted()) / \(env.dailyStepGoal.formatted()) steps")
                    .font(.sans(15, weight: .bold))
                Spacer()
                Text("today").font(.sans(13)).foregroundStyle(Theme.muted)
            }
            .padding(.top, Theme.Space.l)
            ProgressView(value: min(1, Double(env.ledger.activityAmount) / Double(max(1, env.dailyStepGoal))))
                .tint(Theme.coralDeep)
                .padding(.top, Theme.Space.s)
        }
        .accessibilityElement(children: .combine)
    }

    private var refreshStepsButton: some View {
        Button {
            Task { await env.refresh() }
        } label: {
            HStack(spacing: Theme.Space.s) {
                if env.isRefreshing {
                    ProgressView()
                        .tint(Theme.paper)
                        .accessibilityHidden(true)
                }
                Text(LocalizedStringKey(
                    env.isRefreshing ? "dashboard.refreshingSteps" : "dashboard.refreshSteps"
                ))
            }
        }
        .buttonStyle(.pill)
        .disabled(env.isRefreshing)
    }

    private var sessionStarter: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("session.chooseDuration")
                .font(.sans(12.5, weight: .semibold))
                .textCase(.uppercase)
                .kerning(1)
                .foregroundStyle(Theme.muted)

            HStack(spacing: Theme.Space.s) {
                ForEach(env.supportedSessionDurations, id: \.self) { minutes in
                    let isSelected = selectedSessionMinutes == minutes
                    Button {
                        selectedSessionMinutes = minutes
                    } label: {
                        Text("common.minutesValue \(minutes)")
                            .font(.sans(15, weight: .semibold))
                            .foregroundStyle(isSelected ? Theme.paper : Theme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Theme.minTouchTarget)
                            .background(
                                isSelected ? Theme.sageDeep : Theme.sageLight,
                                in: .capsule
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(minutes > env.wallet.availableMinutes)
                    .opacity(minutes <= env.wallet.availableMinutes ? 1 : 0.35)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            Button {
                Task { await env.startSession(durationMinutes: selectedSessionMinutes) }
            } label: {
                HStack(spacing: Theme.Space.s) {
                    if env.isStartingSession {
                        ProgressView().tint(Theme.paper).accessibilityHidden(true)
                    }
                    Text("session.start \(selectedSessionMinutes)")
                }
            }
            .buttonStyle(.pill(.sage))
            .disabled(env.isStartingSession)

            Button("dashboard.refreshSteps") {
                Task { await env.refresh() }
            }
            .buttonStyle(.quietLink)
            .frame(maxWidth: .infinity)
            .disabled(env.isRefreshing)
        }
    }

    private func activeSessionView(_ session: ScreenTimeSession) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("session.active")
                    .font(.sans(12.5, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(1)
                    .foregroundStyle(Theme.sageDeep)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(sessionTime(session.remainingSeconds(at: context.date)))
                        .font(.sans(22, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.sageDeep)
                        .contentTransition(.numericText())
                }
            }
            Text("session.active.explanation")
                .font(.sans(13.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func sessionTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var numbers: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            StatPair(
                value: Text("\(env.nextMilestone.remainingAmount.formatted()) steps"),
                caption: "until the next reward",
                color: Theme.coralDeep,
                numericValue: Double(env.nextMilestone.remainingAmount)
            )
            StatPair(
                value: Text("+\(env.nextMilestone.rewardMinutes) min"),
                caption: "your next unlock",
                color: Theme.sageDeep,
                numericValue: Double(env.nextMilestone.rewardMinutes)
            )
        }
        .padding(.vertical, 18)
    }

    private func journeySection(journey: ThirtyDayJourney, progress: ThirtyDayJourney.Progress) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(journeyTitle).font(.serif(25))
                    Text("Day \(env.journeyDay) of 30")
                        .font(.sans(12.5, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Text("\(Int((progress.fraction * 100).rounded()))%")
                    .font(.serif(25))
                    .foregroundStyle(Theme.coralDeep)
            }
            ProgressView(value: progress.fraction).tint(Theme.coralDeep)
            Text("\(progress.cumulativeSteps.formatted()) / \(journey.target.formatted()) steps")
                .font(.sans(13.5, weight: .semibold))
            Text(journeyMeaning)
                .font(.serif(17, italic: true, relativeTo: .body))
                .foregroundStyle(Theme.muted)
        }
        .padding(Theme.Space.m)
        .background(Theme.paper, in: .rect(cornerRadius: Theme.cornerRadius))
        .overlay { RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.line) }
        .accessibilityElement(children: .combine)
    }

    private var journeyTitle: String {
        switch env.journeyDay {
        case 7...13: "Week one complete"
        case 14...20: "Halfway there"
        case 30: "You earned your month"
        default: "Your 30-day goal"
        }
    }

    private var journeyMeaning: String {
        switch env.journeyDay {
        case 7...13: "Momentum is built one earned scroll at a time."
        case 14...20: "Your phone is spending this month pushing you forward."
        case 30: "Thirty days of choosing movement before scrolling."
        default: "A month where scrolling gives you a reason to move."
        }
    }

    private var monthSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("THIS MONTH").eyebrowStyle()
            HStack(alignment: .top, spacing: Theme.Space.s) {
                monthMetric(env.monthTotals.steps.formatted(), "steps")
                monthMetric(durationText(env.monthTotals.earnedSeconds), "earned")
                monthMetric("\(env.streakDays)", "day streak")
            }
            Text("\(env.streakDays) days of moving before scrolling.")
                .font(.serif(17, italic: true, relativeTo: .body))
                .foregroundStyle(Theme.muted)
        }
    }

    private func monthMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.sans(15, weight: .bold)).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.sans(11.5, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func durationText(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private var footerLinks: some View {
        HStack(spacing: Theme.Space.l) {
            Button("dashboard.thisWeek") { isShowingWeek = true }
                .buttonStyle(.quietLink)
            Button("settings.title") { isShowingSettings = true }
                .buttonStyle(.quietLink)
        }
        .padding(.bottom, Theme.Space.s)
    }

    private func show(_ section: AppSection) {
        if let onNavigate {
            onNavigate(section)
            return
        }

        switch section {
        case .home:
            break
        case .week:
            isShowingWeek = true
        case .settings:
            isShowingSettings = true
        }
    }
}

// MARK: - Pieces

/// The soft label that floats over the illustration.
struct Chip: View {
    let text: Text
    var color: Color = Theme.ink

    var body: some View {
        text
            .font(.sans(12.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(Theme.paper.opacity(0.8), in: .capsule)
    }
}

/// A number with its meaning underneath. Half of the single hairline row of numbers.
struct StatPair: View {
    let value: Text
    let caption: LocalizedStringKey
    var color: Color = Theme.ink
    var numericValue: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            value
                .font(.sans(15.5, weight: .bold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .contentTransition(.numericText(value: numericValue ?? 0))
                .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: numericValue)
            Text(caption)
                .font(.sans(11.5, weight: .semibold))
                .textCase(.uppercase)
                .kerning(1)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct JourneyResultView: View {
    let journey: ThirtyDayJourney
    let result: ThirtyDayJourney.FinalizedResult
    let onDone: () -> Void

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TrailView(progress: result.reachedTarget ? 1 : min(1, Double(result.cumulativeSteps) / Double(max(1, journey.target))))
                        .frame(height: 220)

                    Text("YOU EARNED YOUR MONTH").eyebrowStyle(Theme.sageDeep).padding(.top, Theme.Space.l)
                    Text("That’s what happens when your phone gives you a reason to move.")
                        .font(.serif(39))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)

                    VStack(spacing: 0) {
                        resultRow("figure.walk", result.cumulativeSteps.formatted(), "steps", Theme.coralDeep)
                        Hairline()
                        resultRow("timer", durationText(result.earnedSeconds), "earned", Theme.sageDeep)
                        Hairline()
                        resultRow("flame.fill", "\(result.activeDays)", "active days", Theme.coralDeep)
                        Hairline()
                        resultRow("trophy.fill", "\(result.goalHitDays)", "days hitting your goal", Theme.ink)
                    }
                    .padding(.top, Theme.Space.l)

                    Button("Keep earning", action: onDone)
                        .buttonStyle(.pill(.sage))
                        .padding(.top, Theme.Space.xl)
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.bottom, Theme.Space.xl)
            }
        }
    }

    private func resultRow(_ icon: String, _ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 30).accessibilityHidden(true)
            Text(value).font(.serif(29)).foregroundStyle(color)
            Spacer()
            Text(label).font(.sans(13.5, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .combine)
    }

    private func durationText(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return "\(hours)h \(minutes)m"
    }
}

#Preview {
    DashboardView()
        .environment(AppEnvironment(
            screenTime: MockScreenTimeService(status: .approved),
            health: MockHealthKitService(hasRequested: true, steps: 3_842)
        ))
}
