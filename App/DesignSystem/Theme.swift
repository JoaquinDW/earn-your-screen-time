import SwiftUI

/// Semantic design tokens for the "Guardian as progress" identity (design v5).
///
/// The ground is ivory — never white, never grey — and it lifts from `#F6F3ED` to `#F9F6F1` as
/// the day is earned. There is exactly **one** accent: cobalt. It is absent while nothing has
/// been earned and floods in with progress, so colour itself is a progress signal rather than a
/// decoration. Everything that is not earned yet is stone or the grey-blue wash.
///
/// There is no red anywhere — running out of screen time is not an error, it is just the next
/// lap (PRD §28).
///
/// The design is a single, deliberately light palette; the app pins itself to the light
/// appearance rather than inventing a dark variant the design does not specify.
enum Theme {

    // MARK: - Ground

    /// Page ground at rest.
    static let background = Color(hex: 0xF6F3ED)
    /// Page ground at a fully earned day. The base lifts toward this as progress grows.
    static let backgroundLit = Color(hex: 0xF9F6F1)
    /// Slightly brighter paper, used for panels and the reward scene.
    static let paper = Color(hex: 0xFAF8F4)
    /// The unearned fill: spend pills and quiet chips before there is anything to spend.
    static let stone = Color(hex: 0xEAE6DF)

    static let ink = Color(hex: 0x1B1C1E)
    static let muted = Color(hex: 0x6F6F74)
    /// The hairlines that replace cards throughout the design.
    static let line = Color(hex: 0x1B1C1E).opacity(0.10)

    // MARK: - The one accent

    /// Earned. The colour that escapes the Guardian into the air around it.
    static let cobalt = Color(hex: 0x1E4DF7)
    /// Cobalt on ivory, for text small enough to need the contrast.
    static let cobaltDeep = Color(hex: 0x1439C8)
    static let cobaltPressed = Color(hex: 0x102E9F)
    /// The tint spend pills pick up once there is a balance.
    static let cobaltTint = Color(hex: 0x1E4DF7).opacity(0.07)
    static let cobaltSoft = Color(hex: 0xE4EAFE)
    /// Grey-blue: the atmosphere's ink wash, and the weight behind the Guardian.
    static let wash = Color(hex: 0x8A8F98)

    // MARK: - Roles
    //
    // Named by meaning so screens do not reach for raw colours. v5 collapses the old two-accent
    // system (coral for earning, sage for earned) into one: cobalt *is* progress, and the
    // difference between "earning" and "earned" is carried by how much of it is present.

    /// Earned / available screen time.
    static let earned = cobaltDeep
    /// Activity: steps, distance to the next reward.
    static let activity = cobaltDeep
    /// Locked state. Calm and neutral by design.
    static let locked = muted
    static let surface = paper

    // Compatibility aliases for screens authored against the previous two-accent palette.
    // They all resolve into the single cobalt system so no screen is left on the old pigments.
    static let coral = cobalt
    static let coralLight = cobaltSoft
    static let coralDeep = cobaltDeep
    static let coralPressed = cobaltPressed
    static let sage = cobalt
    static let sageLight = cobaltSoft
    static let sageDeep = cobaltDeep
    static let sagePressed = cobaltPressed
    static let sky = stone
    static let skyDeep = wash

    // MARK: - Spacing (8pt rhythm, with the design's wider gutters)

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        /// Horizontal page gutter used by every full-screen layout.
        static let gutter: CGFloat = 28
    }

    static let cornerRadius: CGFloat = 20
    /// The sheet lip the content pulls over the illustration.
    static let sheetRadius: CGFloat = 28
    /// Apple HIG minimum touch target.
    static let minTouchTarget: CGFloat = 44
    /// Every primary action in the design is a full-width pill of this height.
    static let buttonHeight: CGFloat = 58
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
