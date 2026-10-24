import EarnDomain
import SwiftUI

/// The stretch of days an impact report covers.
enum ImpactPeriod: String {
    case today
    case week
    case month

    var eyebrow: LocalizedStringKey {
        switch self {
        case .today: "impact.period.today"
        case .week: "impact.period.week"
        case .month: "impact.period.month"
        }
    }
}

/// "Your day" from Home: what moving, and staying out, added up to today.
///
/// Opal leads with its Focus Score and one sec with the opens it prevented; both give people a
/// number to come back for. Progress already tells the earned-versus-used story, so this is the
/// outcome version of it, and the place the progress card is shared from.
struct ImpactReportView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let impact = env.impact(for: [env.progressToday])

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: 6) {
                        NightEyebrow(text: ImpactPeriod.today.eyebrow)
                        Text("impact.title")
                            .font(.serif(38, relativeTo: .largeTitle))
                            .accessibilityAddTraits(.isHeader)
                    }
                    ImpactMetrics(impact: impact)
                    if impact.reclaimedSeconds != nil {
                        Text("impact.reclaimed.footnote")
                            .font(.sans(12.5))
                            .foregroundStyle(Night.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.top, Theme.Space.xl)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 4) {
                ProgressShareActions(impact: impact, period: .today, source: "impact_report")
                Button("common.done") { dismiss() }
                    .buttonStyle(.quiet)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, Theme.Space.s)
        }
        .foregroundStyle(Night.text)
        .background(Night.ground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            env.analytics.track(.impactReportViewed.withProperties([
                "source": .string("home"),
                "skipped_opens": .int(impact.skippedOpens),
                "has_reclaimed_estimate": .bool(impact.reclaimedSeconds != nil)
            ]))
        }
    }
}

/// The four numbers of a report, two by two.
struct ImpactMetrics: View {
    let impact: ImpactSummary

    @Environment(\.locale) private var locale

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Space.m, verticalSpacing: Theme.Space.m) {
            GridRow {
                metric(
                    impact.reclaimedSeconds.map { ImpactFormat.duration($0, locale: locale) } ?? "–",
                    "impact.metric.reclaimed",
                    accent: impact.reclaimedSeconds != nil
                )
                metric(impact.skippedOpens.formatted(.number.locale(locale)), "impact.metric.skipped", accent: impact.skippedOpens > 0)
            }
            GridRow {
                metric(ImpactFormat.duration(impact.earnedSeconds, locale: locale), "impact.metric.earned")
                metric(impact.activityAmount.formatted(.number.locale(locale)), "impact.metric.steps")
            }
        }
    }

    private func metric(_ value: String, _ label: LocalizedStringKey, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.serif(34, relativeTo: .title))
                .foregroundStyle(accent ? Night.moss : Night.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
            Text(label)
                .font(.sans(12.5, weight: .medium))
                .foregroundStyle(Night.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(Night.panel, in: .rect(cornerRadius: Night.panelRadius))
        .accessibilityElement(children: .combine)
    }
}

enum ImpactFormat {
    static func duration(_ seconds: Int, locale: Locale) -> String {
        Duration.seconds(max(0, seconds)).formatted(
            .units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2)
            .locale(locale)
        )
    }
}

// MARK: - Sharing

/// Share the progress card, or dare a friend to try. Earnit had no share surface at all, and with
/// a few dozen installs a month every person who shows a friend is a meaningful share of growth.
struct ProgressShareActions: View {
    let impact: ImpactSummary
    let period: ImpactPeriod
    /// Where the actions sit, for `progress_share_tapped`.
    let source: String

    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale
    @State private var card: Image?

    var body: some View {
        VStack(spacing: 4) {
            if let card, impact.hasContent {
                ShareLink(
                    item: card,
                    message: Text("share.progress.message \(AppConfiguration.appStoreURL.absoluteString)"),
                    preview: SharePreview(Text("share.preview.title"), image: card)
                ) {
                    Label("share.progress", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.nightPill)
                .simultaneousGesture(TapGesture().onEnded { track("progress") })
            }

            ShareLink(
                item: AppConfiguration.appStoreURL,
                message: challengeMessage
            ) {
                Label("share.challenge", systemImage: "figure.walk")
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Night.cobaltText)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { track("challenge") })
        }
        // Re-render only when a number on the card changes, not on every timeline tick.
        .task(id: cardSignature) { card = renderCard() }
    }

    private var challengeMessage: Text {
        impact.earnedMinutes > 0
            ? Text("share.challenge.message.earned \(impact.earnedMinutes)")
            : Text("share.challenge.message")
    }

    private var cardSignature: [Int] {
        [impact.earnedSeconds / 60, impact.skippedOpens, (impact.reclaimedSeconds ?? -60) / 60,
         impact.activityAmount, env.streakDays]
    }

    private func track(_ kind: String) {
        env.analytics.track(.progressShareTapped.withProperties([
            "kind": .string(kind),
            "source": .string(source),
            "period": .string(period.rawValue)
        ]))
    }

    @MainActor
    private func renderCard() -> Image? {
        let renderer = ImageRenderer(
            content: ProgressShareCard(impact: impact, period: period, streak: env.streakDays)
                .environment(\.locale, locale)
        )
        // 360 × 640 points at 3× is a 1080 × 1920 story.
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}

/// The story-sized card that gets shared. The illustration does the selling; the numbers are
/// the person's own, and the lead is the most impressive one they have.
struct ProgressShareCard: View {
    let impact: ImpactSummary
    let period: ImpactPeriod
    let streak: Int

    @Environment(\.locale) private var locale

    var body: some View {
        ZStack(alignment: .topLeading) {
            IllustratedScene.freedomRidge.image
                .resizable()
                .scaledToFill()
                .frame(width: 360, height: 640, alignment: .bottom)
                .clipped()
            LinearGradient(
                colors: [Night.ground.opacity(0.92), Night.ground.opacity(0.55), .clear],
                startPoint: .top,
                endPoint: .center
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "Earnit")
                    .font(.serif(26))
                NightEyebrow(text: period.eyebrow, color: Night.textSoft)
                    .padding(.top, 36)
                Text(headlineValue)
                    .font(.serif(76))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.top, 6)
                Text(headlineLabel)
                    .font(.sans(17, weight: .medium))
                    .foregroundStyle(Night.textSoft)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    if impact.skippedOpens > 0 {
                        row("hand.raised", Text("share.card.skipped \(impact.skippedOpens)"))
                    }
                    if impact.activityAmount > 0 {
                        row("figure.walk", Text("share.card.steps \(impact.activityAmount.formatted(.number.locale(locale)))"))
                    }
                    if leadsWithReclaimed, impact.earnedSeconds > 0 {
                        row("bolt.fill", Text("share.card.earned \(ImpactFormat.duration(impact.earnedSeconds, locale: locale))"))
                    }
                    if streak > 1 {
                        row("flame.fill", Text("share.card.streak \(streak)"))
                    }
                }
                .padding(.top, 28)

                Spacer(minLength: 0)

                Text("share.card.footer")
                    .font(.sans(14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Night.cobalt, in: .capsule)
            }
            .padding(28)
        }
        .frame(width: 360, height: 640)
        .foregroundStyle(Night.text)
        .background(Night.ground)
    }

    /// Lead with reclaimed time once it is worth bragging about; earned minutes otherwise.
    private var leadsWithReclaimed: Bool { (impact.reclaimedSeconds ?? 0) >= 15 * 60 }

    private var headlineValue: String {
        ImpactFormat.duration(leadsWithReclaimed ? impact.reclaimedSeconds ?? 0 : impact.earnedSeconds, locale: locale)
    }

    private var headlineLabel: LocalizedStringKey {
        leadsWithReclaimed ? "share.card.reclaimed" : "share.card.earnedLead"
    }

    private func row(_ symbol: String, _ text: Text) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Night.moss)
                .frame(width: 20)
            text.font(.sans(16, weight: .medium))
        }
    }
}

#Preview {
    ImpactReportView()
        .environment(AppEnvironment(
            screenTime: MockScreenTimeService(status: .approved),
            health: MockHealthKitService(hasRequested: true, steps: 6_240)
        ))
}
