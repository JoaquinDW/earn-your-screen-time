import SwiftUI

enum AppSection: String, CaseIterable, Hashable {
    case home
    case week
    case settings

    var label: LocalizedStringKey {
        switch self {
        case .home: "nav.home"
        case .week: "nav.week"
        case .settings: "nav.settings"
        }
    }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// A row of three that becomes the nocturnal ground it stands on, with a 26pt cobalt tick over
/// whichever item is active. A short fade protects it from scrolling content without drawing a
/// hard-edged plate over the screen.
struct FloatingBottomNavigation: View {
    @Binding var selection: AppSection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(AppSection.allCases, id: \.self) { section in
                    let isSelected = selection == section
                    Button {
                        selection = section
                        HapticManager.trigger(.light)
                    } label: {
                        NavigationItem(
                            section: section,
                            isSelected: isSelected
                        )
                    }
                    .buttonStyle(NavigationButtonStyle(reduceMotion: reduceMotion))
                    .accessibilityLabel(Text(section.label))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.top, 14)
            .padding(.bottom, Theme.Space.s)
        }
        .frame(maxWidth: .infinity)
        .background {
            Night.ground.ignoresSafeArea(edges: .bottom)
        }
        .background(alignment: .top) {
            GroundFade(edge: .bottom, height: 32)
                .offset(y: -32)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.26), value: selection)
    }
}

private struct NavigationItem: View {
    let section: AppSection
    let isSelected: Bool

    private var tint: Color {
        isSelected ? Night.text : Night.textFaint
    }

    var body: some View {
        VStack(spacing: 6) {
            icon
                .frame(width: 23, height: 16)
            Text(section.label)
                .font(.sans(10.5, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .frame(minHeight: Theme.minTouchTarget)
        .overlay(alignment: .top) {
            // The whole selected state: one 26pt hairline tick, 15pt above the glyph.
            if isSelected {
                Rectangle()
                    .fill(Night.cobalt)
                    .frame(width: 26, height: 1.5)
                    .offset(y: -15)
            }
        }
        .contentShape(.rect)
    }

    @ViewBuilder
    private var icon: some View {
        switch section {
        case .home:
            HomeGlyph().stroke(tint, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        case .week:
            TrendGlyph().stroke(tint, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        case .settings:
            SlidersGlyph(tint: tint, knobFill: Night.ground)
        }
    }
}

// MARK: - Glyphs
//
// All authored in the design's own 23×16 box, so the three read as one set.

/// Today. The design's own roofline — a place you come back to, not a creature.
private struct HomeGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 23
        let sy = rect.height / 16
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        var path = Path()
        path.move(to: at(2, 6.8))
        path.addLine(to: at(11.5, 1))
        path.addLine(to: at(21, 6.8))
        path.addLine(to: at(21, 15))
        path.addLine(to: at(14.6, 15))
        path.addLine(to: at(14.6, 9.4))
        path.addLine(to: at(8.4, 9.4))
        path.addLine(to: at(8.4, 15))
        path.addLine(to: at(2, 15))
        path.closeSubpath()
        return path
    }
}

private struct TrendGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 23
        let sy = rect.height / 16
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        var path = Path()
        path.move(to: at(2, 13.5))
        path.addCurve(to: at(12, 6.5), control1: at(6, 13.5), control2: at(9, 10.5))
        path.addCurve(to: at(21, 2), control1: at(14.5, 3.2), control2: at(17.5, 1.8))
        path.move(to: at(2, 2))
        path.addLine(to: at(2, 13.8))
        path.addLine(to: at(21, 13.8))
        return path
    }
}

private struct SlidersGlyph: View {
    let tint: Color
    var knobFill: Color = Theme.background

    var body: some View {
        GeometryReader { geometry in
            let sx = geometry.size.width / 23
            let sy = geometry.size.height / 16
            let at = { (x: CGFloat, y: CGFloat) in CGPoint(x: x * sx, y: y * sy) }

            ZStack {
                Path { path in
                    path.move(to: at(2, 4))
                    path.addLine(to: at(21, 4))
                    path.move(to: at(2, 12))
                    path.addLine(to: at(21, 12))
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

                // Knobs punched out of the rails, as the design draws them.
                ForEach([CGPoint(x: 8, y: 4), CGPoint(x: 15.5, y: 12)], id: \.x) { knob in
                    Circle()
                        .fill(knobFill)
                        .overlay(Circle().stroke(tint, lineWidth: 1.4))
                        .frame(width: 4.2 * sx, height: 4.2 * sy)
                        .position(at(knob.x, knob.y))
                }
            }
        }
    }
}

private struct NavigationButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.62 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
