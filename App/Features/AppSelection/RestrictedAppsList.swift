import FamilyControls
import ManagedSettings
import SwiftUI

/// The apps whose minutes come out of the wallet.
///
/// Screen Time hands us opaque tokens — we can *display* an app but never read its name (PRD §27).
/// `Label(token)` is the one way to show the real icon and title, so the rows here are rendered
/// by the system and the monogram is only a stand-in for the empty state.
struct RestrictedAppsList: View {
    @Binding var selection: FamilyActivitySelection
    /// Whether tapping a row removes it. Off in read-only contexts.
    var isEditable = true

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(selection.applicationTokens), id: \.self) { token in
                Hairline()
                row(Label(token)) { selection.applicationTokens.remove(token) }
            }
            ForEach(Array(selection.categoryTokens), id: \.self) { token in
                Hairline()
                row(Label(token)) { selection.categoryTokens.remove(token) }
            }
            ForEach(Array(selection.webDomainTokens), id: \.self) { token in
                Hairline()
                row(Label(token)) { selection.webDomainTokens.remove(token) }
            }
            Hairline()
        }
    }

    private func row(_ label: some View, remove: @escaping () -> Void) -> some View {
        HStack(spacing: Theme.Space.m) {
            label
                .labelStyle(TokenLabelStyle())
            Spacer(minLength: 0)
            if isEditable {
                SelectionDot(isSelected: true)
            }
        }
        .padding(.vertical, Theme.Space.s)
        .frame(minHeight: 70)
        .contentShape(.rect)
        .onTapGesture { if isEditable { remove() } }
        .accessibilityAddTraits(isEditable ? [.isButton, .isSelected] : [])
        .accessibilityHint(isEditable ? Text("appSelection.remove.a11y") : Text(""))
    }
}

/// Puts a system-rendered app label into the design's language: round icon, name in Figtree.
private struct TokenLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Space.m) {
            configuration.icon
                .frame(width: 44, height: 44)
                .clipShape(.circle)
            configuration.title
                .font(.sans(18, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
        }
    }
}

/// The row that opens Apple's picker — the only way to choose apps.
struct ChooseAppsRow: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m) {
                ZStack {
                    Circle().fill(Theme.sageLight)
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.sageDeep)
                }
                .frame(width: 44, height: 44)

                Text(count == 0 ? "appSelection.choose" : "appSelection.change")
                    .font(.sans(18, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Theme.Space.s)
            .frame(minHeight: 70)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// The home screen's row of controlled apps: up to three, icon over name.
struct RestrictedAppsStrip: View {
    let selection: FamilyActivitySelection
    var limit = 3
    let onChoose: () -> Void

    var body: some View {
        if selection.isEmpty {
            Button(action: onChoose) {
                HStack(spacing: Theme.Space.s) {
                    Text("dashboard.noAppsSelected")
                        .font(.sans(15, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.sans(12, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Theme.coralDeep)
                .frame(minHeight: Theme.minTouchTarget, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else {
            HStack(alignment: .top, spacing: 26) {
                ForEach(Array(selection.applicationTokens.prefix(limit)), id: \.self) { token in
                    Label(token).labelStyle(StackedTokenLabelStyle())
                }
                ForEach(Array(selection.categoryTokens.prefix(max(0, limit - selection.applicationTokens.count))), id: \.self) { token in
                    Label(token).labelStyle(StackedTokenLabelStyle())
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct StackedTokenLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: Theme.Space.xs) {
            configuration.icon
                .frame(width: 40, height: 40)
                .clipShape(.circle)
            configuration.title
                .font(.sans(12, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: 64)
    }
}
