import SwiftUI

/// A titled card. Used instead of `Form` on the dashboard so the balance can breathe.
struct CardSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, Theme.Space.xs)

            VStack(spacing: 0) { content }
                .background(Theme.surface, in: .rect(cornerRadius: Theme.cornerRadius))
        }
    }
}

/// One statistic inside a card: an SF Symbol, a label and a value.
struct StatRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    let symbol: String
    let label: LocalizedStringKey
    let value: String
    var tint: Color = .secondary
    var showsDivider = true

    /// At accessibility text sizes a label and a value cannot share a row without
    /// hyphenating both; stack them instead.
    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.xs))
            : AnyLayout(HStackLayout(spacing: Theme.Space.m))
    }

    var body: some View {
        VStack(spacing: 0) {
            layout {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)          // the label already says it

                Text(label)
                    .font(.body)

                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: Theme.Space.s)
                }

                Text(value)
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, typeSize.isAccessibilitySize ? Theme.Space.m : 0)
            .frame(minHeight: Theme.minTouchTarget + 8)

            if showsDivider {
                Divider().padding(.leading, Theme.Space.m + 28 + Theme.Space.m)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
