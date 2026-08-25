import EarnDomain
import FamilyControls
import SwiftUI

struct OnboardingHookStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GuardianHeader(
                progress: GuardianState.awakening.anchor,
                height: 300,
                lip: Theme.sheetRadius
            )
            VStack(alignment: .leading, spacing: 0) {
                Text("app.name")
                    .eyebrowStyle(Theme.coralDeep)
                Text("Earn your screen time.")
                    .font(.serif(48))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                Text("Turn the apps you already love into motivation to move.")
                    .font(.sans(17))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 14)

                HStack(spacing: Theme.Space.s) {
                    loopItem(icon: "figure.walk", text: "Move", color: Theme.cobaltDeep)
                    Image(systemName: "arrow.right").accessibilityHidden(true)
                    loopItem(icon: "timer", text: "Earn", color: Theme.cobaltDeep)
                    Image(systemName: "arrow.right").accessibilityHidden(true)
                    loopItem(icon: "apps.iphone", text: "Enjoy", color: Theme.ink)
                }
                .padding(.vertical, Theme.Space.l)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Move, earn, then enjoy")

                Spacer(minLength: Theme.Space.m)
                Button("See what you could achieve", action: onContinue).buttonStyle(.pill)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, Theme.Space.m)
            .padding(.bottom, Theme.Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Theme.background)
        }
    }

    private func loopItem(icon: String, text: LocalizedStringKey, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 21, weight: .semibold)).foregroundStyle(color)
            Text(text).font(.sans(12.5, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
    }
}

struct ScienceStep: View {
    let onContinue: () -> Void
    let onBack: () -> Void
    @State private var showsSource = false

    var body: some View {
        OnboardingScaffold(onBack: onBack) {
            Text("WHY THIS WORKS").eyebrowStyle(Theme.coralDeep)
            Text("Your phone keeps you sitting.")
                .font(.serif(39))
                .padding(.top, 12)
            Text("Let’s make it do the opposite.")
                .font(.serif(24, italic: true, relativeTo: .title2))
                .foregroundStyle(Theme.coralDeep)
                .padding(.top, 6)

            VStack(spacing: 0) {
                evidence(
                    icon: "shoeprints.fill",
                    title: "Every step counts",
                    body: "Any amount of physical activity is better than none."
                )
                Hairline()
                evidence(icon: "brain.head.profile", title: "Move for your mind", body: "Regular physical activity supports mental health and well-being.")
                Hairline()
                evidence(icon: "figure.walk.motion", title: "Sit less. Move more.", body: "Health guidelines recommend reducing sedentary behavior.")
            }
            .padding(.top, Theme.Space.l)

            Button("Based on WHO physical activity guidelines") { showsSource = true }
                .buttonStyle(.quietLink)
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Space.m)
        } action: {
            Button("Show me how", action: onContinue).buttonStyle(.pill)
        }
        .sheet(isPresented: $showsSource) { ScienceSourceView() }
    }

    private func evidence(
        icon: String,
        title: LocalizedStringKey,
        body: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.coralDeep)
                .frame(width: 44, height: 44)
                .background(Theme.coralLight, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.serif(22))
                Text(body).font(.sans(14)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .combine)
    }
}

private struct ScienceSourceView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("The evidence supports moving more and sitting less. It does not guarantee a specific health outcome for any individual.")
                        .font(.sans(16))
                    Link("Read the WHO physical activity guidance", destination: URL(string: "https://www.who.int/news-room/fact-sheets/detail/physical-activity")!)
                        .buttonStyle(.quietLink)
                }
                .padding(Theme.Space.gutter)
            }
            .navigationTitle("About the science")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

struct MechanismStep: View {
    let rule: EarningRule
    let onContinue: () -> Void
    let onBack: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        OnboardingScaffold(onBack: onBack) {
            Text("THE RULE IS SIMPLE").eyebrowStyle(Theme.coralDeep)
            Text("Move first. Scroll later.")
                .font(.serif(42))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            VStack(spacing: Theme.Space.m) {
                mechanismValue(
                    icon: "figure.walk",
                    value: Text(rule.amountRequired.formatted(.number.locale(locale))),
                    label: Text("steps"),
                    color: Theme.coralDeep
                )
                Image(systemName: "arrow.down").foregroundStyle(Theme.muted).accessibilityHidden(true)
                mechanismValue(
                    icon: "plus",
                    value: Text("\(rule.rewardMinutes)"),
                    label: Text("minutes"),
                    color: Theme.sageDeep
                )
                Image(systemName: "arrow.down").foregroundStyle(Theme.muted).accessibilityHidden(true)
                mechanismValue(
                    icon: "apps.iphone",
                    value: Text("Screen time"),
                    label: Text("on apps you choose"),
                    color: Theme.ink
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.xl)

            Text("Instead of blocking your favorite apps forever, Earnit makes screen time something you unlock by moving.")
                .font(.sans(15))
                .foregroundStyle(Theme.muted)
        } action: {
            Button("Build my plan", action: onContinue).buttonStyle(.pill)
        }
    }

    private func mechanismValue(icon: String, value: Text, label: Text, color: Color) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon).font(.system(size: 21, weight: .bold)).foregroundStyle(color).frame(width: 36)
            VStack(alignment: .leading, spacing: 1) {
                value.font(.serif(29)).foregroundStyle(color)
                label.font(.sans(13)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: 240, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct CommitmentStep: View {
    let profile: OnboardingProfile
    let rule: EarningRule
    let onContinue: () -> Void
    let onBack: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale

    private var dailyMinutes: Int { (profile.dailyStepGoal / rule.amountRequired) * rule.rewardMinutes }

    var body: some View {
        OnboardingScaffold(onBack: onBack) {
            Text("YOUR COMMITMENT").eyebrowStyle(Theme.coralDeep)
            Text("Make a deal with yourself.")
                .font(.serif(42))
                .padding(.top, 12)
            HStack(alignment: .center, spacing: Theme.Space.m) {
                commitmentValue(
                    Text(profile.dailyStepGoal.formatted(.number.locale(locale))),
                    Text("steps/day"),
                    Theme.coralDeep
                )
                Text("=").font(.serif(30)).foregroundStyle(Theme.muted)
                commitmentValue(Text("\(dailyMinutes)"), Text("minutes earned"), Theme.sageDeep)
            }
            .padding(.vertical, Theme.Space.xl)
            .accessibilityElement(children: .combine)

            RestrictedAppsStrip(selection: env.screenTime.selection, limit: 4, onChoose: {})
            Text("Move first. Scroll later.")
                .font(.serif(27, italic: true, relativeTo: .title))
                .padding(.top, Theme.Space.xl)
        } action: {
            Button("I’m in", action: onContinue).buttonStyle(.pill)
        }
    }

    private func commitmentValue(_ value: Text, _ label: Text, _ color: Color) -> some View {
        VStack(spacing: 4) {
            value.font(.serif(33)).foregroundStyle(color)
            label.font(.sans(12.5, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

struct FinalPlanStep: View {
    let profile: OnboardingProfile
    let recentAverage: Int?
    let onContinue: () -> Void
    let onBack: () -> Void
    @Environment(\.locale) private var locale

    private var projection: Projection { Projection(profile: profile) }

    var body: some View {
        OnboardingScaffold(onBack: onBack) {
            Text("YOUR PLAN IS READY").eyebrowStyle(Theme.sageDeep)
            Text("Make your screen time work for you.")
                .font(.serif(42))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            if let recentAverage {
                Text("Apple Health shows a recent average of \(recentAverage.formatted(.number.locale(locale))) steps/day.")
                    .font(.sans(15))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 12)
            } else {
                Text("Your estimate gives us everything needed to begin. Your plan will update from your real steps.")
                    .font(.sans(15))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 12)
            }

            VStack(spacing: 0) {
                finalRow(
                    Text("Daily goal"),
                    Text(profile.dailyStepGoal.formatted(.number.locale(locale))),
                    Theme.coralDeep
                )
                Hairline()
                finalRow(
                    Text("30-day goal"),
                    Text(projection.totalSteps.formatted(.number.locale(locale))),
                    Theme.ink
                )
                Hairline()
                finalRow(
                    Text("Intentional screen time"),
                    Text("up to \(projection.earnedHours)h"),
                    Theme.sageDeep
                )
            }
            .padding(.top, Theme.Space.l)

            Text("You’re not trying to use a different phone. You’re building a different relationship with it.")
                .font(.serif(20, italic: true, relativeTo: .title3))
                .foregroundStyle(Theme.muted)
                .padding(.top, Theme.Space.l)
        } action: {
            Button("Start my 30-day change", action: onContinue).buttonStyle(.pill)
        }
    }

    private func finalRow(_ label: Text, _ value: Text, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            label.font(.sans(14, weight: .semibold)).foregroundStyle(Theme.muted)
            Spacer()
            value.font(.serif(27)).foregroundStyle(color)
        }
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .combine)
    }
}

struct ActivationStep: View {
    let profile: OnboardingProfile
    let rule: EarningRule
    let onFinish: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            GuardianPortrait(progress: GuardianState.awakening.anchor)
                .frame(height: 200)
            Text("You’re in.").font(.serif(50)).padding(.top, Theme.Space.l)
            Text("Your first walk starts now.")
                .font(.serif(23, italic: true, relativeTo: .title2))
                .foregroundStyle(Theme.muted)
                .padding(.top, 8)

            VStack(spacing: Theme.Space.s) {
                Text("0 / \(profile.dailyStepGoal.formatted(.number.locale(locale))) steps")
                    .font(.sans(16, weight: .bold))
                ProgressView(value: 0).tint(Theme.cobaltDeep)
                Text("Your first \(rule.amountRequired.formatted(.number.locale(locale))) steps unlock \(rule.rewardMinutes) minutes.")
                    .font(.sans(14))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Theme.Space.xl)
            Spacer()
            Button("Let’s earn it", action: onFinish).buttonStyle(.pill)
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.bottom, Theme.Space.l)
        }
        .padding(.horizontal, Theme.Space.gutter)
    }
}
