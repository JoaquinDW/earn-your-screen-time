import EarnDomain
import SwiftUI

/// The last seven days, in minutes earned.
///
/// Earned, not spent: how the time was used is the user's business. A day the app was never
/// opened is a real zero rather than a gap, so the shape of the week is honest.
struct WeekView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    @State private var chartIsVisible = false

    var showsDoneButton = true

    private var week: [DaySummary] { env.week }
    private var peakMinutes: Int { max(20, week.map(\.earnedMinutes).max() ?? 0) }
    private var kilometres: Double {
        Double(week.reduce(0) { $0 + $1.activityAmount }) * Projection.metresPerStep / 1_000
    }

    var body: some View {
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(Theme.ink)
        .paperBackground()
        .onAppear {
            guard !chartIsVisible else { return }
            if reduceMotion {
                chartIsVisible = true
            } else {
                withAnimation(.easeOut(duration: 0.42)) { chartIsVisible = true }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("week.title")
                .font(.serif(36))

            Text("week.streak \(env.streakDays)")
                .font(.serif(16, italic: true, relativeTo: .body))
                .foregroundStyle(Theme.muted)
                .contentTransition(.numericText(value: Double(env.streakDays)))
                .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: env.streakDays)
                .padding(.top, 4)
                .padding(.bottom, 26)

            chart

            HStack(spacing: Theme.Space.m) {
                StatPair(
                    value: Text("week.streakValue \(env.streakDays)"),
                    caption: "week.streakCaption",
                    color: Theme.coralDeep,
                    numericValue: Double(env.streakDays)
                )
                StatPair(
                    value: Text("week.distanceValue \(kilometres, specifier: "%.1f")"),
                    caption: "week.distanceCaption",
                    color: Theme.sageDeep,
                    numericValue: kilometres
                )
            }
            .padding(.top, 26)

            // Home holds nothing that is not today (design v5), so the longer arcs — the 30-day
            // journey and the month's totals — live here, where history already lives.
            if let journey = env.journey, let progress = env.journeyProgress {
                journeySection(journey: journey, progress: progress)
                    .padding(.top, Theme.Space.xl)
            }

            monthSection.padding(.top, Theme.Space.xl)

            Spacer(minLength: 20)

            if showsDoneButton {
                Button("common.done") { dismiss() }
                    .buttonStyle(.pill(.sage))
                    .padding(.top, Theme.Space.l)
            }
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.xl)
        .padding(.bottom, Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The longer arcs

    private func journeySection(
        journey: ThirtyDayJourney,
        progress: ThirtyDayJourney.Progress
    ) -> some View {
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
                    .foregroundStyle(Theme.cobalt)
            }
            ProgressView(value: progress.fraction).tint(Theme.cobalt)
            Text(
                "\(progress.cumulativeSteps.formatted(.number.locale(locale))) / \(journey.target.formatted(.number.locale(locale))) steps"
            )
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

    private var journeyTitle: LocalizedStringKey {
        switch env.journeyDay {
        case 7...13: "Week one complete"
        case 14...20: "Halfway there"
        case 30: "You earned your month"
        default: "Your 30-day goal"
        }
    }

    private var journeyMeaning: LocalizedStringKey {
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
                monthMetric(
                    Text(env.monthTotals.steps.formatted(.number.locale(locale))),
                    Text("steps")
                )
                monthMetric(durationText(env.monthTotals.earnedSeconds), Text("earned"))
                monthMetric(Text("\(env.streakDays)"), Text("day streak"))
            }
            Text("\(env.streakDays) days of moving before scrolling.")
                .font(.serif(17, italic: true, relativeTo: .body))
                .foregroundStyle(Theme.muted)
        }
    }

    private func monthMetric(_ value: Text, _ label: Text) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            value.font(.sans(15, weight: .bold)).minimumScaleFactor(0.7).lineLimit(1)
            label.font(.sans(11.5, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func durationText(_ seconds: Int) -> Text {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0 {
            return Text("\(hours)h \(minutes)m")
        }
        return Text("\(minutes)m")
    }

    private var chart: some View {
        HStack(alignment: .bottom, spacing: 11) {
            ForEach(week, id: \.day) { day in
                VStack(spacing: 9) {
                    Text("\(day.earnedMinutes)")
                        .font(.sans(11.5, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .contentTransition(.numericText(value: Double(day.earnedMinutes)))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: day.earnedMinutes)

                    Capsule()
                        .fill(day.day == env.ledger.day ? Theme.cobalt : Theme.wash.opacity(0.45))
                        .frame(height: chartIsVisible ? barHeight(for: day) : 4)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.38), value: barHeight(for: day))

                    Text(weekdayInitial(for: day))
                        .font(.sans(11.5))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(weekdayName(for: day)))
                .accessibilityValue(Text("common.minutesValue \(day.earnedMinutes)"))
            }
        }
        .frame(height: 200, alignment: .bottom)
    }

    /// Bars are scaled against the best day of the week, so a quiet week still reads as a shape.
    private func barHeight(for day: DaySummary) -> CGFloat {
        let available: CGFloat = 142
        guard day.earnedMinutes > 0 else { return 4 }
        return max(6, available * CGFloat(day.earnedMinutes) / CGFloat(peakMinutes))
    }

    private func weekdayInitial(for day: DaySummary) -> String {
        guard let date = day.day.startOfDay() else { return "" }
        return date.formatted(.dateTime.weekday(.narrow).locale(locale))
    }

    private func weekdayName(for day: DaySummary) -> String {
        guard let date = day.day.startOfDay() else { return "" }
        return date.formatted(.dateTime.weekday(.wide).locale(locale))
    }
}

#Preview {
    WeekView()
        .environment(AppEnvironment(
            screenTime: MockScreenTimeService(status: .approved),
            health: MockHealthKitService(hasRequested: true, steps: 3_842)
        ))
}
