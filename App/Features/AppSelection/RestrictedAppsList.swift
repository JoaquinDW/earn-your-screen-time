import FamilyControls
import ManagedSettings
import SwiftUI

/// The apps whose minutes come out of the wallet.
///
/// Screen Time hands us opaque tokens — we can *display* an app but never read its name (PRD §27).
/// `Label(token)` is the one way to show the real icon and title, so the rows here are rendered
/// by the system, and the empty state is the Guardian at rest.
struct RestrictedAppsList: View {
    @Binding var selection: FamilyActivitySelection
    /// Whether tapping a row removes it. Off in read-only contexts.
    var isEditable = true

    private var isEmpty: Bool {
        selection.applicationTokens.isEmpty
            && selection.categoryTokens.isEmpty
            && selection.webDomainTokens.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if isEmpty {
                // Nothing to list yet, so the screen shows the Guardian at rest rather than a
                // blank column above the picker.
                GuardianPortrait(progress: 0)
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Space.l)
            }
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

/// A plain row of the controlled apps: icon over name, up to `limit` of them.
///
/// Onboarding still shows the apps this way — there is no balance yet, so there is nothing to
/// price them in. Home uses `ReadyToSpendRow` instead.
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
                .foregroundStyle(Theme.cobaltDeep)
                .frame(minHeight: Theme.minTouchTarget, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else {
            HStack(alignment: .top, spacing: 26) {
                ForEach(Array(selection.applicationTokens.prefix(limit)), id: \.self) { token in
                    Label(token).labelStyle(StackedTokenLabelStyle())
                }
                ForEach(
                    Array(selection.categoryTokens.prefix(max(0, limit - selection.applicationTokens.count))),
                    id: \.self
                ) { token in
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

/// Home's spend row (design v5): not a second status readout, but what the balance *buys*.
///
/// The blocked apps used to sit here as a row of circles that said nothing. Now each one is a
/// pill labelled with the balance — what this app would open for, right now. The pills stay
/// stone-grey while there is nothing to spend and pick up cobalt as the balance grows, so the
/// row wakes up with the Guardian instead of competing with it.
struct ReadyToSpendRow: View {
    let selection: FamilyActivitySelection
    let availableMinutes: Int
    /// The shortest session that can actually be started. Below it, the row is honestly grey.
    var minimumSpendMinutes = 1
    var limit = 3
    let onChoose: () -> Void
    let onSpend: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Tier {
        /// Nothing to spend yet.
        case resting
        /// A balance worth opening something with.
        case ready
        /// A full day's worth.
        case full
    }

    private var tier: Tier {
        if availableMinutes >= 30 { .full }
        else if availableMinutes >= minimumSpendMinutes { .ready }
        else { .resting }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("dashboard.readyToSpend", systemImage: "lock.fill")
                    .font(.sans(11))
                    .textCase(.uppercase)
                    .kerning(1.5)
                    .foregroundStyle(Theme.muted)
                    .contentTransition(.symbolEffect(.replace))
                Spacer(minLength: Theme.Space.s)
                Text("home.minutesAvailable \(availableMinutes)")
                    .font(.sans(12, weight: tier == .resting ? .regular : .semibold))
                    .foregroundStyle(tier == .resting ? Theme.muted : Theme.cobaltDeep)
                    .contentTransition(.numericText(value: Double(availableMinutes)))
            }

            if selection.isEmpty {
                chooseAppsPill
            } else {
                HStack(spacing: Theme.Space.s) {
                    ForEach(tokens, id: \.self) { token in
                        pill {
                            HStack(spacing: 9) {
                                // The system renders the real icon; the token's name is opaque to
                                // us and too long for a third of the width anyway, so the label
                                // is what the balance opens it *for*.
                                Label(token)
                                    .labelStyle(.iconOnly)
                                    .frame(width: 20, height: 20)
                                    .clipShape(.circle)
                                Text("common.minutesValue \(availableMinutes)")
                                    .font(.sans(12.5, weight: .semibold))
                                    .foregroundStyle(tier == .resting ? Theme.muted : Theme.cobaltDeep)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                        }
                    }
                }
                .contentShape(.rect)
                .onTapGesture(perform: onSpend)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(Text("home.minutesAvailable \(availableMinutes)"))
                .accessibilityHint(Text("home.spend.a11y"))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: EarnMotion.standard), value: availableMinutes)
    }

    private var tokens: [ApplicationToken] {
        Array(selection.applicationTokens.prefix(limit))
    }

    private var chooseAppsPill: some View {
        Button(action: onChoose) {
            pill {
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                        .font(.sans(12, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("dashboard.noAppsSelected")
                        .font(.sans(12.5, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(Theme.muted)
            }
        }
        .buttonStyle(.plain)
    }

    /// The pill itself. Everything about it — fill, border, text colour — is the balance.
    private func pill(@ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: Theme.minTouchTarget)
            .background(fill, in: .capsule)
            .overlay {
                if tier == .full {
                    Capsule().stroke(Theme.cobalt.opacity(0.22), lineWidth: 1)
                }
            }
    }

    private var fill: Color {
        switch tier {
        case .resting: Theme.stone.opacity(0.7)
        case .ready: Theme.cobaltTint
        case .full: Color.white
        }
    }
}
