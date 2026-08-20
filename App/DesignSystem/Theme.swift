import SwiftUI

/// Semantic design tokens.
///
/// Direction (PRD §28): minimal, native, calm, premium, motivational — never parental-control
/// software. In practice that means system materials and typography, an 8pt spacing rhythm, and
/// a palette where "locked" reads as *neutral*, never as an alarm. There is no red in the
/// primary states: running out of screen time is not an error, it is just the next lap.
enum Theme {

    // MARK: - Colour

    /// Earned / available screen time. The one saturated colour in the app.
    static let earned = Color(light: 0x1B7F55, dark: 0x3BC98C)
    /// Activity (steps, progress toward the next reward).
    static let activity = Color(light: 0xB4762A, dark: 0xE0A85C)
    /// Locked state. Deliberately calm and neutral.
    static let locked = Color(light: 0x6B6F76, dark: 0x9AA0A8)

    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let track = Color(.tertiarySystemFill)
    static let separator = Color(.separator)

    // MARK: - Spacing (8pt rhythm)

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    static let cornerRadius: CGFloat = 20
    /// Apple HIG minimum touch target.
    static let minTouchTarget: CGFloat = 44
}

extension Color {
    /// Declares both themes together so neither is an afterthought.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    fileprivate convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
