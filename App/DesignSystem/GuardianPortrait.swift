import SwiftUI
import UIKit

/// The Guardian as a painted figure, and the two bounded containers that give it a stage
/// outside Home.
///
/// The illustration is authored as five watercolour artboards — the poses the design paints the
/// transformation in. Progress stays continuous: `GuardianPortrait` reads the value *between* two
/// adjacent artboards and cross-fades them, the same way `ramp(_:_:)` reads every number in
/// `GuardianAtmosphere`. Where an artboard has not been painted yet, the nearest shipped painting
/// remains visible; the vector `GuardianFigure` is only used when no painting ships at all.

// MARK: - States

/// The five poses the design paints the Guardian in.
enum GuardianState: String, CaseIterable {
    /// Closed wings, introspective posture, almost no cobalt.
    case resting
    /// Beginning movement, subtle blue strokes.
    case awakening
    /// Wings opening, more energy.
    case rising
    /// Confident posture, wider composition.
    case strong
    /// Fully opened wings, expressive cobalt movement.
    case free

    /// The progress this artboard was painted at — the control point it is read between.
    var anchor: Double {
        switch self {
        case .resting: 0.00
        case .awakening: 0.24
        case .rising: 0.55
        case .strong: 0.86
        case .free: 1.00
        }
    }

    var assetName: String { "guardian-\(rawValue)" }

    /// The pose a given progress reads as, for copy and for anything that needs one name.
    init(progress: Double) {
        switch progress {
        case ..<0.12: self = .resting
        case ..<0.38: self = .awakening
        case ..<0.70: self = .rising
        case ..<0.94: self = .strong
        default: self = .free
        }
    }
}

// MARK: - The figure

/// The Guardian: the painted artboards where they exist, the nearest shipped painting otherwise.
///
/// It fills whatever frame it is given, so callers size it through
/// `GuardianScale.size(for:fittingIn:)` — that keeps the painted and the drawn figure on exactly
/// the same footprint.
///
/// The cross-fade is not animated here: opacity follows `progress`, so it inherits whatever
/// animation the caller already puts on that value (Home passes `nil` under Reduce Motion).
struct GuardianPortrait: View {
    /// 0…1 toward a fully earned day.
    var progress: Double

    private var p: Double { min(1, max(0, progress)) }

    var body: some View {
        let pair = Self.bracket(p)

        return Group {
            if GuardianArtwork.has(pair.lower), GuardianArtwork.has(pair.upper) {
                ZStack {
                    artwork(pair.lower).opacity(1 - pair.t)
                    artwork(pair.upper).opacity(pair.t)
                }
            } else if let painted = GuardianArtwork.available(in: pair) {
                artwork(painted)
            } else {
                GuardianFigure(progress: p)
            }
        }
        // The figure keeps its own proportions, so a caller can hand it one dimension and still
        // get the composition the artboard was painted at — no letterboxing inside the frame.
        .aspectRatio(aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)      // the copy beside it already says this
    }

    /// The painting's own proportions where it exists, the vector's where it does not.
    ///
    /// A painted artboard is the composition; `GuardianScale` only describes the stand-in, so the
    /// artwork has to win or a wide figure would sit letterboxed in a tall box.
    private var aspectRatio: Double {
        let pair = Self.bracket(p)
        let lower = GuardianArtwork.aspect(pair.lower)
        let upper = GuardianArtwork.aspect(pair.upper)
        switch (lower, upper) {
        case let (l?, u?): return l + (u - l) * pair.t
        case let (l?, nil): return l
        case let (nil, u?): return u
        case (nil, nil):
            if let painted = GuardianArtwork.available(in: pair),
               let aspect = GuardianArtwork.aspect(painted) {
                return aspect
            }
            let size = GuardianScale.size(for: p)
            return size.height > 0 ? size.width / size.height : 1
        }
    }

    private func artwork(_ state: GuardianState) -> some View {
        Image(state.assetName)
            .resizable()
            .scaledToFit()
    }

    /// The two artboards `progress` falls between, and how far it is across them.
    static func bracket(_ progress: Double) -> (lower: GuardianState, upper: GuardianState, t: Double) {
        let states = GuardianState.allCases
        for (lower, upper) in zip(states, states.dropFirst()) where progress <= upper.anchor {
            let span = upper.anchor - lower.anchor
            let t = span > 0 ? (progress - lower.anchor) / span : 1
            return (lower, upper, min(1, max(0, t)))
        }
        return (.strong, .free, 1)
    }
}

/// Which artboards the bundle actually ships.
///
/// Resolved once: this is asked on every frame the Home screen draws, and `UIImage(named:)` goes
/// to the asset catalog.
private enum GuardianArtwork {
    static func has(_ state: GuardianState) -> Bool { painted[state] != nil }

    /// The artboard's width ÷ height, or `nil` where it has not been painted.
    static func aspect(_ state: GuardianState) -> Double? {
        guard let size = painted[state], size.height > 0 else { return nil }
        return size.width / size.height
    }

    /// The closest shipped artboard. This keeps the painted Guardian visible while later poses are
    /// still awaiting artwork, and naturally switches to those poses as their assets are added.
    static func available(
        in pair: (lower: GuardianState, upper: GuardianState, t: Double)
    ) -> GuardianState? {
        let progress = pair.lower.anchor
            + (pair.upper.anchor - pair.lower.anchor) * pair.t
        return painted.keys.min {
            abs($0.anchor - progress) < abs($1.anchor - progress)
        }
    }

    /// Resolved once, keyed to the artboards that actually ship, with the size each was painted at.
    private static let painted: [GuardianState: CGSize] = GuardianState.allCases.reduce(into: [:]) {
        if let image = UIImage(named: $1.assetName) { $0[$1] = image.size }
    }
}

// MARK: - Bounded stages

/// The Guardian's world as a full-bleed header, with the rounded page lip the copy sheet pulls
/// over it.
///
/// This is the shape onboarding's hero needs: the artwork runs under the status bar and the sheet
/// below continues in the same ivory, so the two read as one surface rather than a picture with a
/// page under it.
struct GuardianHeader: View {
    var progress: Double
    var height: CGFloat
    /// Height of the rounded page lip drawn over the bottom of the scene.
    var lip: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                GuardianAtmosphere(progress: progress, bleedsIntoSafeArea: false)
                    .ignoresSafeArea(edges: .top)

                GuardianPortrait(progress: progress)
                    .frame(
                        maxWidth: geometry.size.width - Theme.Space.gutter * 2,
                        maxHeight: geometry.size.height - lip - Theme.Space.m
                    )
                    .padding(.bottom, lip)

                if lip > 0 {
                    UnevenRoundedRectangle(topLeadingRadius: lip, topTrailingRadius: lip)
                        .fill(Theme.background)
                        .frame(height: lip)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
        .frame(height: height)
    }
}

/// A bounded, rounded block of the Guardian's world, for scenes that sit inside a scrolling page.
struct GuardianPanel: View {
    var progress: Double
    var height: CGFloat
    var cornerRadius: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                GuardianAtmosphere(progress: progress, bleedsIntoSafeArea: false)
                GuardianPortrait(progress: progress)
                    .frame(
                        maxWidth: geometry.size.width - Theme.Space.l * 2,
                        maxHeight: geometry.size.height - Theme.Space.m
                    )
                    .padding(.bottom, Theme.Space.s)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: cornerRadius))
    }
}

#Preview("Portrait states") {
    HStack(spacing: 0) {
        ForEach(GuardianState.allCases, id: \.self) { state in
            GuardianPanel(progress: state.anchor, height: 320)
                .frame(width: 150)
        }
    }
}

#Preview("Header") {
    VStack(spacing: 0) {
        GuardianHeader(progress: GuardianState.awakening.anchor, height: 300, lip: Theme.sheetRadius)
        Text("Move first. Scroll later.")
            .font(.serif(27, italic: true, relativeTo: .title))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Theme.Space.gutter)
            .background(Theme.background)
    }
}
