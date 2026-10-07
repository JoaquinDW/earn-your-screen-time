import EarnDomain
import SwiftUI
import UIKit

// MARK: - Intro

/// The product's demonstration moment: what push-ups buy, and two equally reachable ways out.
struct OnboardingPushupsIntroStep: View {
    @Environment(AppEnvironment.self) private var env
    let model: OnboardingPushupsDemoModel
    let onTryNow: () -> Void
    let onLater: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            onBack: onBack,
            progress: Double(OnboardingView.Route.pushupsIntro.progress) / Double(OnboardingView.Route.progressCount)
        ) {
            Text("Earn your next minute of screen time")
                .font(.serif(40, relativeTo: .largeTitle))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                OnboardingPoint(text: "5 push-ups earn the same 5 minutes as 500 steps.")
                OnboardingPoint(text: "No walk, no waiting — indoors, in a minute.")
                OnboardingPoint(text: "The camera counts the reps for you.")
            }
            .padding(.top, Theme.Space.xl)

            Text("Video is never saved or uploaded.")
                .font(.sans(13.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.xl)

            if !model.offersDemo {
                // Never promise a demo a device cannot run.
                Text("This iPhone can't run the push-up camera, so there's nothing to try here. Everything else works normally.")
                    .font(.sans(13.5))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Space.m)
            }
        } action: {
            if model.offersDemo {
                Button("Try it now", action: onTryNow).buttonStyle(.pill)
                // Deliberately a full-width outline, not a whisper of grey text: skipping the
                // demo has to look like a real choice, because it is one.
                Button("I'll do it later", action: onLater).buttonStyle(.outline)
            } else {
                Button("Continue", action: onLater).buttonStyle(.pill)
            }
        }
        .onAppear { model.introAppeared(in: env) }
    }
}

// MARK: - Camera explanation

/// Stands between "Try it now" and the system prompt. iOS only asks once, so it is worth
/// spending a screen on why.
struct OnboardingCameraExplanationStep: View {
    @Environment(AppEnvironment.self) private var env
    let model: OnboardingPushupsDemoModel
    let onSkip: () -> Void

    var body: some View {
        OnboardingScaffold {
            Text("We use the camera to count your push-ups")
                .font(.serif(38, relativeTo: .largeTitle))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                OnboardingPoint(text: "Nothing leaves your iPhone.")
                OnboardingPoint(text: "The camera runs only while you're doing the set.")
                OnboardingPoint(text: "You can turn it off again in Settings at any time.")
            }
            .padding(.top, Theme.Space.xl)
        } action: {
            Button("Turn on camera") {
                Task { await model.requestCamera(in: env) }
            }
            .buttonStyle(.pill)
            Button("I'll do it later", action: onSkip).buttonStyle(.outline)
        }
        .onAppear { model.explanationAppeared(in: env) }
    }
}

// MARK: - Demo

/// The camera screens. One view for framing, countdown and counting so the capture session
/// is created once and lives exactly as long as the set.
struct OnboardingPushupsDemoStep: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    let model: OnboardingPushupsDemoModel
    let onFinished: () -> Void
    let onSkip: () -> Void

    var body: some View {
        Group {
            switch model.phase {
            case .framing, .countdown, .counting:
                cameraExperience
            case .completed:
                completed
            case .permissionDenied:
                permissionDenied
            case .cameraError:
                cameraError
            case .trouble:
                detectionTrouble
            default:
                Color.clear
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: EarnMotion.standard), value: model.phase)
    }

    // MARK: Camera

    private var cameraExperience: some View {
        ZStack {
            if let detector = model.detector {
                ExerciseCameraView(
                    detector: detector,
                    onSnapshot: { model.received($0, in: env) },
                    onError: { model.cameraFailed($0, in: env) }
                )
                .ignoresSafeArea()
            } else {
                Night.groundDeep.ignoresSafeArea()
            }

            LinearGradient(
                colors: [Night.ground.opacity(0.80), Night.ground.opacity(0.16), Night.ground.opacity(0.84)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if model.phase == .framing {
                framingGuide.allowsHitTesting(false)
            }

            VStack(spacing: Theme.Space.l) {
                header
                Spacer(minLength: Theme.Space.l)
                footer
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.vertical, Theme.Space.l)
        }
    }

    /// A border that changes colour as the framing improves. No reading required from the floor.
    private var framingGuide: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .stroke(cueColor.opacity(0.32), lineWidth: 4)
            .padding(Theme.Space.m)
            .animation(reduceMotion ? nil : .easeOut(duration: EarnMotion.standard), value: model.cue)
    }

    @ViewBuilder
    private var header: some View {
        switch model.phase {
        case .framing:
            framingHeader
        case .countdown:
            countdownHeader
        case .counting:
            countingHeader
        default:
            EmptyView()
        }
    }

    private var framingHeader: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: cueSymbol)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(cueColor)
                .accessibilityHidden(true)
            Text("Do 3 push-ups")
                .font(.sans(40, weight: .bold, relativeTo: .largeTitle))
                .minimumScaleFactor(0.5)
                .lineLimit(2)
            Text(cueDetail)
                .font(.sans(18, weight: .semibold))
                .foregroundStyle(cueColor)
                .minimumScaleFactor(0.7)
                .lineLimit(3)
            Text("Prop your phone up a couple of steps away, in good light.")
                .font(.sans(14))
                .foregroundStyle(Night.textSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.l)
        .padding(.horizontal, Theme.Space.m)
        .background(Night.ground.opacity(0.82), in: .rect(cornerRadius: Night.panelRadius))
        .animation(reduceMotion ? nil : .easeOut(duration: EarnMotion.quick), value: model.cue)
        .accessibilityElement(children: .combine)
    }

    private var countdownHeader: some View {
        VStack(spacing: Theme.Space.s) {
            Text("\(model.countdownValue)")
                .font(.serif(110))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(reduceMotion ? nil : .easeOut(duration: EarnMotion.quick), value: model.countdownValue)
                .frame(width: 170, height: 170)
                .background(Night.ground.opacity(0.86), in: .circle)
            Text("Get set")
                .font(.sans(22, weight: .bold))
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.s)
                .background(Night.ground.opacity(0.82), in: .capsule)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Starting in \(model.countdownValue)"))
    }

    private var countingHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text("\(model.repsDetected)")
                    .font(.serif(84))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeOut(duration: EarnMotion.quick), value: model.repsDetected)
                Text("of \(model.targetReps) push-ups")
                    .font(.sans(22, weight: .semibold))
                    .foregroundStyle(Night.textSoft)
                Spacer(minLength: 0)
            }
            TickMeter(progress: model.progress, height: 22)
            Text(cueDetail)
                .font(.sans(19, weight: .bold))
                .foregroundStyle(Night.cobaltText)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
        }
        .padding(Theme.Space.m)
        .background(Night.ground.opacity(0.9), in: .rect(cornerRadius: Night.panelRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(model.repsDetected) of \(model.targetReps) push-ups"))
    }

    private var footer: some View {
        VStack(spacing: Theme.Space.s) {
            if model.phase == .counting {
                Text("This is a demo. It doesn't add minutes to your balance yet.")
                    .font(.sans(13, weight: .semibold))
                    .foregroundStyle(Night.textSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, Theme.Space.s)
                    .background(Night.ground.opacity(0.82), in: .capsule)
            }
            Button("Cancel", role: .cancel) {
                model.cancel(in: env)
                onSkip()
            }
            .buttonStyle(.outline)
            .background(Night.ground.opacity(0.7), in: .capsule)
        }
    }

    // MARK: Outcomes

    private var completed: some View {
        outcomeLayout(
            symbol: "checkmark",
            tint: Night.moss,
            title: "That's it. This is how you'll earn screen time.",
            detail: "Whenever your apps are paused, you'll be able to unlock them with a set like that one."
        ) {
            Text("Those reps were a demo, so they didn't add any minutes. Your balance starts once your plan is running.")
                .font(.sans(13.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.m)
        } action: {
            Button("Set up my apps", action: onFinished).buttonStyle(.pill)
        }
    }

    private var permissionDenied: some View {
        outcomeLayout(
            symbol: "camera.fill",
            tint: Night.textMuted,
            title: "We couldn't turn on the camera",
            detail: "You can carry on without the demo and turn the camera on later from Settings."
        ) {
            EmptyView()
        } action: {
            Button("Continue without the demo") {
                model.cancel(in: env)
                onSkip()
            }
            .buttonStyle(.pill)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.outline)
        }
    }

    private var cameraError: some View {
        outcomeLayout(
            symbol: "exclamationmark.triangle",
            tint: Night.textMuted,
            title: "We couldn't turn on the camera",
            detail: "You can carry on without the demo and try it again whenever you like."
        ) {
            if !model.errorMessage.isEmpty {
                Text(model.errorMessage)
                    .font(.sans(13.5))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Space.m)
            }
        } action: {
            Button("Try again") { model.retry(in: env) }.buttonStyle(.pill)
            Button("Continue without the demo") {
                model.cancel(in: env)
                onSkip()
            }
            .buttonStyle(.outline)
        }
    }

    /// Nothing here says the user failed. The camera did not find them yet; that is all.
    /// Leads with the fix for what framing last saw, then the general checklist. After a
    /// second miss the way on becomes the primary action: the demo is optional, and a person
    /// stuck on it is a person about to leave onboarding.
    private var detectionTrouble: some View {
        let hasRetried = model.troubleCount >= 2
        return outcomeLayout(
            symbol: "viewfinder",
            tint: Night.cobaltText,
            title: "We can't see you yet",
            detail: hasRetried
                ? "No problem. You can try it any time from Home."
                : "A couple of small changes usually fix it."
        ) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                OnboardingPoint(text: troubleTip)
                if model.troubleCue != .moveBack {
                    OnboardingPoint(text: "Point it so your whole body fits in the frame.")
                }
                if model.troubleCue != .lighting {
                    OnboardingPoint(text: "Turn on a light if the room is dim.")
                }
            }
            .padding(.top, Theme.Space.l)
        } action: {
            if hasRetried {
                Button("Continue without the demo") {
                    model.cancel(in: env)
                    onSkip()
                }
                .buttonStyle(.pill)
                Button("Try once more") { model.retry(in: env) }.buttonStyle(.outline)
            } else {
                Button("Try again") { model.retry(in: env) }.buttonStyle(.pill)
                Button("Continue without the demo") {
                    model.cancel(in: env)
                    onSkip()
                }
                .buttonStyle(.outline)
            }
        }
    }

    private var troubleTip: LocalizedStringKey {
        switch model.troubleCue {
        case .tooFar: "You looked far away. Put the phone about two steps from where your head will be."
        case .lighting: "It was too dark to see your joints. Face a window or turn on a light."
        case .moveBack: "Part of you was out of frame. Step back until your head and feet both fit."
        case .searching, .ready: "Prop the phone against something, two or three steps away, facing your side."
        }
    }

    private func outcomeLayout<Content: View, Action: View>(
        symbol: String,
        tint: Color,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action
    ) -> some View {
        OnboardingScaffold {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(Night.panel, in: .rect(cornerRadius: Night.panelRadius))
                .accessibilityHidden(true)
            Text(title)
                .font(.serif(38, relativeTo: .largeTitle))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.l)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.sans(17))
                .foregroundStyle(Night.textSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.m)
            content()
        } action: {
            action()
        }
    }

    private var cueColor: Color {
        switch model.cue {
        case .ready: Night.moss
        case .searching: Night.text
        default: Night.cobaltText
        }
    }

    private var cueSymbol: String {
        switch model.cue {
        case .searching: "person.and.background.dotted"
        case .tooFar: "arrow.down.forward.and.arrow.up.backward"
        case .lighting: "lightbulb.max"
        case .moveBack: "arrow.up.backward.and.arrow.down.forward"
        case .ready: "checkmark.circle.fill"
        }
    }

    private var cueDetail: LocalizedStringKey {
        switch model.cue {
        case .searching: "Looking for you"
        case .tooFar: "Come a little closer"
        case .lighting: "A bit more light, please"
        case .moveBack: "Move back so your whole body fits"
        case .ready: "Got you"
        }
    }
}

// MARK: - Later

/// Where "I'll do it later" lands. The demo stays available, and nothing was lost.
struct OnboardingPushupsLaterStep: View {
    let model: OnboardingPushupsDemoModel
    let onContinue: () -> Void

    var body: some View {
        OnboardingScaffold(
            progress: Double(OnboardingView.Route.pushupsLater.progress) / Double(OnboardingView.Route.progressCount)
        ) {
            Text("You can try it whenever you want")
                .font(.serif(38, relativeTo: .largeTitle))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("You'll find it on your home screen, and every time a paused app asks you to earn your way in.")
                .font(.sans(15))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.l)
        } action: {
            Button("Continue", action: onContinue).buttonStyle(.pill)
        }
    }
}
