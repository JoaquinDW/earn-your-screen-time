import EarnDomain
import SwiftUI

struct PlanStep: View {
    let profile: OnboardingProfile
    let rule: EarningRule
    let onContinue: () -> Void
    let onBack: () -> Void

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
                planRow(icon: "figure.walk", value: profile.dailyStepGoal.formatted(), label: "steps each day")
                Hairline()
                planRow(icon: "timer", value: "Up to \(dailyMinutes) min", label: "earned each day", color: Theme.sageDeep)
                Hairline()
                planRow(icon: "arrow.triangle.2.circlepath", value: "\(rule.rewardMinutes) min", label: "for every \(rule.amountRequired.formatted()) steps")
            }
            .padding(.top, Theme.Space.l)

            Text("Move first. Scroll later.")
                .font(.serif(25, italic: true, relativeTo: .title2))
                .padding(.top, Theme.Space.l)
        } action: {
            Button("Show me my results", action: onContinue).buttonStyle(.pill)
        }
    }

    private func planRow(icon: String, value: String, label: String, color: Color = Theme.ink) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.1), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(value).font(.serif(27)).foregroundStyle(color)
                Text(label).font(.sans(13.5)).foregroundStyle(Theme.muted)
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
    @State private var appeared = false

    private var projection: Projection { Projection(profile: profile, rule: rule) }

    var body: some View {
        OnboardingScaffold(onBack: onBack) {
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
                result(value: projection.totalSteps.formatted(), caption: "steps toward a more active month", color: Theme.coralDeep, delay: 0)
                Hairline()
                result(value: hoursText, caption: "of screen time turned into something you earn", color: Theme.sageDeep, delay: 0.08)
                Hairline()
                result(value: "30 days", caption: "of choosing movement before scrolling", color: Theme.ink, delay: 0.16)
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

    private var hoursText: String {
        projection.earnedMinutes.isMultiple(of: 60)
            ? "\(projection.earnedMinutes / 60) hours"
            : "\(projection.earnedMinutes) minutes"
    }

    private func result(value: String, caption: String, color: Color, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.serif(38)).foregroundStyle(color)
            Text(caption).font(.sans(14)).foregroundStyle(Theme.muted)
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
