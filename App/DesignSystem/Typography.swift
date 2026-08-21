import SwiftUI
import UIKit
import os

/// Two typefaces, each with one job.
///
/// **Instrument Serif** carries every number and every headline — it is the whole identity, and
/// its italic does the connective lines ("from your next", "you could go"). **Figtree** carries
/// the running text. Both are bundled (SIL Open Font License, see `App/Resources/Fonts`), and
/// both fall back to the system font if registration ever fails, so a missing file degrades
/// the look instead of the layout.
///
/// Sizes are passed explicitly rather than hidden behind a scale: the design uses display type
/// as a graphic element, so a headline is 56pt because it is *that* headline, not because it is
/// "title". `relativeTo:` still hands Dynamic Type the right growth curve.
extension Font {

    /// Display serif. `italic` selects the drawn italic, never a synthesised slant.
    static func serif(
        _ size: CGFloat,
        italic: Bool = false,
        relativeTo textStyle: Font.TextStyle = .largeTitle
    ) -> Font {
        let name = italic ? FontFamily.serifItalic : FontFamily.serifRegular
        guard FontFamily.isAvailable(name) else {
            let system = Font.system(size: size, weight: .regular, design: .serif)
            return italic ? system.italic() : system
        }
        return .custom(name, size: size, relativeTo: textStyle)
    }

    /// Running text.
    static func sans(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        let name = FontFamily.sans(for: weight)
        guard FontFamily.isAvailable(name) else {
            return .system(size: size, weight: weight)
        }
        return .custom(name, size: size, relativeTo: textStyle)
    }

    /// The small uppercase eyebrow the design puts above most headlines.
    static var eyebrow: Font { .sans(11.5, weight: .semibold, relativeTo: .caption) }
}

enum FontFamily {
    static let serifRegular = "InstrumentSerif-Regular"
    static let serifItalic = "InstrumentSerif-Italic"

    static func sans(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: "Figtree-Bold"
        case .semibold, .medium: "Figtree-SemiBold"
        default: "Figtree-Regular"
        }
    }

    /// `UIFont(name:)` is the only honest check that a bundled font actually registered.
    /// Cached because it is asked on nearly every view body.
    static func isAvailable(_ name: String) -> Bool {
        if let known = cache.withLock({ $0[name] }) { return known }
        let available = UIFont(name: name, size: 12) != nil
        cache.withLock { $0[name] = available }
        return available
    }

    private static let cache = OSAllocatedUnfairLock(initialState: [String: Bool]())
}

/// The design's signature headline: an upright first line, then the thought completed in the
/// serif italic on a second line. Two keys rather than inline markup so a translator can move
/// the emphasis to wherever the sentence actually turns.
struct SerifHeadline: View {
    let upright: LocalizedStringKey
    let italic: LocalizedStringKey
    var size: CGFloat = 46
    var color: Color = Theme.ink

    var body: some View {
        (
            Text(upright).font(.serif(size))
            + Text(verbatim: "\n")
            + Text(italic).font(.serif(size, italic: true))
        )
        .foregroundStyle(color)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Text conveniences

extension View {
    /// Uppercase, letter-spaced label — the design's section marker.
    func eyebrowStyle(_ color: Color = Theme.muted) -> some View {
        self.font(.eyebrow)
            .textCase(.uppercase)
            .kerning(1.5)
            .foregroundStyle(color)
    }
}
