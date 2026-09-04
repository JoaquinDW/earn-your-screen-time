import SwiftUI

/// A painted scene from the v6 identity — *"there is a life outside the screen"*.
///
/// Each case is one piece of artwork plus the two things a layout has to know that the file
/// itself cannot say: which edge the composition hangs from, and where the person stands in it.
/// Adding a scene means adding a case and an imageset under `Assets.xcassets/Scenes`; nothing
/// else in the app has to learn about it.
enum IllustratedScene: String, CaseIterable {
    /// Home: a man on a chair under a huge tree, his phone the only cold light in the frame.
    /// The whole middle of the canvas is empty — and that emptiness is where the balance goes.
    case homeEvening = "Scenes/home-evening"
    /// Earn time: the same man walking a path away from us, at dusk, into open ground.
    case earnPath = "Scenes/earn-path"
    /// Blocked: he has put the phone down on a park bench and is looking at the trees instead.
    /// The whole top half is empty night — this is a boundary, drawn as calm rather than denial.
    case blockedBench = "Scenes/blocked-bench"
    /// Freedom: a ridge above the city at dusk, the phone small in his hand. The aspirational
    /// frame — onboarding's opening and the paywall — with an enormous sky to set type into.
    case freedomRidge = "Scenes/freedom-ridge"
    /// Progress: a close crop of legs walking a path through long grass. Deliberately partial —
    /// it is a footnote under the data, not a portrait.
    case progressPath = "Scenes/progress-path"

    var image: Image { Image(rawValue) }

    /// The edge the crop hangs from when the frame is a different shape than the artwork.
    ///
    /// Four of the five scenes put the person low and the sky high, so they hang from the bottom:
    /// a frame shorter than the artwork then eats the sky, never the figure. The progress crop is
    /// the exception — its subject is at the top — so it hangs from there instead.
    var anchor: Alignment {
        switch self {
        case .progressPath: .top
        default: .bottom
        }
    }

    /// The band of the artwork, top to bottom, that the human figure occupies.
    ///
    /// Kept next to the artwork so a layout can reason about where not to put a panel, instead of
    /// each screen re-deriving it from the image by eye.
    var figureBand: ClosedRange<Double> {
        switch self {
        case .homeEvening: 0.76...0.95
        case .earnPath: 0.63...0.87
        case .blockedBench: 0.64...0.90
        case .freedomRidge: 0.62...0.81
        case .progressPath: 0.00...0.42
        }
    }
}

/// How a backdrop is faded back into the app around it.
enum SceneFill {
    /// The artwork is the screen. Only the edges are washed, so the composition survives whole.
    case fullBleed
    /// The artwork is a band that has to *end* somewhere: it dissolves completely into the
    /// ground at its bottom edge, so no seam is ever visible where the content takes over.
    case band
}

/// The one place illustration meets product UI.
///
/// Everything the identity needs lives here rather than in the screens: `aspectFill` so nothing
/// is ever stretched, a crop anchored to the composition so the figure is never sliced, and a
/// vertical wash that carries the artwork into `Night.ground` instead of ending it on a hard
/// rectangle.
///
/// The view simply fills whatever it is given — a screen-sized ZStack layer, or the background of
/// one section — so no screen does arithmetic on device heights to place it.
///
/// The wash is two things at once: a light veil across the open middle, so display type stays
/// legible against whatever the artwork does there, and near-opaque ground at the edges, so the
/// status bar, a tab bar, or a list has something solid to sit on.
struct SceneBackdrop: View {
    let scene: IllustratedScene
    var fill: SceneFill = .fullBleed
    /// Extra darkening across the whole frame, for a screen that stacks more text on the art.
    var veil: Double = 0

    var body: some View {
        artwork
            .overlay(wash)
            .background(Night.ground)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// `scaledToFill` inside a clipped container: the aspect ratio is never touched, and the crop
    /// hangs from the scene's own anchor so the figure stays whole at every frame shape.
    private var artwork: some View {
        Color.clear
            .overlay(alignment: scene.anchor) {
                scene.image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipped()
    }

    private var wash: LinearGradient {
        LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    private var stops: [Gradient.Stop] {
        switch fill {
        case .fullBleed:
            [
                // Only the status bar's own strip needs solid ground; below it the canopy is
                // the whole reason the screen looks like anywhere.
                .init(color: Night.ground.opacity(0.80), location: 0),
                .init(color: Night.ground.opacity(0.34), location: 0.06),
                // The open middle — veiled just enough to hold type, never enough to close it.
                .init(color: Night.ground.opacity(0.08 + veil), location: 0.22),
                .init(color: Night.ground.opacity(0.10 + veil), location: 0.56),
                // Then the ground returns, so a list has somewhere to sit above the figure.
                .init(color: Night.ground.opacity(0.34), location: 0.74),
                .init(color: Night.ground.opacity(0.62), location: 1),
            ]
        case .band:
            [
                .init(color: Night.ground.opacity(0.78), location: 0),
                .init(color: Night.ground.opacity(0.26), location: 0.14),
                .init(color: Night.ground.opacity(0.08 + veil), location: 0.40),
                .init(color: Night.ground.opacity(0.62), location: 0.78),
                // A band has to resolve into the ground, or the screen shows a seam.
                .init(color: Night.ground, location: 1),
            ]
        }
    }
}

/// A band of artwork at the top of a screen, with content sitting in its darkened foot.
///
/// This is the shape every Tier-1 screen except Home takes: Earn time, the opening of onboarding,
/// the paywall. The height is a share of the container rather than a number, so a 6.9" phone
/// shows more of the scene and a 5.4" phone shows less without either one cropping the figure —
/// `SceneBackdrop` hangs the crop from the artwork's own anchor.
///
/// Put it at the top of a `ScrollView` whose content ignores the top safe area, so the artwork
/// reaches the status bar and scrolls away with everything else.
struct SceneHero<Overlay: View>: View {
    let scene: IllustratedScene
    /// Fraction of the visible container the band occupies.
    var share: CGFloat = 0.5
    /// Extra darkening, for a hero that carries more text than a caption.
    var veil: Double = 0
    /// Where the overlay sits inside the band. Bottom-leading unless the artwork says otherwise.
    var alignment: Alignment = .bottomLeading
    @ViewBuilder var overlay: Overlay

    var body: some View {
        overlay
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: alignment)
            .containerRelativeFrame(.vertical, alignment: .bottom) { height, _ in
                height * share
            }
            .background { SceneBackdrop(scene: scene, fill: .band, veil: veil) }
    }
}

extension View {
    /// Bounds a UI column so it stops where the figure in a scene begins.
    ///
    /// Home and Blocked both put their whole composition above a person standing in the lower
    /// part of a full-bleed scene. Expressing that from the scene's own `figureBand` — rather
    /// than a per-device offset — is what keeps him uncovered on every iPhone.
    func clearOfFigure(in scene: IllustratedScene) -> some View {
        containerRelativeFrame(.vertical, alignment: .top) { height, _ in
            height * scene.figureBand.lowerBound
        }
    }
}

/// A local fade from transparent to the ground, for content that has to overlap the artwork.
///
/// Used instead of giving a list an opaque box: the artwork keeps coming through the top of the
/// fade, so there is still no rectangle anywhere on the screen.
struct GroundFade: View {
    var edge: VerticalEdge = .bottom
    var height: CGFloat = 90
    var opacity: Double = 1

    var body: some View {
        LinearGradient(
            colors: [Night.ground.opacity(0), Night.ground.opacity(opacity)],
            startPoint: edge == .bottom ? .top : .bottom,
            endPoint: edge == .bottom ? .bottom : .top
        )
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The translucent surface v6 floats over an illustration — blurred artwork, one hairline edge.
struct NightPanel<Content: View>: View {
    var radius: CGFloat = Night.panelRadius
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(.ultraThinMaterial, in: .rect(cornerRadius: radius))
            .background(Night.panel.opacity(0.78), in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Night.edge, lineWidth: 1)
            }
            .environment(\.colorScheme, .dark)
    }
}

#Preview("Home — full bleed") {
    ZStack {
        SceneBackdrop(scene: .homeEvening).ignoresSafeArea()
        VStack {
            Text(verbatim: "42")
                .font(.serif(104))
                .foregroundStyle(Night.text)
            Spacer()
        }
        .padding(.top, 120)
    }
}

#Preview("Earn — band") {
    VStack(spacing: 0) {
        Text(verbatim: "4,328")
            .font(.serif(58))
            .foregroundStyle(Night.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, Theme.Space.l)
            .frame(height: 420, alignment: .bottom)
            .background { SceneBackdrop(scene: .earnPath, fill: .band) }
        Spacer()
    }
    .background(Night.ground)
    .ignoresSafeArea(edges: .top)
}
