import SwiftUI

/// Semantic design tokens for *"there is a life outside the screen"* (design v6).
///
/// v6 moved the whole product onto a nocturnal ground: near-black and deep forest, with the
/// illustrations carrying every other colour in the app. `Night` holds the raw palette; `Theme`
/// is the semantic layer every screen actually reads, so a screen asks for *ink* or *muted* and
/// never for a hex value.
///
/// There is exactly **one** accent: cobalt. It means *earned, and interactive*. It is absent
/// while nothing has been earned and floods in with progress, so colour itself is a progress
/// signal rather than a decoration — and because it is the only accent, its scarcity is what
/// makes it read. There is no red anywhere: running out of screen time is not an error, it is
/// just the next lap (PRD §28).
///
/// The v5 two-accent names (`coral*`, `sage*`) survive as aliases so the screens authored
/// against them keep compiling; they all resolve into the one cobalt system.
enum Theme {

    // MARK: - Ground

    /// Page ground. A hair off black, so the artwork's own blacks still read against it.
    static let background = Night.ground
    /// The deepest tone, where the ground has to out-black an illustration.
    static let backgroundLit = Night.groundDeep
    /// Raised surface: panels, cards, list rows.
    static let paper = Night.panel
    /// The unearned fill: spend pills and quiet chips before there is anything to spend.
    static let stone = Night.forestLift

    static let ink = Night.text
    static let muted = Night.textMuted
    /// The hairlines that replace cards throughout the design.
    static let line = Night.line

    // MARK: - The one accent

    /// Earned, and every primary action.
    static let cobalt = Night.cobalt
    /// Cobalt at text weight. On the dark ground this *lifts* rather than deepens — the same
    /// role v5's `cobaltDeep` played on ivory, inverted for the ground it now sits on.
    static let cobaltDeep = Night.cobaltText
    static let cobaltPressed = Night.cobaltLift
    /// The tint spend pills pick up once there is a balance.
    static let cobaltTint = Night.cobaltWash
    static let cobaltSoft = Night.cobaltWash
    /// The quiet ink wash: captions, disabled marks, everything that is not earned yet.
    static let wash = Night.textFaint

    // MARK: - Roles
    //
    // Named by meaning so screens do not reach for raw colours.

    /// Earned / available screen time.
    static let earned = Night.cobaltText
    /// Activity: steps, distance to the next reward.
    static let activity = Night.cobaltText
    /// Already banked and counted. Quieter than cobalt on purpose.
    static let credited = Night.moss
    /// Locked state. Calm and neutral by design.
    static let locked = Night.textMuted
    static let surface = Night.panel

    // Compatibility aliases for screens authored against the v5 two-accent palette.
    static let coral = Night.cobalt
    static let coralLight = Night.cobaltWash
    static let coralDeep = Night.cobaltText
    static let coralPressed = Night.cobaltLift
    static let sage = Night.cobalt
    static let sageLight = Night.cobaltWash
    static let sageDeep = Night.cobaltText
    static let sagePressed = Night.cobaltLift
    static let sky = Night.forestLift
    static let skyDeep = Night.textFaint

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

    static let cornerRadius: CGFloat = 18
    /// The sheet lip the content pulls over the illustration.
    static let sheetRadius: CGFloat = 28
    /// Apple HIG minimum touch target.
    static let minTouchTarget: CGFloat = 44
    /// Every primary action in the design is a full-width pill of this height.
    static let buttonHeight: CGFloat = 56
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
