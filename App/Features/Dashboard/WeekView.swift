import EarnDomain
import SwiftUI

/// Earned time, used time, and the life that produced both.
struct WeekView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    @State private var period = ProgressPeriod.week
    @State private var selectedDay: DayKey?
    @State private var plotIsVisible = false

    var showsDoneButton = true

    private var summaries: [DaySummary] {
        switch period {
        case .day: [env.progressToday]
        case .week: env.week
        case .month: env.month
        }
    }

    private var totals: ActivityHistory.Totals { env.progressTotals(for: summaries) }
    private var selectedSummary: DaySummary { summaries.first { $0.day == selectedDay } ?? summaries.last ?? env.progressToday }
    private var displayedSessionCount: Int {
        totals.sessionCount + (env.activeSession != nil && summaries.contains { $0.day == env.ledger.day } ? 1 : 0)
    }
    private var hasCompleteUsageHistory: Bool { summaries.allSatisfy(\.hasUsageData) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: env.activeSession == nil ? 60 : 1)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                header
                periodPicker
                    .padding(.top, Theme.Space.l)
                balanceStory
                    .padding(.top, Theme.Space.xl)
                plot
                    .padding(.top, Theme.Space.l)
                selectedDayStrip
                    .padding(.top, Theme.Space.m)
                sourceSection
                    .padding(.top, Theme.Space.xxl)
                sessionSection
                    .padding(.top, Theme.Space.xxl)
                insightScene
                    .padding(.top, Theme.Space.xxl)
                if let journey = env.journey, let progress = env.journeyProgress {
                    journeySection(journey: journey, progress: progress)
                        .padding(.top, Theme.Space.xxl)
                }
                if showsDoneButton {
                    Button("common.done") { dismiss() }
                        .buttonStyle(.pill)
                        .padding(.top, Theme.Space.xl)
                }
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.top, Theme.Space.l)
                .padding(.bottom, Theme.Space.xxl)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(Night.text)
        .background(Night.ground.ignoresSafeArea())
        .onAppear {
            selectedDay = summaries.last?.day
        }
        .onChange(of: period) { _, _ in
            selectedDay = summaries.last?.day
        }
        .task(id: period) {
            plotIsVisible = reduceMotion
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) { plotIsVisible = true }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            progressText("progress.title")
                .font(.serif(42))
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(periodTitle)
                        streakLabel
                    }
                } else {
                    HStack(spacing: Theme.Space.s) {
                        Text(periodTitle)
                        Text(verbatim: "·").foregroundStyle(Night.textGhost)
                        streakLabel
                    }
                }
            }
            .font(.sans(13, weight: .medium))
            .foregroundStyle(Night.textMuted)
        }
    }

    private var streakLabel: some View {
        progressText("progress.streak \(env.streakDays)")
            .contentTransition(.numericText(value: Double(env.streakDays)))
    }

    private var periodPicker: some View {
        Picker(selection: $period) {
            ForEach(ProgressPeriod.allCases) { option in
                progressText(option.title).tag(option)
            }
        } label: {
            progressText("progress.period.label")
        }
        .pickerStyle(.segmented)
        .tint(Night.cobalt)
        .frame(minHeight: Theme.minTouchTarget)
    }

    /// A period is read as an exchange, not as three disconnected dashboard metrics.
    private var balanceStory: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    earnedValue
                    earnedLabel
                }
                VStack(alignment: .leading, spacing: 2) {
                    earnedValue
                    earnedLabel
                }
            }

            BalanceRail(
                earnedSeconds: totals.earnedSeconds,
                consumedSeconds: totals.consumedSeconds,
                isVisible: plotIsVisible
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    usedValue
                    Spacer()
                    differenceValue(alignment: .trailing)
                }
                VStack(alignment: .leading, spacing: 5) {
                    usedValue
                    differenceValue(alignment: .leading)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: period)
        .accessibilityElement(children: .combine)
    }

    private var earnedValue: some View {
        Text(duration(totals.earnedSeconds))
            .font(.serif(58))
            .foregroundStyle(totals.earnedSeconds > 0 ? Night.text : Night.textMuted)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .contentTransition(.numericText(value: Double(totals.earnedSeconds)))
    }

    private var earnedLabel: some View {
        progressText("progress.earned")
            .font(.sans(14, weight: .medium))
            .foregroundStyle(Night.textMuted)
    }

    private var usedValue: some View {
        progressText(hasCompleteUsageHistory
                     ? "progress.usedValue \(duration(totals.consumedSeconds))"
                     : "progress.usedRecordedValue \(duration(totals.consumedSeconds))")
            .font(.sans(14, weight: .semibold))
            .foregroundStyle(Night.textSoft)
    }

    private func differenceValue(alignment: TextAlignment) -> some View {
        progressText(deltaText)
            .font(.sans(13, weight: .medium))
            .foregroundStyle(hasCompleteUsageHistory && totals.netSeconds >= 0 ? Night.cobaltText : Night.textMuted)
            .multilineTextAlignment(alignment)
    }

    @ViewBuilder
    private var plot: some View {
        switch period {
        case .day:
            DayFlowPlot(summary: env.progressToday, isVisible: plotIsVisible)
        case .week:
            WeekFlowPlot(
                summaries: summaries,
                selectedDay: selectedSummary.day,
                isVisible: plotIsVisible,
                locale: locale,
                onSelect: select
            )
        case .month:
            MonthFlowPlot(
                summaries: summaries,
                selectedDay: selectedSummary.day,
                isVisible: plotIsVisible,
                locale: locale,
                onSelect: select
            )
        }
    }

    private var selectedDayStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                selectedDate
                Spacer()
                selectedMetrics
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                selectedDate
                selectedMetrics
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { NightHairline() }
        .overlay(alignment: .bottom) { NightHairline() }
        .contentTransition(.numericText())
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: selectedSummary.day)
        .accessibilityElement(children: .combine)
    }

    private var selectedDate: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dateLabel(selectedSummary.day))
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(Night.textSoft)
            progressText("progress.stepsValue \(selectedSummary.activityAmount.formatted(.number.locale(locale)))")
                .font(.sans(11.5))
                .foregroundStyle(Night.textMuted)
        }
    }

    private var selectedMetrics: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            compactMetric(duration(selectedSummary.earnedSeconds), "progress.earned")
            compactMetric(
                selectedSummary.hasUsageData ? duration(selectedSummary.consumedSeconds) : "—",
                "progress.used"
            )
        }
    }

    private func compactMetric(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value).font(.sans(14, weight: .bold)).monospacedDigit()
            progressText(label).font(.sans(10.5, weight: .medium)).foregroundStyle(Night.textMuted)
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            progressText("progress.sources.title")
                .font(.serif(28))
            progressText("progress.sources.subtitle")
                .font(.sans(13))
                .foregroundStyle(Night.textMuted)

            SourceRibbon(
                steps: totals.stepEarnedSeconds,
                study: totals.studyEarnedSeconds,
                pushups: totals.pushupEarnedSeconds,
                isVisible: plotIsVisible
            )
            .padding(.top, Theme.Space.s)

            sourceRow("figure.walk", "progress.source.movement", totals.stepEarnedSeconds, Night.cobaltText)
            NightHairline(inset: 34)
            sourceRow("book.closed.fill", "progress.source.study", totals.studyEarnedSeconds, Night.textSoft)
            NightHairline(inset: 34)
            sourceRow("figure.strengthtraining.traditional", "progress.source.pushups", totals.pushupEarnedSeconds, Night.moss)
        }
    }

    private func sourceRow(
        _ icon: String,
        _ title: LocalizedStringKey,
        _ seconds: Int,
        _ color: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22)
                .accessibilityHidden(true)
            progressText(title)
                .font(.sans(14, weight: .medium))
            Spacer()
            Text(duration(seconds))
                .font(.sans(14, weight: .bold))
                .foregroundStyle(seconds > 0 ? Night.textSoft : Night.textMuted)
                .monospacedDigit()
        }
        .frame(minHeight: Theme.minTouchTarget)
        .accessibilityElement(children: .combine)
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            progressText("progress.sessions.title")
                .font(.serif(28))
            progressText("progress.sessions.subtitle")
                .font(.sans(13))
                .foregroundStyle(Night.textMuted)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: Theme.Space.s) {
                        sessionMetricRow("\(displayedSessionCount)", "progress.sessions.count")
                        NightHairline()
                        sessionMetricRow(duration(averageSessionSeconds), "progress.sessions.average")
                        NightHairline()
                        sessionMetricRow(duration(totals.returnedSeconds), "progress.sessions.returned")
                    }
                } else {
                    HStack(alignment: .top, spacing: Theme.Space.m) {
                        sessionMetric("\(displayedSessionCount)", "progress.sessions.count")
                        sessionMetric(duration(averageSessionSeconds), "progress.sessions.average")
                        sessionMetric(duration(totals.returnedSeconds), "progress.sessions.returned")
                    }
                }
            }
            .padding(.top, Theme.Space.s)

            if !hasCompleteUsageHistory {
                progressText("progress.usage.partialNote")
                    .font(.sans(12.5, weight: .medium))
                    .foregroundStyle(Night.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if totals.returnedSeconds > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.sans(12, weight: .semibold))
                        .foregroundStyle(Night.cobaltText)
                        .accessibilityHidden(true)
                    progressText("progress.sessions.savedNote \(duration(totals.returnedSeconds))")
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Night.textSoft)
                }
                .padding(.horizontal, Theme.Space.m)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .background(Night.cobaltWash, in: .rect(cornerRadius: Night.panelRadius))
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }

    private func sessionMetric(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.serif(29))
                .foregroundStyle(Night.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            progressText(label)
                .font(.sans(11.5, weight: .medium))
                .foregroundStyle(Night.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func sessionMetricRow(_ value: String, _ label: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline) {
            progressText(label)
                .font(.sans(13, weight: .medium))
                .foregroundStyle(Night.textMuted)
            Spacer()
            Text(value)
                .font(.serif(25))
                .monospacedDigit()
        }
        .frame(minHeight: Theme.minTouchTarget)
        .accessibilityElement(children: .combine)
    }

    private var insightScene: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Spacer(minLength: 90)
            progressText(insightTitle)
                .font(.serif(28))
                .foregroundStyle(Night.text)
                .fixedSize(horizontal: false, vertical: true)
            progressText(insightDetail)
                .font(.sans(13, weight: .medium))
                .foregroundStyle(Night.textSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .bottomLeading)
        .background { SceneBackdrop(scene: .progressPath, fill: .band, veil: 0.06) }
        .clipShape(.rect(cornerRadius: Theme.sheetRadius))
        .accessibilityElement(children: .combine)
    }

    private func journeySection(
        journey: ThirtyDayJourney,
        progress: ThirtyDayJourney.Progress
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    progressText("progress.journey.title").font(.serif(28))
                    progressText("progress.journey.day \(env.journeyDay)")
                        .font(.sans(12.5, weight: .medium))
                        .foregroundStyle(Night.textMuted)
                }
                Spacer()
                Text("\(Int((progress.fraction * 100).rounded()))%")
                    .font(.serif(28))
                    .foregroundStyle(Night.cobaltText)
                    .monospacedDigit()
            }
            TickMeter(progress: progress.fraction, height: 14)
            progressText("progress.journey.steps \(progress.cumulativeSteps.formatted(.number.locale(locale))) \(journey.target.formatted(.number.locale(locale)))")
                .font(.sans(13, weight: .semibold))
                .foregroundStyle(Night.textSoft)
        }
        .padding(Theme.Space.m)
        .background(Night.panel, in: .rect(cornerRadius: Night.panelRadius))
        .accessibilityElement(children: .combine)
    }

    private var averageSessionSeconds: Int {
        guard displayedSessionCount > 0 else { return 0 }
        return totals.consumedSeconds / displayedSessionCount
    }

    private var periodTitle: String {
        switch period {
        case .day:
            String(localized: "progress.period.today", table: "Progress", locale: locale)
        case .week:
            String(localized: "progress.period.lastSevenDays", table: "Progress", locale: locale)
        case .month:
            env.ledger.day.startOfDay()?.formatted(.dateTime.month(.wide).locale(locale)) ?? ""
        }
    }

    private var deltaText: LocalizedStringKey {
        guard hasCompleteUsageHistory else { return "progress.usage.partial" }
        if totals.netSeconds >= 0 {
            return "progress.delta.positive \(duration(totals.netSeconds))"
        }
        return "progress.delta.negative \(duration(abs(totals.netSeconds)))"
    }

    private var insightTitle: LocalizedStringKey {
        guard totals.earnedSeconds > 0 else { return "progress.insight.empty.title" }
        guard hasCompleteUsageHistory else { return "progress.insight.partial.title" }
        if totals.returnedSeconds > 0 { return "progress.insight.returned.title" }
        if let best = summaries.max(by: { $0.earnedSeconds < $1.earnedSeconds }), best.earnedSeconds > 0 {
            return "progress.insight.bestDay.title \(dateLabel(best.day))"
        }
        return "progress.insight.moving.title"
    }

    private var insightDetail: LocalizedStringKey {
        guard totals.earnedSeconds > 0 else { return "progress.insight.empty.detail" }
        guard hasCompleteUsageHistory else { return "progress.insight.partial.detail" }
        if totals.returnedSeconds > 0 {
            return "progress.insight.returned.detail \(duration(totals.returnedSeconds))"
        }
        return "progress.insight.ratio.detail \(consumptionPercent)"
    }

    private var consumptionPercent: Int {
        guard totals.earnedSeconds > 0 else { return 0 }
        return Int((Double(totals.consumedSeconds) / Double(totals.earnedSeconds) * 100).rounded())
    }

    private func select(_ day: DayKey) {
        guard selectedDay != day else { return }
        selectedDay = day
        HapticManager.trigger(.light)
    }

    private func dateLabel(_ day: DayKey) -> String {
        guard let date = day.startOfDay() else { return day.description }
        if day == env.ledger.day {
            return String(localized: "progress.period.today", table: "Progress", locale: locale)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().locale(locale))
    }

    private func duration(_ seconds: Int) -> String {
        Duration.seconds(max(0, seconds)).formatted(
            .units(
                allowed: [.hours, .minutes],
                width: .narrow,
                maximumUnitCount: 2
            )
            .locale(locale)
        )
    }
}

private enum ProgressPeriod: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: Self { self }
    var title: LocalizedStringKey {
        switch self {
        case .day: "progress.period.day"
        case .week: "progress.period.week"
        case .month: "progress.period.month"
        }
    }
}

private struct BalanceRail: View {
    let earnedSeconds: Int
    let consumedSeconds: Int
    let isVisible: Bool

    private var maximum: CGFloat { CGFloat(max(earnedSeconds, consumedSeconds, 60)) }

    var body: some View {
        VStack(spacing: 7) {
            rail(value: earnedSeconds, color: Night.cobalt, height: 10)
            rail(value: consumedSeconds, color: Night.textDim, height: 4)
        }
        .accessibilityHidden(true)
    }

    private func rail(value: Int, color: Color, height: CGFloat) -> some View {
        Capsule()
            .fill(color)
            .frame(height: height)
            .scaleEffect(x: isVisible ? CGFloat(value) / maximum : 0.02, anchor: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Night.text.opacity(0.08), in: .capsule)
    }
}

private struct DayFlowPlot: View {
    let summary: DaySummary
    let isVisible: Bool

    private var maxValue: CGFloat { CGFloat(max(summary.earnedSeconds, summary.consumedSeconds, 60)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: Theme.Space.l) {
                    flowColumns
                    Spacer(minLength: 0)
                    stepMetric
                }
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    flowColumns
                    stepMetric
                }
            }
            progressText(summary.earnedSeconds == 0 && summary.consumedSeconds == 0
                         ? "progress.plot.empty"
                         : "progress.plot.dayCaption")
                .font(.sans(12.5))
                .foregroundStyle(Night.textMuted)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .bottomLeading)
        .background(Night.panel, in: .rect(cornerRadius: Night.panelRadius))
    }

    private var flowColumns: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.l) {
            flowColumn(value: summary.earnedSeconds, title: "progress.earned", color: Night.cobalt)
            flowColumn(value: summary.consumedSeconds, title: "progress.used", color: Night.textDim)
        }
    }

    private var stepMetric: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("\(summary.activityAmount.formatted())")
                .font(.serif(27))
                .foregroundStyle(summary.activityAmount > 0 ? Night.text : Night.textMuted)
                .monospacedDigit()
            progressText("progress.steps")
                .font(.sans(11.5, weight: .medium))
                .foregroundStyle(Night.textMuted)
        }
    }

    private func flowColumn(
        value: Int,
        title: LocalizedStringKey,
        color: Color
    ) -> some View {
        VStack(spacing: Theme.Space.s) {
            Capsule()
                .fill(color)
                .frame(width: 28, height: 104)
                .scaleEffect(y: isVisible ? max(0.04, CGFloat(value) / maxValue) : 0.04, anchor: .bottom)
                .frame(height: 104, alignment: .bottom)
            progressText(title)
                .font(.sans(11.5, weight: .medium))
                .foregroundStyle(Night.textMuted)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WeekFlowPlot: View {
    let summaries: [DaySummary]
    let selectedDay: DayKey
    let isVisible: Bool
    let locale: Locale
    let onSelect: (DayKey) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var peak: CGFloat {
        CGFloat(max(300, summaries.flatMap { [$0.earnedSeconds, $0.consumedSeconds] }.max() ?? 0))
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.s) {
            ForEach(Array(summaries.enumerated()), id: \.element.day) { index, summary in
                Button { onSelect(summary.day) } label: {
                    VStack(spacing: Theme.Space.s) {
                        HStack(alignment: .bottom, spacing: 3) {
                            bar(summary.earnedSeconds, color: Night.cobalt, delay: Double(index) * 0.035)
                            bar(summary.consumedSeconds, color: Night.textDim, delay: Double(index) * 0.035 + 0.04)
                        }
                        Text(weekday(summary.day))
                            .font(.sans(11.5, weight: selectedDay == summary.day ? .semibold : .regular))
                            .foregroundStyle(selectedDay == summary.day ? Night.text : Night.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        selectedDay == summary.day ? Night.cobaltWash : .clear,
                        in: .rect(cornerRadius: 12)
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(ProgressPlotButtonStyle())
                .accessibilityLabel(Text(date(summary.day)))
                .accessibilityValue(summary.hasUsageData
                    ? progressText("progress.day.a11y \(summary.earnedMinutes) \(summary.consumedMinutes)")
                    : progressText("progress.day.earnedA11y \(summary.earnedMinutes)"))
            }
        }
        .frame(height: 210, alignment: .bottom)
        .padding(.horizontal, 4)
    }

    private func bar(_ seconds: Int, color: Color, delay: Double) -> some View {
        Capsule()
            .fill(color)
            .frame(width: 11, height: 150)
            .scaleEffect(y: isVisible ? max(0.025, CGFloat(seconds) / peak) : 0.025, anchor: .bottom)
            .frame(height: 150, alignment: .bottom)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(delay), value: isVisible)
    }

    private func weekday(_ day: DayKey) -> String {
        day.startOfDay()?.formatted(.dateTime.weekday(.narrow).locale(locale)) ?? ""
    }

    private func date(_ day: DayKey) -> String {
        day.startOfDay()?.formatted(.dateTime.weekday(.wide).day().month().locale(locale)) ?? day.description
    }
}

private struct MonthFlowPlot: View {
    let summaries: [DaySummary]
    let selectedDay: DayKey
    let isVisible: Bool
    let locale: Locale
    let onSelect: (DayKey) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(repeating: GridItem(.fixed(44), spacing: 3), count: 7)
    private var peak: Double { Double(max(300, summaries.map(\.earnedSeconds).max() ?? 0)) }

    private var leadingBlanks: Int {
        guard let date = summaries.first?.day.startOfDay() else { return 0 }
        let calendar = Calendar.current
        return (calendar.component(.weekday, from: date) - calendar.firstWeekday + 7) % 7
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(veryShortWeekdays.indices, id: \.self) { index in
                    Text(veryShortWeekdays[index])
                        .font(.sans(10.5, weight: .medium))
                        .foregroundStyle(Night.textMuted)
                        .frame(width: 44)
                }
            }
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(width: 44, height: 44)
                }
                ForEach(Array(summaries.enumerated()), id: \.element.day) { index, summary in
                    Button { onSelect(summary.day) } label: {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(cellColor(summary))
                            if summary.consumedSeconds > 0 {
                                Capsule()
                                    .fill(Night.textSoft.opacity(0.72))
                                    .frame(width: consumedMarkerWidth(summary), height: 2)
                                    .padding(.bottom, 5)
                            }
                            Text("\(summary.day.day)")
                                .font(.sans(11.5, weight: selectedDay == summary.day ? .bold : .medium))
                                .foregroundStyle(selectedDay == summary.day ? Color.white : Night.textSoft)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .padding(6)
                        }
                        .frame(width: 44, height: 44)
                        .overlay {
                            if selectedDay == summary.day {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Night.cobaltText, lineWidth: 1.5)
                            }
                        }
                        .scaleEffect(isVisible ? 1 : 0.82)
                        .opacity(isVisible ? 1 : 0)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.38).delay(min(0.28, Double(index) * 0.012)),
                            value: isVisible
                        )
                    }
                    .buttonStyle(ProgressPlotButtonStyle())
                    .accessibilityLabel(Text(date(summary.day)))
                    .accessibilityValue(summary.hasUsageData
                        ? progressText("progress.day.a11y \(summary.earnedMinutes) \(summary.consumedMinutes)")
                        : progressText("progress.day.earnedA11y \(summary.earnedMinutes)"))
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, Theme.Space.m)
        .background(Night.panel, in: .rect(cornerRadius: Night.panelRadius))
    }

    private var veryShortWeekdays: [String] {
        var symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let offset = max(0, Calendar.current.firstWeekday - 1)
        symbols = Array(symbols[offset...] + symbols[..<offset])
        return symbols.map { $0.uppercased(with: locale) }
    }

    private func cellColor(_ summary: DaySummary) -> Color {
        guard summary.earnedSeconds > 0 else { return Night.forestLift.opacity(0.48) }
        return Night.cobalt.opacity(0.22 + 0.78 * Double(summary.earnedSeconds) / peak)
    }

    private func consumedMarkerWidth(_ summary: DaySummary) -> CGFloat {
        min(32, max(6, 32 * CGFloat(summary.consumedSeconds) / CGFloat(peak)))
    }

    private func date(_ day: DayKey) -> String {
        day.startOfDay()?.formatted(.dateTime.weekday(.wide).day().month().locale(locale)) ?? day.description
    }
}

private struct SourceRibbon: View {
    let steps: Int
    let study: Int
    let pushups: Int
    let isVisible: Bool

    private var total: CGFloat { CGFloat(max(steps + study + pushups, 1)) }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 3) {
                segment(steps, color: Night.cobalt, width: geometry.size.width)
                segment(study, color: Night.textSoft, width: geometry.size.width)
                segment(pushups, color: Night.moss, width: geometry.size.width)
            }
            .scaleEffect(x: isVisible ? 1 : 0.02, anchor: .leading)
        }
        .frame(height: 14)
        .clipShape(.capsule)
        .background(Night.text.opacity(0.08), in: .capsule)
        .accessibilityHidden(true)
    }

    private func segment(_ seconds: Int, color: Color, width: CGFloat) -> some View {
        color.frame(width: max(seconds > 0 ? 3 : 0, width * CGFloat(seconds) / total))
    }
}

private struct ProgressPlotButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private func progressText(_ key: LocalizedStringKey) -> Text {
    Text(key, tableName: "Progress")
}

#Preview {
    WeekView(showsDoneButton: false)
        .environment(AppEnvironment(
            screenTime: MockScreenTimeService(status: .approved),
            health: MockHealthKitService(hasRequested: true, steps: 3_842)
        ))
}
