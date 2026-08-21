import SwiftUI

// MARK: - Buttons

/// The one primary action per screen: a full-width pill, label set in the display serif.
struct PillButtonStyle: ButtonStyle {
    enum Tint {
        /// Moving forward — the colour of earning.
        case coral
        /// Arriving — the colour of time already earned.
        case sage

        var fill: Color { self == .coral ? Theme.coralDeep : Theme.sageDeep }
        var pressedFill: Color { self == .coral ? Theme.coralPressed : Theme.sagePressed }
    }

    var tint: Tint = .coral
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.serif(20, relativeTo: .title3))
            .foregroundStyle(Theme.paper)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.buttonHeight)
            .background(configuration.isPressed ? tint.pressedFill : tint.fill, in: .capsule)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Secondary navigation ("Back"). Present, but never competing with the pill.
struct QuietButtonStyle: ButtonStyle {
    var underlined = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sans(14, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .underline(underlined)
            .frame(minHeight: Theme.minTouchTarget)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static func pill(_ tint: PillButtonStyle.Tint) -> PillButtonStyle { PillButtonStyle(tint: tint) }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
    static var quietLink: QuietButtonStyle { QuietButtonStyle(underlined: true) }
}

// MARK: - Hairlines

/// The design has no cards: a single hairline is what separates one thing from the next.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: 1)
    }
}

/// The mark that shows whether a row is chosen. Never colour alone — it is a filled disc
/// versus an empty ring, which reads without colour vision.
struct SelectionDot: View {
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isSelected {
                Circle()
                    .fill(Theme.coral)
                    .overlay(Circle().fill(Theme.paper).frame(width: 6, height: 6))
            } else {
                Circle().strokeBorder(Theme.line, lineWidth: 1.5)
            }
        }
        .frame(width: 20, height: 20)
        .contentTransition(.opacity)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isSelected)
    }
}

/// One answer in a question screen: hairline above, dot, label. No card, no fill.
struct ChoiceRow: View {
    let label: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m) {
                SelectionDot(isSelected: isSelected)
                Text(label)
                    .font(.sans(18, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.coralDeep : Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.Space.s)
            .frame(minHeight: 64)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isSelected)
    }
}

/// A monogram disc. Stands in for an app icon: Screen Time never hands us the real one,
/// and the tokens are opaque by design (PRD §27).
struct Monogram: View {
    let letter: String
    var diameter: CGFloat = 44

    var body: some View {
        Circle()
            .fill(Theme.sageLight)
            .frame(width: diameter, height: diameter)
            .overlay(
                Text(letter)
                    .font(.serif(diameter * 0.43, relativeTo: .body))
                    .foregroundStyle(Theme.sageDeep)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Progress

/// The thin segmented rule at the top of onboarding: nine steps, filled as you go.
struct StepDots: View {
    let total: Int
    let completed: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < completed ? Theme.coral : Theme.line)
                    .frame(height: 3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("onboarding.progress.a11y \(completed) \(total)"))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: completed)
    }
}
