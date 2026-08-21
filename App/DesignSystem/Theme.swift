import SwiftUI

/// Semantic design tokens for the "Move first. Scroll later." identity.
///
/// The palette is warm paper: cream ground, ink text, a soft coral for *earning* and a sage
/// green for *earned*. There is no red anywhere — running out of screen time is not an error,
/// it is just the next lap (PRD §28).
///
/// The design is a single, deliberately light paper palette; the app pins itself to the light
/// appearance rather than inventing a dark variant the design does not specify.
enum Theme {

    // MARK: - Palette

    /// Page ground.
    static let background = Color(hex: 0xFAF3E7)
    /// Slightly brighter paper, used for the arrival/reward scene.
    static let paper = Color(hex: 0xFFFAF2)
    static let ink = Color(hex: 0x24211E)
    static let muted = Color(hex: 0x6F685F)
    /// The hairlines that replace cards throughout the design.
    static let line = Color(hex: 0x24211E).opacity(0.14)

    /// Progress toward the next reward — the trail, the accent numbers.
    static let coral = Color(hex: 0xD9805F)
    static let coralLight = Color(hex: 0xF3D6C8)
    static let coralDeep = Color(hex: 0xA85536)
    static let coralPressed = Color(hex: 0x8F4529)

    /// Screen time already earned.
    static let sage = Color(hex: 0x8FAE86)
    static let sageLight = Color(hex: 0xDCEAD4)
    static let sageDeep = Color(hex: 0x4F6B4C)
    static let sagePressed = Color(hex: 0x3D5439)

    static let sky = Color(hex: 0xCFE1E8)
    static let skyDeep = Color(hex: 0x5B7D8D)

    // MARK: - Roles
    //
    // Named by meaning so screens do not reach for raw colours.

    /// Earned / available screen time.
    static let earned = sageDeep
    /// Activity: steps, distance to the next reward.
    static let activity = coralDeep
    /// Locked state. Calm and neutral by design.
    static let locked = muted
    static let surface = paper

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
