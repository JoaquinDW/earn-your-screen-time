import EarnDomain
import SwiftUI

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("onboarding.step.v2") private var storedStep = 0

    @State private var profile = OnboardingProfile()
    @State private var isMovingBack = false
    @State private var recentAverage: Int?
    @State private var viewedSteps: Set<Step> = []

    private var step: Step { Step(rawValue: storedStep) ?? .hook }

    var body: some View {
        ZStack {
            PaperBackground()
            content
                .id(step)
                .transition(reduceMotion ? .opacity : .push(from: isMovingBack ? .leading : .trailing))
        }
        .foregroundStyle(Theme.ink)
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: step)
        .onAppear {
            profile = env.profile
            env.analytics.track(.onboardingStarted)
            trackView(step)
        }
        .onChange(of: profile) { _, updated in env.saveProfile(updated) }
        .onChange(of: storedStep) { _, _ in trackView(step) }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .hook:
            OnboardingHookStep(onContinue: advance)
        case .scrolling:
            QuestionStep(question: .scrolling, profile: $profile, step: step, onContinue: questionContinue, onBack: goBack)
        case .movement:
            QuestionStep(question: .movement, profile: $profile, step: step, onContinue: questionContinue, onBack: goBack)
        case .outcomes:
            QuestionStep(question: .outcomes, profile: $profile, step: step, onContinue: questionContinue, onBack: goBack)
        case .science:
            ScienceStep(onContinue: advance, onBack: goBack)
        case .mechanism:
            MechanismStep(rule: env.ledger.rule, onContinue: mechanismContinue, onBack: goBack)
        case .plan:
            PlanStep(profile: profile, rule: env.ledger.rule, onContinue: advance, onBack: goBack)
        case .projection:
            ProjectionStep(profile: profile, rule: env.ledger.rule, onContinue: projectionContinue, onBack: goBack)
        case .apps:
            AppsStep(onContinue: advance, onBack: goBack)
        case .commitment:
            CommitmentStep(profile: profile, rule: env.ledger.rule, onContinue: commitmentContinue, onBack: goBack)
        case .health:
            HealthPermissionStep(onContinue: healthContinue, onBack: goBack)
        case .result:
            FinalPlanStep(profile: profile, recentAverage: recentAverage, onContinue: advance, onBack: goBack)
        case .paywall:
            OnboardingPaywallStep(profile: profile, onActivated: advance)
        case .activation:
            ActivationStep(profile: profile, rule: env.ledger.rule, onFinish: finish)
        }
    }

    private func questionContinue() {
        switch step {
        case .scrolling:
            if let scrolling = profile.scrolling {
                env.analytics.track(.scrollTimeSelected.withProperties(["band": .string(scrolling.rawValue)]))
            }
        case .movement:
            if let movement = profile.movement {
                env.analytics.track(.currentStepsSelected.withProperties(["band": .string(movement.rawValue)]))
            }
        case .outcomes:
            env.analytics.track(.desiredOutcomesSelected.withProperties([
                "count": .int(profile.desiredOutcomes.count),
                "values": .string(profile.desiredOutcomes.map(\.rawValue).sorted().joined(separator: ","))
            ]))
        default: break
        }
        advance()
    }

    private func mechanismContinue() {
        env.analytics.track(.mechanismUnderstood)
        env.analytics.track(.planGenerated.withProperties(["daily_goal": .int(profile.dailyStepGoal)]))
        advance()
    }

    private func projectionContinue() {
        env.analytics.track(.thirtyDayProjectionCTA)
        advance()
    }

    private func commitmentContinue() {
        env.analytics.track(.commitmentConfirmed.withProperties(["daily_goal": .int(profile.dailyStepGoal)]))
        advance()
    }

    private func healthContinue(average: Int?) {
        recentAverage = average
        advance()
    }

    private func advance() {
        guard let next = step.next else { return }
        isMovingBack = false
        storedStep = next.rawValue
    }

    private func goBack() {
        guard let previous = step.previous else { return }
        isMovingBack = true
        storedStep = previous.rawValue
    }

    private func finish() {
        storedStep = 0
        env.completeOnboarding()
    }

    private func trackView(_ step: Step) {
        guard viewedSteps.insert(step).inserted else { return }
        switch step {
        case .science: env.analytics.track(.scienceScreenViewed)
        case .projection: env.analytics.track(.thirtyDayProjectionViewed)
        case .result: env.analytics.track(.personalizedResultViewed)
        default: break
        }
    }

    enum Step: Int, CaseIterable, Hashable {
        case hook, scrolling, movement, outcomes, science, mechanism, plan, projection
        case apps, commitment, health, result, paywall, activation

        var next: Step? { Step(rawValue: rawValue + 1) }
        var previous: Step? { rawValue == 0 ? nil : Step(rawValue: rawValue - 1) }
    }
}

private struct QuestionStep: View {
    let question: OnboardingQuestion
    @Binding var profile: OnboardingProfile
    let step: OnboardingView.Step
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(onBack: onBack) {
            StepDots(total: OnboardingView.Step.allCases.count - 1, completed: step.rawValue)
                .padding(.bottom, Theme.Space.l)
            Text("A LITTLE ABOUT YOU").eyebrowStyle(Theme.coralDeep)
            Text(question.title)
                .font(.serif(38))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Text(question.subtitle)
                .font(.sans(14.5))
                .foregroundStyle(Theme.muted)
                .padding(.top, 10)
                .padding(.bottom, Theme.Space.m)

            VStack(spacing: 0) {
                ForEach(question.options(for: $profile)) { answer in
                    Hairline()
                    ChoiceRow(label: answer.label, isSelected: answer.isSelected, action: answer.select)
                }
                Hairline()
            }
        } action: {
            Button("Continue", action: onContinue)
                .buttonStyle(.pill)
                .disabled(!question.isAnswered(in: profile))
        }
    }
}

private struct OnboardingPaywallStep: View {
    let profile: OnboardingProfile
    let onActivated: () -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ProPaywallView(profile: profile, allowsDismiss: false, onActivated: onActivated)
            .task {
                await env.subscriptionManager.refresh()
                if env.subscriptionManager.isPro { onActivated() }
            }
    }
}

#Preview {
    OnboardingView()
        .environment(AppEnvironment(
            screenTime: MockScreenTimeService(status: .approved),
            health: MockHealthKitService(recentAverageSteps: 4_350)
        ))
}
