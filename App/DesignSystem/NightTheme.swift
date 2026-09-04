import SwiftUI

/// The dark, illustrated half of the app — design v6, *"there is a life outside the screen"*.
///
/// v5's ivory `Theme` is still the ground for every utility screen (Progress, Settings,
/// onboarding, paywall). v6 introduces a second, *nocturnal* ground for the two screens the
/// illustrations live on: Home and Earn time. Rather than flip `Theme` and break every screen
/// that was drawn for paper, the two palettes sit side by side and a screen picks one.
///
/// The rules are the same as v5's, restated in the dark: one accent (cobalt) that means *earned
/// and interactive*, one quiet positive (moss) for what has already been credited, and no red
/// anywhere. Everything else is forest and near-black, so the artwork carries the colour.
enum Night {

    // MARK: - Ground

    /// The app ground. Sits a hair off black so the artwork's own blacks still read.
    static let ground = Color(hex: 0x070E0D)
    /// The deepest tone, used where the ground has to out-black the illustration.
    static let groundDeep = Color(hex: 0x05100C)
    /// Raised surfaces: the spend list, the rule cards.
    static let panel = Color(hex: 0x0B1712)
    /// Forest greens for fills that need to lift off the panel without becoming grey.
    static let forest = Color(hex: 0x143326)
    static let forestLift = Color(hex: 0x1B2A24)

    // MARK: - The one accent

    /// Earned, and every primary action. Never decorative.
    static let cobalt = Color(hex: 0x2E5CE6)
    static let cobaltLift = Color(hex: 0x4674FF)
    /// Cobalt at text weight — links and inline emphasis, where the fill would be too heavy.
    static let cobaltText = Color(hex: 0x6E97FF)
    static let cobaltWash = Color(hex: 0x2E5CE6).opacity(0.16)
    /// Already banked. Quieter than cobalt on purpose: credit is a fact, not an invitation.
    static let moss = Color(hex: 0x8CBF6B)

    // MARK: - Ink

    static let text = Color(hex: 0xECF3EE)
    static let textSoft = Color(hex: 0xB9CCC2)
    static let textMuted = Color(hex: 0x93A79D)
    static let textDim = Color(hex: 0x7E9389)
    static let textFaint = Color(hex: 0x61756B)
    static let textGhost = Color(hex: 0x4E6159)

    /// The hairline that separates rows inside a panel.
    static let line = Color(hex: 0xECF3EE).opacity(0.07)
    /// The hairline that draws a panel's own edge.
    static let edge = Color(hex: 0xECF3EE).opacity(0.09)

    static let panelRadius: CGFloat = 18
    static let cardRadius: CGFloat = 18
}

// MARK: - Controls

/// The v6 primary action: a cobalt capsule, sans-serif, sized to its label.
///
/// v5's `PillButtonStyle` is full-width and sets its label in the display serif; on the dark
/// screens the serif belongs to the numerals alone, so the button steps back into Figtree.
struct NightPillButtonStyle: ButtonStyle {
    /// Full-width when the button owns the row, hugging when it sits next to something.
    var isProminent = true

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sans(15, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, isProminent ? Theme.Space.l : 20)
            .padding(.vertical, 13)
            .frame(maxWidth: isProminent ? .infinity : nil)
            .frame(minHeight: Theme.minTouchTarget)
            .background(configuration.isPressed ? Night.cobaltLift : Night.cobalt, in: .capsule)
            .shadow(color: Night.cobalt.opacity(isEnabled ? 0.42 : 0), radius: 18, y: 8)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == NightPillButtonStyle {
    static var nightPill: NightPillButtonStyle { NightPillButtonStyle() }
    static func nightPill(prominent: Bool) -> NightPillButtonStyle {
        NightPillButtonStyle(isProminent: prominent)
    }
}

/// The v6 progress form: a rule of hairline ticks, cobalt for the part you own.
///
/// It is deliberately not a bar and not a ring — a ring would turn earning into a fitness goal,
/// and the design asks for something that reads as *measured ground* instead. The tick count is
/// fixed rather than measured, so the rule keeps its density at every width without geometry.
struct TickMeter: View {
    /// 0…1.
    let progress: Double
    var height: CGFloat = 22
    var tint: Color = Night.cobalt
    /// Roughly one tick every 7pt across a phone-width row.
    var tickCount = 46

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double { min(1, max(0, progress)) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tickCount, id: \.self) { index in
                Rectangle()
                    .fill(isEarned(index) ? tint : Night.text.opacity(0.16))
                    .frame(width: 1.5)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: clamped)
        .accessibilityHidden(true)
    }

    private func isEarned(_ index: Int) -> Bool {
        Double(index) / Double(tickCount) < clamped
    }
}

/// The uppercase, letter-spaced marker above every v6 section.
struct NightEyebrow: View {
    let text: LocalizedStringKey
    var color: Color = Night.textMuted

    var body: some View {
        Text(text)
            .font(.sans(11, weight: .medium))
            .textCase(.uppercase)
            .kerning(1.9)
            .foregroundStyle(color)
    }
}

/// A hairline on the dark ground.
struct NightHairline: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Night.line)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}
