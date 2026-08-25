import SwiftUI

/// The Guardian **is** the progress bar (design v5).
///
/// There is no ring and no percentage anywhere on Home. Progress is read off the figure itself:
/// how low it sits, how much of the frame it takes, how far the wings reach, and how much cobalt
/// has escaped into the air around it. Every number in this file is the design's own — the four
/// artboards (6%, 47%, 92%, 100%) are the control points, and `ramp(_:_:)` reads the value
/// *between* them so the screen wakes gradually through the day instead of snapping between four
/// poses.
///
/// Composition, bottom to top:
/// 1. **Base** — ivory lifting from `#F6F3ED` to `#F9F6F1`.
/// 2. **Light** — a radial behind the figure, growing to 80% of the screen height.
/// 3. **Ink wash** — grey-blue, blurred, bleeding off-frame.
/// 4. **Cobalt wash** — absent early, drifting on a slow loop once minutes are earned.
/// 5. **Orbits** — one to three oversized hairlines that always overflow the viewport.
/// 6. **Traces** — cobalt strokes leaving the wingtips (drawn with the figure).
/// 7. **Grain** — constant, barely legible.

// MARK: - Interpolation

/// Reads a value the design specifies at discrete progress states, piecewise-linearly.
///
/// `stops` must be sorted by progress. Outside the range the end values simply hold.
func ramp(_ progress: Double, _ stops: [(p: Double, v: Double)]) -> Double {
    guard let first = stops.first, let last = stops.last else { return 0 }
    if progress <= first.p { return first.v }
    if progress >= last.p { return last.v }
    for (lower, upper) in zip(stops, stops.dropFirst()) where progress <= upper.p {
        let span = upper.p - lower.p
        guard span > 0 else { return upper.v }
        let t = (progress - lower.p) / span
        return lower.v + (upper.v - lower.v) * t
    }
    return last.v
}

/// A 0…1 fade that opens over a band of progress. Used to bring layers in one at a time.
private func fade(_ progress: Double, from start: Double, to end: Double) -> Double {
    guard end > start else { return progress >= end ? 1 : 0 }
    return min(1, max(0, (progress - start) / (end - start)))
}

// MARK: - Figure geometry

/// The size the illustration takes at a given progress, from artboards 8a–8d.
///
/// It is not linear: the figure holds back for most of the day and then takes the screen, which
/// is the point — at 100% it is wider than the phone and crops at both edges.
enum GuardianScale {
    private static let widths: [(p: Double, v: Double)] = [
        (0.00, 168), (0.06, 176), (0.47, 258), (0.92, 340), (1.00, 436),
    ]
    private static let heights: [(p: Double, v: Double)] = [
        (0.00, 202), (0.06, 212), (0.47, 312), (0.92, 404), (1.00, 470),
    ]

    static func size(for progress: Double) -> CGSize {
        CGSize(width: ramp(progress, widths), height: ramp(progress, heights))
    }
}

/// Where the Guardian's parts sit, in the figure's own unit square (0…1, y down).
///
/// The open pose is the design's own mark scaled out of its 23×16 box into this taller one: two
/// crescents that leave the apex, sweep **up and out** past the corners, and curl back to a
/// shoulder below the apex — with the orb floating free underneath. Nothing joins them, exactly
/// as the nav glyph draws it.
///
/// `openness` is the progress value. Folded, the wings are small and tucked in beside the apex;
/// open, their tips run past the edges of the box, which is what makes them crop against the
/// phone at 100%.
private enum GuardianGeometry {
    static let apex = CGPoint(x: 0.500, y: 0.480)

    static func orb(_ openness: Double) -> (center: CGPoint, radius: Double) {
        (CGPoint(x: 0.5, y: 0.825), lerp(0.055, 0.080, openness))
    }

    /// Outer wingtip, for the leading wing. Mirrored for the trailing one.
    static func tip(_ openness: Double) -> CGPoint {
        CGPoint(
            x: lerp(0.290, 0.030, openness),
            y: lerp(0.400, 0.110, openness)
        )
    }

    static func wingPath(in rect: CGRect, openness o: Double, mirrored: Bool) -> Path {
        func at(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(
                x: rect.minX + (mirrored ? 1 - x : x) * rect.width,
                y: rect.minY + y * rect.height
            )
        }

        let tip = self.tip(o)
        var path = Path()
        path.move(to: at(apex.x, apex.y))
        // Leading edge: out of the apex and up to the tip.
        path.addCurve(
            to: at(tip.x, tip.y),
            control1: at(lerp(0.445, 0.400, o), lerp(0.430, 0.290, o)),
            control2: at(lerp(0.355, 0.190, o), lerp(0.380, 0.075, o))
        )
        // Trailing edge: back down and in to the shoulder, below the apex.
        path.addCurve(
            to: at(lerp(0.470, 0.430, o), lerp(0.620, 0.660, o)),
            control1: at(lerp(0.315, 0.120, o), lerp(0.510, 0.400, o)),
            control2: at(lerp(0.395, 0.270, o), lerp(0.585, 0.560, o))
        )
        path.closeSubpath()
        return path
    }
}

private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * min(1, max(0, t))
}

// MARK: - Shapes

private struct GuardianWing: Shape {
    var openness: Double
    var mirrored: Bool

    var animatableData: Double {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        GuardianGeometry.wingPath(in: rect, openness: openness, mirrored: mirrored)
    }
}

/// One cobalt stroke leaving a wingtip, drawn in the figure's unit space.
///
/// The control points deliberately fall outside 0…1: a trace is supposed to leave the figure and
/// drift off toward the edge of the screen, so it is never clipped to the illustration's box.
private struct GuardianTrace: Shape {
    var start: CGPoint
    var control1: CGPoint
    var control2: CGPoint
    var end: CGPoint

    func path(in rect: CGRect) -> Path {
        func at(_ point: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
        }
        var path = Path()
        path.move(to: at(start))
        path.addCurve(to: at(end), control1: at(control1), control2: at(control2))
        return path
    }
}

// MARK: - The figure

/// The Guardian: two wings, a body and an orb, plus the traces that escape it.
///
/// The vector stand-in for the painted artboards: `GuardianPortrait` draws this whenever a
/// watercolour state has not been painted yet, so the *same* figure still interpolates
/// continuously instead of leaving a hole in the screen.
struct GuardianFigure: View {
    /// 0…1 toward a fully earned day.
    var progress: Double

    private var p: Double { min(1, max(0, progress)) }

    /// Grey-blue while nothing is earned, cobalt once it is. This is the only hue in the figure.
    private var pigment: Color { Theme.wash.mix(with: Theme.cobalt, by: p) }

    var body: some View {
        ZStack {
            wing(mirrored: false)
            wing(mirrored: true)
            orb
        }
        .overlay(traces)
        .accessibilityHidden(true)      // the copy beside it already says this
    }

    /// A wash of pigment held by a hairline — the mark is an outline, so the fill stays light
    /// enough that the edge is what you actually read.
    private func wing(mirrored: Bool) -> some View {
        let shape = GuardianWing(openness: p, mirrored: mirrored)
        return shape
            .fill(
                LinearGradient(
                    colors: [
                        pigment.opacity(lerp(0.05, 0.14, p)),
                        pigment.opacity(lerp(0.01, 0.04, p)),
                    ],
                    startPoint: .bottom,
                    endPoint: mirrored ? .topTrailing : .topLeading
                )
            )
            .overlay(
                shape.stroke(
                    pigment.mix(with: Theme.ink, by: 0.30).opacity(lerp(0.22, 0.45, p)),
                    style: StrokeStyle(lineWidth: 1.1, lineJoin: .round)
                )
            )
    }

    private var orb: some View {
        GeometryReader { geometry in
            let orb = GuardianGeometry.orb(p)
            let diameter = orb.radius * 2 * geometry.size.width
            let center = CGPoint(
                x: orb.center.x * geometry.size.width,
                y: orb.center.y * geometry.size.height
            )
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [pigment.opacity(lerp(0.10, 0.34, p)), pigment.opacity(0)],
                            center: .center,
                            startRadius: diameter * 0.35,
                            endRadius: diameter * 1.5
                        )
                    )
                    .frame(width: diameter * 3, height: diameter * 3)
                    .position(center)
                Circle()
                    .fill(pigment.opacity(lerp(0.55, 1.0, p)))
                    .frame(width: diameter, height: diameter)
                    .position(center)
            }
        }
    }

    /// Zero to four strokes, appearing one at a time as the day is earned (layer 6).
    private var traces: some View {
        let tip = GuardianGeometry.tip(p)
        let specs: [(trace: GuardianTrace, from: Double, to: Double, alpha: Double)] = [
            (
                GuardianTrace(
                    start: CGPoint(x: 1 - tip.x, y: tip.y),
                    control1: CGPoint(x: 1.12, y: tip.y - 0.16),
                    control2: CGPoint(x: 1.24, y: -0.06),
                    end: CGPoint(x: 1.30, y: -0.26)
                ), 0.18, 0.32, 0.42
            ),
            (
                GuardianTrace(
                    start: CGPoint(x: tip.x, y: tip.y),
                    control1: CGPoint(x: -0.12, y: tip.y - 0.18),
                    control2: CGPoint(x: -0.26, y: -0.08),
                    end: CGPoint(x: -0.31, y: -0.28)
                ), 0.50, 0.64, 0.32
            ),
            // Two more rise from between the wings, clearing the top of the composition.
            (
                GuardianTrace(
                    start: CGPoint(x: 0.545, y: 0.070),
                    control1: CGPoint(x: 0.585, y: -0.040),
                    control2: CGPoint(x: 0.598, y: -0.200),
                    end: CGPoint(x: 0.590, y: -0.340)
                ), 0.76, 0.88, 0.24
            ),
            (
                GuardianTrace(
                    start: CGPoint(x: 0.432, y: 0.085),
                    control1: CGPoint(x: 0.398, y: -0.030),
                    control2: CGPoint(x: 0.372, y: -0.170),
                    end: CGPoint(x: 0.364, y: -0.310)
                ), 0.93, 0.99, 0.16
            ),
        ]

        return ZStack {
            ForEach(Array(specs.enumerated()), id: \.offset) { _, spec in
                let presence = fade(p, from: spec.from, to: spec.to)
                if presence > 0 {
                    spec.trace
                        .stroke(
                            Theme.cobalt.opacity(spec.alpha * presence),
                            style: StrokeStyle(lineWidth: 1.3, lineCap: .round)
                        )
                    TraceEndpoint(point: spec.trace.end)
                        .fill(Theme.cobalt.opacity(spec.alpha * 1.5 * presence))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The small dot the design leaves at the far end of each trace.
private struct TraceEndpoint: Shape {
    var point: CGPoint
    var radius: CGFloat = 3.5

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.minY + point.y * rect.height
        )
        return Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }
}

// MARK: - The stage

/// The elastic area the Guardian stands in: it takes whatever height the copy below leaves it,
/// and the figure is always anchored to the bottom of it.
struct GuardianStage: View {
    var progress: Double

    private var p: Double { min(1, max(0, progress)) }

    var body: some View {
        let size = GuardianScale.size(for: p)

        return ZStack(alignment: .bottom) {
            floorGlow
            // Height drives the growth and the figure's own proportions give it its width. The
            // vector is unaffected — it already has this ratio — but a painted artboard is a
            // composition, not a silhouette, and matching its width would shrink a seated pose
            // to a stamp.
            GuardianPortrait(progress: p)
                .frame(height: size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// The weight the figure casts on the floor of its stage — grey early, cobalt once earning.
    private var floorGlow: some View {
        let width = ramp(p, [(0.06, 230), (0.47, 300), (0.92, 370), (1.00, 402)])
        let height = ramp(p, [(0.06, 150), (0.47, 190), (0.92, 230), (1.00, 250)])
        let alpha = ramp(p, [(0.06, 0.13), (0.47, 0.09), (0.92, 0.13), (1.00, 0.16)])
        let blur = ramp(p, [(0.06, 14), (0.47, 18), (0.92, 20), (1.00, 22)])
        let colour = Theme.wash.mix(with: Theme.cobalt, by: fade(p, from: 0.06, to: 0.47))

        return Ellipse()
            .fill(
                RadialGradient(
                    colors: [colour.opacity(alpha), colour.opacity(0)],
                    center: UnitPoint(x: 0.5, y: 0.86),
                    startRadius: 0,
                    endRadius: width * 0.62
                )
            )
            .frame(width: width, height: height)
            .blur(radius: blur)
            .allowsHitTesting(false)
    }
}

// MARK: - The atmosphere

/// Layers 1–5 and 7: everything that is not the figure.
///
/// Full-bleed behind the whole screen. Every layer is decorative and never intercepts touches.
struct GuardianAtmosphere: View {
    var progress: Double
    /// Full-bleed behind a whole screen by default. Bounded containers — `GuardianHeader`,
    /// `GuardianPanel` — turn this off so the layers stay inside the frame they were given.
    var bleedsIntoSafeArea: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrifting = false

    private var p: Double { min(1, max(0, progress)) }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                base
                light(in: size)
                inkWash(in: size)
                cobaltWash(in: size)
                secondaryCobaltWash(in: size)
                orbits(in: size)
                GrainTexture(opacity: ramp(p, [(0.06, 0.12), (1.00, 0.16)]))
            }
            .frame(width: size.width, height: size.height)
        }
        .modifier(FullBleed(isEnabled: bleedsIntoSafeArea))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { startDriftIfNeeded() }
        .onChange(of: reduceMotion) { _, shouldReduce in
            if shouldReduce {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { isDrifting = false }
            } else {
                startDriftIfNeeded()
            }
        }
    }

    private func startDriftIfNeeded() {
        guard !reduceMotion, !isDrifting else { return }
        let period = ramp(p, [(0.47, 16), (0.92, 14), (1.00, 12)])
        withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
            isDrifting = true
        }
    }

    // Layer 1 — the ground. Never white, never grey.
    private var base: some View {
        Theme.background.mix(with: Theme.backgroundLit, by: p)
    }

    // Layer 2 — the light behind the figure.
    private func light(in size: CGSize) -> some View {
        ellipseWash(
            in: size,
            colour: Color.white.mix(with: Theme.backgroundLit, by: lerp(0.25, 0, p)),
            alpha: ramp(p, [(0.06, 0.85), (0.47, 0.95), (0.92, 0.98), (1.00, 1.00)]),
            centre: CGPoint(x: 0.500, y: 0.176),
            radii: CGSize(
                width: ramp(p, [(0.06, 0.696), (1.00, 0.742)]),
                height: ramp(p, [(0.06, 0.291), (1.00, 0.416)])
            ),
            blur: 0
        )
    }

    // Layer 3 — grey-blue, bleeding off-frame.
    private func inkWash(in size: CGSize) -> some View {
        ellipseWash(
            in: size,
            colour: Theme.wash,
            alpha: ramp(p, [(0.06, 0.09), (0.47, 0.13), (0.92, 0.17), (1.00, 0.20)]),
            centre: CGPoint(
                x: ramp(p, [(0.06, 0.24), (0.47, 0.83), (0.92, 0.82), (1.00, 0.82)]),
                y: ramp(p, [(0.06, 0.36), (0.47, 0.44), (0.92, 0.39), (1.00, 0.35)])
            ),
            radii: CGSize(
                width: ramp(p, [(0.06, 0.48), (0.47, 0.43), (0.92, 0.48), (1.00, 0.52)]),
                height: ramp(p, [(0.06, 0.22), (0.47, 0.20), (0.92, 0.23), (1.00, 0.25)])
            ),
            blur: ramp(p, [(0.06, 18), (1.00, 24)])
        )
    }

    // Layer 4 — cobalt. Absent until minutes have been earned, then drifting.
    private func cobaltWash(in size: CGSize) -> some View {
        let presence = fade(p, from: 0.10, to: 0.47)
        return ellipseWash(
            in: size,
            colour: Theme.cobalt,
            alpha: ramp(p, [(0.47, 0.07), (0.92, 0.11), (1.00, 0.15)]) * presence,
            centre: CGPoint(
                x: ramp(p, [(0.47, 0.449), (0.92, 0.472), (1.00, 0.500)]),
                y: ramp(p, [(0.47, 0.310), (0.92, 0.289), (1.00, 0.242)])
            ),
            radii: CGSize(
                width: ramp(p, [(0.47, 0.614), (1.00, 0.651)]),
                height: ramp(p, [(0.47, 0.230), (1.00, 0.294)])
            ),
            blur: ramp(p, [(0.47, 26), (1.00, 34)])
        )
        .offset(y: isDrifting ? -14 : 0)
    }

    // Layer 4b — the second cobalt pool that opens on the left late in the day.
    private func secondaryCobaltWash(in size: CGSize) -> some View {
        let presence = fade(p, from: 0.60, to: 0.92)
        return ellipseWash(
            in: size,
            colour: Theme.cobalt,
            alpha: ramp(p, [(0.92, 0.07), (1.00, 0.10)]) * presence,
            centre: CGPoint(
                x: ramp(p, [(0.92, 0.15), (1.00, 0.16)]),
                y: ramp(p, [(0.92, 0.51), (1.00, 0.47)])
            ),
            radii: CGSize(
                width: ramp(p, [(0.92, 0.43), (1.00, 0.50)]),
                height: ramp(p, [(0.92, 0.17), (1.00, 0.21)])
            ),
            blur: ramp(p, [(0.92, 24), (1.00, 26)])
        )
    }

    // Layer 5 — one to three hairlines, always larger than the screen.
    private func orbits(in size: CGSize) -> some View {
        ZStack {
            orbit(
                in: size,
                centre: CGPoint(
                    x: ramp(p, [(0.06, 0.498), (0.47, 0.597), (1.00, 0.597)]),
                    y: ramp(p, [(0.06, 0.380), (0.47, 0.431), (0.92, 0.471), (1.00, 0.501)])
                ),
                radius: ramp(p, [(0.06, 0.806), (0.47, 0.968), (0.92, 1.132), (1.00, 1.301)]),
                colour: Theme.ink,
                alpha: ramp(p, [(0.06, 0.035), (0.47, 0.060), (0.92, 0.081), (1.00, 0.100)]),
                width: 1,
                presence: 1
            )
            orbit(
                in: size,
                centre: CGPoint(
                    x: 0.597,
                    y: ramp(p, [(0.47, 0.454), (0.92, 0.496), (1.00, 0.529)])
                ),
                radius: ramp(p, [(0.47, 0.786), (0.92, 0.920), (1.00, 1.060)]),
                colour: Theme.cobalt,
                alpha: ramp(p, [(0.47, 0.075), (0.92, 0.126), (1.00, 0.200)]),
                width: ramp(p, [(0.92, 1.0), (1.00, 1.2)]),
                presence: fade(p, from: 0.10, to: 0.47)
            )
            orbit(
                in: size,
                centre: CGPoint(
                    x: 0.597,
                    y: ramp(p, [(0.92, 0.522), (1.00, 0.557)])
                ),
                radius: ramp(p, [(0.92, 0.682), (1.00, 0.803)]),
                colour: Theme.ink.mix(with: Theme.cobalt, by: fade(p, from: 0.92, to: 1.0)),
                alpha: ramp(p, [(0.92, 0.045), (1.00, 0.090)]),
                width: 1,
                presence: fade(p, from: 0.52, to: 0.92)
            )
        }
    }

    private func orbit(
        in size: CGSize,
        centre: CGPoint,
        radius: Double,
        colour: Color,
        alpha: Double,
        width: Double,
        presence: Double
    ) -> some View {
        let diameter = radius * 2 * size.width
        return Circle()
            .stroke(colour.opacity(alpha * presence), lineWidth: width)
            .frame(width: diameter, height: diameter)
            .position(x: centre.x * size.width, y: centre.y * size.height)
            .opacity(presence > 0 ? 1 : 0)
    }

    /// A soft elliptical pool, placed by fractions of the screen exactly as the design does.
    private func ellipseWash(
        in size: CGSize,
        colour: Color,
        alpha: Double,
        centre: CGPoint,
        radii: CGSize,
        blur: Double
    ) -> some View {
        let width = radii.width * 2 * size.width
        let height = radii.height * 2 * size.height
        return Ellipse()
            .fill(
                RadialGradient(
                    colors: [colour.opacity(alpha), colour.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(width, height) * 0.5
                )
            )
            .frame(width: width, height: height)
            .blur(radius: blur)
            .position(x: centre.x * size.width, y: centre.y * size.height)
    }
}

/// `ignoresSafeArea()` applied only when the atmosphere is the ground of a whole screen.
private struct FullBleed: ViewModifier {
    var isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.ignoresSafeArea()
        } else {
            content
        }
    }
}

// MARK: - The mark

/// The Guardian reduced to a glyph — two wings and an orb — for the navigation bar.
///
/// Authored in the design's own 23×16 box so the nav icon and the illustration are provably the
/// same creature.
struct GuardianMark: View {
    var color: Color = Theme.cobalt
    var lineWidth: CGFloat = 1.4

    var body: some View {
        GeometryReader { geometry in
            let s = CGSize(width: geometry.size.width / 23, height: geometry.size.height / 16)
            let at = { (x: CGFloat, y: CGFloat) in CGPoint(x: x * s.width, y: y * s.height) }

            ZStack {
                Path { path in
                    path.move(to: at(11.5, 5.4))
                    path.addCurve(to: at(1.6, 1.2), control1: at(9.4, 2.4), control2: at(6, 0.9))
                    path.addCurve(to: at(9.4, 10.1), control1: at(2.6, 5.6), control2: at(5.4, 8.8))
                    path.move(to: at(11.5, 5.4))
                    path.addCurve(to: at(21.4, 1.2), control1: at(13.6, 2.4), control2: at(17, 0.9))
                    path.addCurve(to: at(13.6, 10.1), control1: at(20.4, 5.6), control2: at(17.6, 8.8))
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                Path { path in
                    path.addEllipse(in: CGRect(
                        x: at(11.5, 12.4).x - 2.2 * s.width,
                        y: at(11.5, 12.4).y - 2.2 * s.height,
                        width: 4.4 * s.width,
                        height: 4.4 * s.height
                    ))
                }
                .stroke(color, lineWidth: lineWidth)
            }
        }
    }
}

#Preview("States") {
    HStack(spacing: 0) {
        ForEach([0.06, 0.47, 0.92, 1.0], id: \.self) { progress in
            ZStack {
                GuardianAtmosphere(progress: progress)
                GuardianStage(progress: progress).padding(.bottom, 40)
            }
            .frame(width: 200, height: 440)
            .clipped()
        }
    }
}
