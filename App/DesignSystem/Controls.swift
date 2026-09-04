import SwiftUI

// MARK: - Buttons

/// The one primary action per screen: a cobalt capsule with a white label.
///
/// v5 set this label in the display serif on an ivory ground. v6 gives the serif to the numerals
/// alone — a button is a control, not a headline — so the label steps back into Figtree and the
/// capsule carries the accent instead.
///
/// The `Tint` cases are v5's two-accent vocabulary. There is only one accent now, so they resolve
/// to the same cobalt; they are kept so the ~20 call sites authored against them still read.
struct PillButtonStyle: ButtonStyle {
    enum Tint {
        case coral
        case sage
    }

    var tint: Tint = .coral
    /// Full-width when the button owns the row, hugging when it sits beside something.
    var isProminent = true

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sans(16, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, isProminent ? Theme.Space.l : 20)
            .padding(.vertical, isProminent ? 0 : 13)
            .frame(maxWidth: isProminent ? .infinity : nil)
            .frame(minHeight: isProminent ? Theme.buttonHeight : Theme.minTouchTarget)
            .background(configuration.isPressed ? Night.cobaltLift : Night.cobalt, in: .capsule)
            .shadow(color: Night.cobalt.opacity(isEnabled ? 0.34 : 0), radius: 18, y: 8)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The secondary action beside a pill: the same shape, drawn as a hairline instead of a fill.
struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sans(16, weight: .medium))
            .foregroundStyle(Night.textSoft)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.buttonHeight)
            .background(configuration.isPressed ? Night.text.opacity(0.06) : .clear, in: .capsule)
            .overlay { Capsule().stroke(Night.edge, lineWidth: 1) }
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Secondary navigation ("Back"). Present, but never competing with the pill.
struct QuietButtonStyle: ButtonStyle {
    var underlined = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sans(14, weight: .semibold))
            .foregroundStyle(underlined ? Night.cobaltText : Night.textMuted)
            .underline(false)
            .frame(minHeight: Theme.minTouchTarget)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static func pill(_ tint: PillButtonStyle.Tint) -> PillButtonStyle { PillButtonStyle(tint: tint) }
    /// The hugging variant, for a button that sits inside a composition rather than owning a row.
    static var pillCompact: PillButtonStyle { PillButtonStyle(isProminent: false) }
}

extension ButtonStyle where Self == OutlineButtonStyle {
    static var outline: OutlineButtonStyle { OutlineButtonStyle() }
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
                    .fill(Night.cobalt)
                    .overlay(Circle().fill(Color.white).frame(width: 6, height: 6))
            } else {
                Circle().strokeBorder(Night.text.opacity(0.22), lineWidth: 1.5)
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
            .fill(Night.forestLift)
            .frame(width: diameter, height: diameter)
            .overlay(
                Text(letter)
                    .font(.serif(diameter * 0.43, relativeTo: .body))
                    .foregroundStyle(Night.textSoft)
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
                    .fill(index < completed ? Night.cobalt : Night.text.opacity(0.14))
                    .frame(height: 3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("onboarding.progress.a11y \(completed) \(total)"))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: completed)
    }
}

// MARK: - Forms

extension View {
    /// The v6 surface for a native `Form`: forest rows on the night ground.
    ///
    /// Kept as a modifier over a real `Form` rather than a hand-rolled list, so `Stepper`,
    /// `Picker` and `Toggle` stay the actual controls with their actual behaviour — a settings
    /// screen is the wrong place to reinvent iOS.
    func settingsSurface() -> some View {
        self
            .listSectionSpacing(20)
            .environment(\.defaultMinListRowHeight, 48)
            .scrollIndicators(.hidden)
    }
}
