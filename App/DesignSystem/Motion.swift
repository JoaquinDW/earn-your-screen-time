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
    func staggeredAppear(_ index: Int, in scene: String) -> some View {
        modifier(StaggeredAppear(index: index, scene: scene))
    }
}

/// The scenes whose entrance has already played since launch.
@MainActor
private enum StaggeredScenes {
    static var played: Set<String> = []
}

private struct StaggeredAppear: ViewModifier {
    let index: Int
    let scene: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible: Bool

    init(index: Int, scene: String) {
        self.index = index
        self.scene = scene
        // Read at creation, before any piece's `onAppear` marks the scene as played, so every
        // piece of the first pass animates and anything inserted later simply appears.
        _isVisible = State(initialValue: StaggeredScenes.played.contains(scene))
    }

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 14)
            .blur(radius: isVisible || reduceMotion ? 0 : 6)
            .onAppear {
                guard !isVisible else { return }
                StaggeredScenes.played.insert(scene)
                let animation = reduceMotion
                    ? Animation.easeOut(duration: EarnMotion.quick)
                    : EarnMotion.settle.delay(Double(index) * EarnMotion.stagger)
                withAnimation(animation) { isVisible = true }
            }
    }
}
