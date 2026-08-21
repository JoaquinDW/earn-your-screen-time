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

    var icon: String {
        switch self {
        case .home: "house"
        case .week: "star"
        case .settings: "gearshape"
        }
    }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// Top-level navigation, grounded in the same paper as the page.
struct FloatingBottomNavigation: View {
    @Binding var selection: AppSection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        VStack(spacing: 0) {
            Hairline()

            HStack(spacing: Theme.Space.s) {
                ForEach(AppSection.allCases, id: \.self) { section in
                    let isSelected = selection == section
                    Button {
                        selection = section
                    } label: {
                        FloatingNavigationItem(
                            section: section,
                            isSelected: isSelected,
                            selectionNamespace: selectionNamespace
                        )
                    }
                    .buttonStyle(FloatingNavigationButtonStyle(reduceMotion: reduceMotion))
                    .accessibilityLabel(Text(section.label))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.vertical, Theme.Space.s)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.paper.opacity(0.98).ignoresSafeArea(edges: .bottom))
        .overlay(GrainTexture(opacity: 0.1).allowsHitTesting(false))
        .animation(reduceMotion ? nil : .snappy(duration: 0.26), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }

}

private struct FloatingNavigationItem: View {
    let section: AppSection
    let isSelected: Bool
    let selectionNamespace: Namespace.ID

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: isSelected ? section.icon + ".fill" : section.icon)
                .font(.system(size: 20, weight: .semibold))

            Text(section.label)
                .font(.sans(9.5, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isSelected ? Theme.sageDeep : Theme.ink)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 52)
        .background(selectionBackground)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Theme.sageLight.opacity(0.9))
                .matchedGeometryEffect(id: "navigation-selection", in: selectionNamespace)
        }
    }
}

private struct FloatingNavigationButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.62 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
