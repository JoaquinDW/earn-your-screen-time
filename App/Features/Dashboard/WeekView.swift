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

    @State private var chartIsVisible = false

    var showsDoneButton = true

    private var week: [DaySummary] { env.week }
    private var peakMinutes: Int { max(20, week.map(\.earnedMinutes).max() ?? 0) }
    private var kilometres: Double {
        Double(week.reduce(0) { $0 + $1.activityAmount }) * Projection.metresPerStep / 1_000
    }

    var body: some View {
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

            Spacer(minLength: 20)

            if showsDoneButton {
                Button("common.done") { dismiss() }
                    .buttonStyle(.pill(.sage))
            }
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.xl)
        .padding(.bottom, Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        .fill(day.day == env.ledger.day ? Theme.coral : Theme.sage)
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
        return date.formatted(.dateTime.weekday(.narrow))
    }

    private func weekdayName(for day: DaySummary) -> String {
        guard let date = day.day.startOfDay() else { return "" }
        return date.formatted(.dateTime.weekday(.wide))
    }
}

#Preview {
    WeekView()
        .environment(AppEnvironment(
            screenTime: MockScreenTimeService(status: .approved),
            health: MockHealthKitService(hasRequested: true, steps: 3_842)
        ))
}
