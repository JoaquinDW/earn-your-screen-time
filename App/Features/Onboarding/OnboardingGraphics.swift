import SwiftUI

/// The pictures onboarding argues with, so its screens stop arguing in paragraphs.
///
/// Every one of these is *geometry*, not illustration: a calendar of 365 marks, a rule of ticks,
/// a three-beat loop built from the same circles and capsules the rest of the app uses. That is
/// deliberate — the two painted scenes (the ridge and the path) stay the only artwork in
/// onboarding, and everything in between is drawn from the product's own vocabulary.
///
/// They all share one rule: the graphic *arrives*. Nothing here is a static diagram that the eye
/// skips; each one resolves in under a second on appear, which is the beat that buys the single
/// line of copy underneath it the attention a paragraph never got.

// MARK: - Numbers that arrive

/// A number that counts up to its value the first time it appears.
///
/// The count is the argument. "61 days" read cold is a statistic; 0 climbing to 61 in front of
/// you is a number someone is spending, which is the whole point of the screen it lives on.
struct CountUp: View {
    let value: Int
    var font: Font = .serif(96)
    var color: Color = Night.cobaltText
    var duration: Double = 1.1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        Ticker(value: shown, font: font)
            .foregroundStyle(color)
            .onAppear(perform: run)
            // Onboarding's first frame renders against an empty profile, so the real number
            // arrives after `onAppear`. Without this the count animates to the placeholder and
            // stays there.
            .onChange(of: value) { _, _ in run() }
            .accessibilityLabel(Text(value.formatted()))
    }

    private func run() {
        guard !reduceMotion else { shown = Double(value); return }
        withAnimation(.easeOut(duration: duration)) { shown = Double(value) }
    }

    /// `Animatable` on the view itself is the only way to interpolate a value SwiftUI has to
    /// re-render as *text* rather than as a frame.
    private struct Ticker: View, Animatable {
        var value: Double
        let font: Font

        var animatableData: Double {
            get { value }
            set { value = newValue }
        }

        var body: some View {
            Text(Int(value.rounded()).formatted())
                .font(font)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - A year, drawn

/// One year as 365 marks — twelve rows, one per month — with the days lost to scrolling filled.
///
/// This replaces the screen's old paragraph about hours and days. Nobody converts "28 full days
/// every year" into a feeling; everybody converts a fifth of their calendar turning cobalt.
struct YearGrid: View {
    /// Days of the year spent scrolling. Filled from January onward.
    let daysLost: Int
    var tint: Color = Night.cobalt
    var rest: Color = Night.text.opacity(0.11)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled: Double = 0

    /// Non-leap month lengths: exactly 365 marks, so the grid is the year rather than a
    /// rectangle that roughly stands for one.
    private static let monthLengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    private static let columns = 31

    var body: some View {
        Calendar(filled: filled, daysLost: daysLost, tint: tint, rest: rest)
            .aspectRatio(2.05, contentMode: .fit)
            .onAppear(perform: fill)
            .onChange(of: daysLost) { _, _ in
                filled = 0
                fill()
            }
            .accessibilityElement()
            .accessibilityLabel(Text("A calendar year. \(daysLost) of 365 days are spent scrolling."))
    }

    private func fill() {
        guard !reduceMotion else { filled = 1; return }
        withAnimation(.easeOut(duration: 1.1).delay(0.15)) { filled = 1 }
    }

    private struct Calendar: View, Animatable {
        var filled: Double
        let daysLost: Int
        let tint: Color
        let rest: Color

        var animatableData: Double {
            get { filled }
            set { filled = newValue }
        }

        var body: some View {
            Canvas(rendersAsynchronously: false) { context, size in
                let colGap: CGFloat = 2.4
                let rowGap: CGFloat = 3.2
                let cell = (size.width - colGap * CGFloat(columns - 1)) / CGFloat(columns)
                let rowHeight = (size.height - rowGap * CGFloat(monthLengths.count - 1))
                    / CGFloat(monthLengths.count)
                let lit = Int((Double(daysLost) * filled).rounded())

                var day = 0
                for (row, length) in monthLengths.enumerated() {
                    for column in 0..<length {
                        let rect = CGRect(
                            x: CGFloat(column) * (cell + colGap),
                            y: CGFloat(row) * (rowHeight + rowGap),
                            width: cell,
                            height: rowHeight
                        )
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: min(1.6, cell / 2)),
                            with: .color(day < lit ? tint : rest)
                        )
                        day += 1
                    }
                }
            }
        }

        private var columns: Int { YearGrid.columns }
        private var monthLengths: [Int] { YearGrid.monthLengths }
    }
}

// MARK: - The loop, played once

/// Walk **or** push up → earn → spend, revealed one beat at a time.
///
/// Both ways in are on the screen at once, and the italic "or" between them is the whole point:
/// walking is the honest default and push-ups are the one people lean forward at, so burying
/// them behind an optional screen later meant most of the flow read as a pedometer. They also
/// happen to be the same trade — 500 steps and 5 push-ups both buy 5 minutes — which is an
/// argument no sentence makes as fast as two rows stacked above one reward.
///
/// Sequence does the explaining: you cannot watch the rule fill, the dots count and the chip
/// land without understanding that one caused the other. It plays once and holds — a loop would
/// compete with the copy it is explaining.
struct EarnLoopDiagram: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            beatRow(1, icon: "figure.walk", title: "Walk 500 steps") {
                TickMeter(progress: beat >= 1 ? 1 : 0, height: 14, tickCount: 16)
                    .frame(width: 76)
            }
            alternative
            beatRow(2, icon: "figure.strengthtraining.traditional", title: "5 push-ups") {
                RepDots(total: 5, filled: beat >= 2 ? 5 : 0)
            }
            connector(after: 2)
            beatRow(3, icon: "plus", title: "Earn 5 minutes") {
                Text("+5:00")
                    .font(.sans(13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Night.cobalt, in: .capsule)
                    .scaleEffect(beat >= 3 ? 1 : 0.6)
            }
            connector(after: 3)
            beatRow(4, icon: "iphone", title: "Choose when to use them") {
                Text("5:00")
                    .font(.sans(13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Night.cobaltText)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .overlay { Capsule().stroke(Night.cobalt.opacity(0.55)) }
                    .scaleEffect(beat >= 4 ? 1 : 0.6)
            }
        }
        .task { await play() }
        .accessibilityElement(children: .combine)
    }

    private func play() async {
        guard !reduceMotion else { beat = 4; return }
        // The push-up row lands quickly after the walking row — they are one choice, not two
        // steps — and the reward waits a beat longer so it reads as the consequence of either.
        for (step, delay) in [(1, 260), (2, 380), (3, 640), (4, 620)] {
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.4)) { beat = step }
        }
    }

    /// What sits between the two ways in, where a connector sits everywhere else: the serif
    /// italic the identity uses for its connective words. A second arrow here would have said
    /// "and then"; this says "either".
    private var alternative: some View {
        Text("or")
            .font(.serif(19, italic: true))
            .foregroundStyle(beat >= 2 ? Night.textSoft : Night.textGhost)
            .frame(width: 54, height: 26)
            .accessibilityHidden(true)
    }

    private func beatRow<Trailing: View>(
        _ index: Int,
        icon: String,
        title: LocalizedStringKey,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let isLit = beat >= index
        return HStack(spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(isLit ? Night.cobaltText : Night.textFaint)
                .frame(width: 54, height: 54)
                .background(isLit ? Night.cobaltWash : Night.forestLift, in: .circle)
            Text(title)
                .font(.sans(17, weight: .semibold))
                .foregroundStyle(isLit ? Night.text : Night.textFaint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Space.s)
            trailing()
                .opacity(isLit ? 1 : 0)
        }
        .opacity(isLit ? 1 : 0.45)
    }

    private func connector(after index: Int) -> some View {
        Rectangle()
            .fill(beat > index ? Night.cobalt.opacity(0.55) : Night.text.opacity(0.12))
            .frame(width: 1.5, height: 30)
            .padding(.leading, 26.5)
            .accessibilityHidden(true)
    }
}

/// The reps a set is worth, filled one at a time — the push-up row's answer to the tick rule.
private struct RepDots: View {
    let total: Int
    let filled: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < filled ? Night.cobalt : Night.text.opacity(0.16))
                    .frame(width: 9, height: 9)
                    .scaleEffect(index < filled ? 1 : 0.7)
                    .animation(.snappy(duration: 0.28).delay(Double(index) * 0.07), value: filled)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Baseline to goal

/// The distance between where someone already walks and where their first goal sits.
///
/// Shown as the app's own tick rule: the ground they already cover is soft, and the increment is
/// the only cobalt on screen. The sliver is the argument — the goal is deliberately small, and a
/// sentence claiming that is far less convincing than seeing how little of the rule it takes.
struct GoalRule: View {
    let baseline: Int
    let goal: Int
    var tickCount = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var extended = false

    private var baselineShare: Double {
        guard goal > 0 else { return 0 }
        return min(1, max(0, Double(baseline) / Double(goal)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: 0) {
                ForEach(0..<tickCount, id: \.self) { index in
                    Rectangle()
                        .fill(color(at: index))
                        .frame(width: 1.5)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 30)

            HStack(alignment: .firstTextBaseline) {
                endpoint("Your usual day", baseline, color: Night.textSoft)
                Spacer(minLength: Theme.Space.m)
                endpoint("First goal", goal, color: Night.cobaltText, alignment: .trailing)
            }
        }
        .onAppear {
            guard !reduceMotion else { extended = true; return }
            withAnimation(.easeOut(duration: 0.85).delay(0.25)) { extended = true }
        }
    }

    private func color(at index: Int) -> Color {
        let position = Double(index) / Double(tickCount)
        if position < baselineShare { return Night.text.opacity(0.28) }
        return extended ? Night.cobalt : Night.text.opacity(0.1)
    }

    private func endpoint(
        _ label: LocalizedStringKey,
        _ value: Int,
        color: Color,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.sans(12.5, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Text(value.formatted())
                .font(.serif(30))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Choices that answer themselves

/// A single-choice question that advances the moment it is answered.
///
/// Onboarding used to charge two taps for every question: one to choose, one to confirm a choice
/// nothing could invalidate. The confirmation beat below — the row snapping to cobalt while the
/// screen holds for a quarter second — is the receipt, and "Back" is the correction.
struct OnboardingChoices<Value: Hashable>: View {
    let values: [Value]
    let selected: Value?
    let label: (Value) -> LocalizedStringKey
    let choose: (Value) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pending: Value?

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            ForEach(values, id: \.self) { value in
                let isSelected = (pending ?? selected) == value
                Button { tap(value) } label: {
                    HStack(spacing: Theme.Space.m) {
                        Text(label(value))
                            .font(.sans(16.5, weight: .semibold))
                            .foregroundStyle(Night.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 19))
                            .foregroundStyle(isSelected ? Night.cobaltText : Night.textFaint)
                    }
                    .padding(.horizontal, Theme.Space.m)
                    .frame(minHeight: 62)
                    .background(
                        isSelected ? Night.cobaltWash : Night.panel,
                        in: .rect(cornerRadius: Theme.cornerRadius)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cornerRadius)
                            .stroke(isSelected ? Night.cobalt : Night.edge, lineWidth: isSelected ? 1.5 : 1)
                    }
                    .scaleEffect(isSelected && !reduceMotion ? 1.015 : 1)
                }
                .buttonStyle(.plain)
                .disabled(pending != nil)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func tap(_ value: Value) {
        guard pending == nil else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { pending = value }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 260))
            choose(value)
        }
    }
}

#Preview("Year") {
    VStack(spacing: Theme.Space.xl) {
        CountUp(value: 61)
        YearGrid(daysLost: 61)
        GoalRule(baseline: 6_400, goal: 7_000)
        EarnLoopDiagram()
    }
    .padding(Theme.Space.gutter)
    .frame(maxHeight: .infinity)
    .background(Night.ground)
    .foregroundStyle(Night.text)
}
