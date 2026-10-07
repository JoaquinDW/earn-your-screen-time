import SwiftUI

/// The streak earns visual weight gradually instead of turning into a second progress goal.
struct StreakBadge: View {
    let days: Int

    private var level: Level {
        switch days {
        case 14...: .established
        case 7...: .growing
        case 3...: .started
        default: .quiet
        }
    }

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: level == .quiet ? "flame" : "flame.fill")
                .font(.sans(11, weight: .semibold, relativeTo: .caption))
                .accessibilityHidden(true)

            Text("dashboard.streak \(days)")
                .font(.sans(12.5, weight: level == .quiet ? .medium : .semibold, relativeTo: .caption))
                .contentTransition(.numericText(value: Double(days)))
        }
        .foregroundStyle(level == .quiet ? Night.textMuted : Night.cobaltText)
        .padding(.horizontal, level == .quiet ? 0 : Theme.Space.s)
        .frame(minHeight: Theme.minTouchTarget)
        .background(backgroundColor, in: .capsule)
        .overlay {
            if level == .established {
                Capsule().stroke(Night.cobalt.opacity(0.35), lineWidth: 1)
            }
        }
        .shadow(
            color: level == .established ? Night.cobalt.opacity(0.18) : .clear,
            radius: Theme.Space.s,
            y: Theme.Space.xs
        )
        .accessibilityElement(children: .combine)
    }

    private var backgroundColor: Color {
        switch level {
        case .quiet: .clear
        case .started: Night.cobaltWash.opacity(0.45)
        case .growing: Night.cobaltWash.opacity(0.72)
        case .established: Night.cobaltWash
        }
    }

    private enum Level {
        case quiet
        case started
        case growing
        case established
    }
}
