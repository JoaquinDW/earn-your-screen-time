import SwiftUI

// MARK: - Press

extension View {
    /// The shared press for every tappable surface: it dips quickly under the finger and springs
    /// back a hair past its size on release, with an optional haptic as the finger lands.
    ///
    /// Pass `haptic: nil` where the action already publishes its own (tabs, duration chips), so a
    /// tap never buzzes twice.
    func pressFeedback(
        _ isPressed: Bool,
        scale: CGFloat = 0.96,
        haptic: EarnHaptic? = .tap
    ) -> some View {
        modifier(PressFeedback(isPressed: isPressed, scale: scale, haptic: haptic))
    }
}

private struct PressFeedback: ViewModifier {
    let isPressed: Bool
    let scale: CGFloat
    let haptic: EarnHaptic?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? scale : 1)
            .animation(
                reduceMotion ? Animation.easeOut(duration: 0.12) : (isPressed ? EarnMotion.press : EarnMotion.release),
                value: isPressed
            )
            .onChange(of: isPressed) { _, pressed in
                guard pressed, let haptic else { return }
                HapticManager.trigger(haptic)
            }
    }
}

// MARK: - Staggered entrance

extension View {
    /// Builds a screen in front of the reader: each piece rises a few points out of a soft blur,
    /// `index × EarnMotion.stagger` after the first.
    ///
    /// The entrance plays once per `scene` per launch. Tabs rebuild their screens on every switch,
    /// and a Home that re-assembles itself each time you come back reads as slow, not premium.
    func staggeredAppear(
        _ index: Int,
        in scene: String,
        style: StaggeredAppearStyle = .rise
    ) -> some View {
        modifier(StaggeredAppear(index: index, scene: scene, style: style))
    }
}

/// How a piece arrives in a staggered entrance.
enum StaggeredAppearStyle {
    /// Rises a few points out of a soft blur. The default for text and blocks.
    case rise
    /// Starts slightly too large and settles into place, as if the camera were landing on it.
    /// For artwork.
    case settle
    /// Slaps down like a sticker: small, tilted, then a springy pop flat. For a single chip.
    case sticker
}

/// The scenes whose entrance has already played since launch.
@MainActor
private enum StaggeredScenes {
    static var played: Set<String> = []
}

private struct StaggeredAppear: ViewModifier {
    let index: Int
    let scene: String
    let style: StaggeredAppearStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible: Bool

    init(index: Int, scene: String, style: StaggeredAppearStyle) {
        self.index = index
        self.scene = scene
        self.style = style
        // Read at creation, before any piece's `onAppear` marks the scene as played, so every
        // piece of the first pass animates and anything inserted later simply appears.
        _isVisible = State(initialValue: StaggeredScenes.played.contains(scene))
    }

    /// Motion is only drawn while hidden; once visible, or with Reduce Motion, a piece is exactly
    /// where its layout put it.
    private var isMoving: Bool { !isVisible && !reduceMotion }

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isMoving && style == .rise ? 14 : 0)
            .blur(radius: isMoving && style != .sticker ? 6 : 0)
            .scaleEffect(isMoving ? hiddenScale : 1)
            .rotationEffect(.degrees(isMoving && style == .sticker ? -8 : 0))
            .onAppear {
                guard !isVisible else { return }
                StaggeredScenes.played.insert(scene)
                withAnimation(animation) { isVisible = true }
            }
    }

    private var hiddenScale: CGFloat {
        switch style {
        case .rise: 1
        case .settle: 1.06
        case .sticker: 0.6
        }
    }

    private var animation: Animation {
        guard !reduceMotion else { return .easeOut(duration: EarnMotion.quick) }
        let spring = style == .sticker ? EarnMotion.pop : EarnMotion.settle
        return spring.delay(Double(index) * EarnMotion.stagger)
    }
}
