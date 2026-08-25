import EarnDomain
import SwiftUI

struct PlanStep: View {
    let profile: OnboardingProfile
    let rule: EarningRule
    let onContinue: () -> Void
    let onBack: () -> Void
    @Environment(\.locale) private var locale

    private var dailyMinutes: Int {
        (profile.dailyStepGoal / rule.amountRequired) * rule.rewardMinutes
    }

    var body: some View {
        OnboardingScaffold(onBack: onBack) {
            Text("YOUR PLAN").eyebrowStyle(Theme.coralDeep)
            Text("A goal built around where you are today.")
                .font(.serif(40))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            VStack(spacing: 0) {
                planRow(
                    icon: "figure.walk",
                    value: Text(profile.dailyStepGoal.formatted(.number.locale(locale))),
                    label: Text("steps each day")
                )
                Hairline()
                planRow(
                    icon: "timer",
                    value: Text("Up to \(dailyMinutes) min"),
                    label: Text("earned each day"),
                    color: Theme.sageDeep
                )
                Hairline()
                planRow(
                    icon: "arrow.triangle.2.circlepath",
                    value: Text("\(rule.rewardMinutes) min"),
                    label: Text("for every \(rule.amountRequired.formatted(.number.locale(locale))) steps")
                )
            }
            .padding(.top, Theme.Space.l)

            Text("Move first. Scroll later.")
                .font(.serif(25, italic: true, relativeTo: .title2))
                .padding(.top, Theme.Space.l)
        } action: {
            Button("Show me my results", action: onContinue).buttonStyle(.pill)
        }
    }

    private func planRow(icon: String, value: Text, label: Text, color: Color = Theme.ink) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.1), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                value.font(.serif(27)).foregroundStyle(color)
                label.font(.sans(13.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.vertical, 15)
        .accessibilityElement(children: .combine)
    }
}

struct ProjectionStep: View {
    let profile: OnboardingProfile
    let rule: EarningRule
    let onContinue: () -> Void
    let onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @State private var appeared = false

    private var projection: Projection { Projection(profile: profile, rule: rule) }

    var body: some View {
        OnboardingScaffold(onBack: onBack) {
            GuardianPortrait(progress: GuardianState.free.anchor)
                .frame(height: 190)
                .frame(maxWidth: .infinity)
                .padding(.bottom, Theme.Space.m)

            Text("YOUR NEXT 30 DAYS").eyebrowStyle(Theme.coralDeep)
            Text("Imagine yourself 30 days from now.")
                .font(.serif(42))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Text("If you stick with your plan, this is what you are working toward.")
                .font(.sans(15))
                .foregroundStyle(Theme.muted)
                .padding(.top, 12)

            VStack(spacing: 0) {
                result(
                    value: Text(projection.totalSteps.formatted(.number.locale(locale))),
                    caption: Text("steps toward a more active month"),
                    color: Theme.coralDeep,
                    delay: 0
                )
                Hairline()
                result(
                    value: hoursText,
                    caption: Text("of screen time turned into something you earn"),
                    color: Theme.sageDeep,
                    delay: 0.08
                )
                Hairline()
                result(
                    value: Text("30 days"),
                    caption: Text("of choosing movement before scrolling"),
                    color: Theme.ink,
                    delay: 0.16
                )
            }
            .padding(.top, Theme.Space.m)

            Text("Same phone. Different relationship with it.")
                .font(.serif(23, italic: true, relativeTo: .title2))
                .padding(.top, Theme.Space.l)
        } action: {
            Button("I want this", action: onContinue).buttonStyle(.pill)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) { appeared = true }
        }
    }

    private var hoursText: Text {
        if projection.earnedMinutes.isMultiple(of: 60) {
            Text("\(projection.earnedMinutes / 60) hours")
        } else {
            Text("\(projection.earnedMinutes) minutes")
        }
    }

    private func result(value: Text, caption: Text, color: Color, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            value.font(.serif(38)).foregroundStyle(color)
            caption.font(.sans(14)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 15)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 10)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(delay), value: appeared)
        .accessibilityElement(children: .combine)
    }
}

struct OnboardingScaffold<Content: View, Action: View>: View {
    let onBack: (() -> Void)?
    @ViewBuilder let content: Content
    @ViewBuilder let action: Action

    init(
        onBack: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action
    ) {
        self.onBack = onBack
        self.content = content()
        self.action = action()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.horizontal, Theme.Space.gutter)
                    .padding(.top, Theme.Space.l)
                    .padding(.bottom, Theme.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 2) {
                action
                if let onBack {
                    Button("Back", action: onBack)
                        .buttonStyle(.quiet)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.s)
            .background(Theme.background)
        }
    }
}
