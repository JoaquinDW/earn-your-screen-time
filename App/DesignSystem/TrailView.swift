import SwiftUI

/// The one illustration in the app, and the only soft shape on any screen.
///
/// It means exactly one thing: **distance to your next reward**. The coral trail is drawn in as
/// far as you have walked, the walker sits at that point, and the flag is the reward. There is
/// no XP, no coins and no second meaning layered on top — that is the whole point of it.
///
/// Geometry is authored in the illustration's own 320×190 space and then scaled to the width of
/// the container, bottom-aligned. Width is never cropped — the walker's start, the flag and the
/// trees are the whole composition — so a slot taller than the artwork simply gets more sky,
/// and a shorter one is a band of landscape with the sky cropped away.
struct TrailView: View {
    /// 0...1 toward the next reward.
    var progress: Double
    var cornerRadius: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBobbing = false

    private static let size = CGSize(width: 320, height: 190)

    private var clamped: Double { min(1, max(0, progress)) }

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / Self.size.width

            scene
                .frame(width: Self.size.width, height: Self.size.height)
                .scaleEffect(scale, anchor: .bottom)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
        .background(Palette.sky)
        .overlay(GrainTexture(opacity: 0.4))
        .clipShape(.rect(cornerRadius: cornerRadius))
        .accessibilityHidden(true)          // the numbers beside it already say this
    }

    // MARK: - Scene

    private var scene: some View {
        ZStack {
            sun
            birds
            hills
            trees
            trail
            flag
            walker
        }
    }

    private var sun: some View {
        ZStack {
            // A gradient rather than a flat wash: 28% coral over this sky mixes to grey, which
            // reads as a ring at the sizes the phone actually draws it at.
            Circle()
                .fill(RadialGradient(
                    colors: [Palette.sun.opacity(0.45), Palette.sun.opacity(0)],
                    center: .center,
                    startRadius: 24,
                    endRadius: 38
                ))
                .frame(width: 76, height: 76)
                .scaleEffect(38 / 27)
            Circle().fill(Palette.sun).frame(width: 76, height: 76)
        }
        .position(x: 254, y: 46)
    }

    private var birds: some View {
        ZStack {
            Bird().stroke(Palette.bird, style: .init(lineWidth: 2.4, lineCap: .round))
                .frame(width: 14, height: 6)
                .position(x: 59, y: 41)
            Bird().stroke(Palette.bird, style: .init(lineWidth: 2.2, lineCap: .round))
                .frame(width: 12, height: 5)
                .position(x: 84, y: 29.5)
        }
    }

    private var hills: some View {
        ZStack {
            hill(color: Palette.hillFar, center: CGPoint(x: 66, y: 152), radii: CGSize(width: 150, height: 74))
            hill(color: Palette.hillMid, center: CGPoint(x: 266, y: 160), radii: CGSize(width: 136, height: 64))
            hill(color: Palette.hillNear, center: CGPoint(x: 150, y: 212), radii: CGSize(width: 230, height: 86))
        }
    }

    private func hill(color: Color, center: CGPoint, radii: CGSize) -> some View {
        Ellipse()
            .fill(color)
            .frame(width: radii.width * 2, height: radii.height * 2)
            .position(center)
    }

    private var trees: some View {
        ZStack {
            tree(x: 43, groundY: 140, height: 16, leafRadius: 11)
            tree(x: 288, groundY: 146, height: 14, leafRadius: 9)
            tree(x: 205.5, groundY: 125, height: 13, leafRadius: 8)
        }
        .opacity(0.9)
    }

    private func tree(x: CGFloat, groundY: CGFloat, height: CGFloat, leafRadius: CGFloat) -> some View {
        let stemWidth: CGFloat = leafRadius > 9 ? 4 : 3.5
        return ZStack {
            Capsule()
                .fill(Palette.treeStem)
                .frame(width: stemWidth, height: height)
                .position(x: x, y: groundY - height / 2)
            Circle()
                .fill(Palette.treeLeaf)
                .frame(width: leafRadius * 2, height: leafRadius * 2)
                .position(x: x, y: groundY - height + leafRadius / 2)
        }
    }

    private var trail: some View {
        ZStack {
            TrailPath().stroke(
                Palette.trailAhead,
                style: .init(lineWidth: 5, lineCap: .round, dash: [9, 10])
            )
            TrailPath()
                .trim(from: 0, to: max(0.0001, clamped))
                .stroke(Palette.trailWalked, style: .init(lineWidth: 5, lineCap: .round))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.9), value: clamped)
        }
    }

    private var flag: some View {
        ZStack {
            Capsule()
                .fill(Palette.flagPole)
                .frame(width: 2.6, height: 34)
                .position(x: 267.3, y: 135)
            Pennant()
                .fill(Palette.flagCloth)
                .frame(width: 16, height: 12)
                .position(x: 277, y: 126)
        }
    }

    private var walker: some View {
        let point = TrailPath.point(at: clamped)
        return ZStack {
            Circle().fill(Palette.walkerRing).frame(width: 19, height: 19)
            Circle().fill(Palette.walkerBody).frame(width: 11.2, height: 11.2)
        }
        .position(point)
        .offset(y: isBobbing ? -2.5 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.9), value: clamped)
        .onAppear {
            startBobbingIfNeeded()
        }
        .onChange(of: reduceMotion) { _, shouldReduceMotion in
            if shouldReduceMotion {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { isBobbing = false }
            } else {
                startBobbingIfNeeded()
            }
        }
    }

    private func startBobbingIfNeeded() {
        guard !reduceMotion, !isBobbing else { return }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            isBobbing = true
        }
    }

    // MARK: - Palette
    //
    // Local to the illustration: these are pigments in a picture, not app-wide roles.

    private enum Palette {
        static let sky = Theme.sky
        static let sun = Color(hex: 0xF2BDA3)
        static let bird = Theme.ink.opacity(0.22)
        static let hillFar = Color(hex: 0xD8E6CF)
        static let hillMid = Color(hex: 0xB3CBA9)
        static let hillNear = Theme.sage
        static let treeStem = Color(hex: 0x6F8A68)
        static let treeLeaf = Color(hex: 0x7BA070)
        static let trailAhead = Theme.paper
        static let trailWalked = Theme.coral
        static let flagPole = Theme.sageDeep
        static let flagCloth = Theme.coral
        static let walkerRing = Theme.paper
        static let walkerBody = Theme.coralDeep
    }
}

// MARK: - Shapes

/// The path the walker follows: one quadratic curve from the near hill to the flag.
private struct TrailPath: Shape {
    static let start = CGPoint(x: 36, y: 178)
    static let control = CGPoint(x: 140, y: 114)
    static let end = CGPoint(x: 268, y: 150)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: Self.start)
        path.addQuadCurve(to: Self.end, control: Self.control)
        return path
    }

    /// Point on the curve at parameter `t`, used to seat the walker.
    static func point(at t: Double) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
        )
    }
}

private struct Bird: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

/// The swallow-tailed flag at the end of the trail.
private struct Pennant: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width / 4, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 0) {
        TrailView(progress: 0.08)
        TrailView(progress: 0.55)
        TrailView(progress: 1)
    }
}

/// The illustration as a full-bleed header.
///
/// It runs under the status bar, and the labels floating over it stay inside the safe area.
struct TrailHeader<Overlay: View>: View {
    var progress: Double
    var height: CGFloat
    /// Where floating labels sit, measured from the top of the illustration.
    var overlayInset: CGFloat = 8
    /// Height of the rounded page lip drawn over the bottom of the illustration. The content
    /// below continues in the same colour, so the two read as one sheet sliding over the scene.
    var lip: CGFloat = 0
    @ViewBuilder var overlay: Overlay

    var body: some View {
        ZStack(alignment: .top) {
            TrailView(progress: progress)
                .ignoresSafeArea(edges: .top)

            overlay.padding(.top, overlayInset)

            if lip > 0 {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    UnevenRoundedRectangle(topLeadingRadius: lip, topTrailingRadius: lip)
                        .fill(Theme.background)
                        .frame(height: lip)
                }
            }
        }
        .frame(height: height)
    }
}
