import EarnDomain
import SwiftUI
import UIKit

struct PushupsToEarnView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var model = PushupsToEarnModel()

    let onUseMinutes: () -> Void

    var body: some View {
        Group {
            if usesCamera {
                cameraExperience
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Space.gutter)
                    .padding(.top, Theme.Space.l)
                    .padding(.bottom, Theme.Space.xxl)
                }
            }
        }
        .background(Night.ground.ignoresSafeArea())
        .foregroundStyle(Night.text)
        .navigationTitle(Text("pushups.title", tableName: PushupsLocalization.tableName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Night.ground, for: .navigationBar)
        .trackScreen("pushups_to_earn", analytics: env.analytics)
        .task { await model.appeared(in: env) }
        .onDisappear { model.close(in: env) }
    }

    private var usesCamera: Bool {
        switch model.phase {
        case .setup, .starting, .countdown, .active:
            true
        default:
            false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            loading
        case .picker:
            picker
        case .claiming:
            processing(title: "pushups.claiming.title", detail: "pushups.claiming.detail")
        case .pending:
            pending
        case .success:
            success
        case .dailyCap:
            dailyCap
        case .error:
            error
        case .setup, .starting, .countdown, .active:
            EmptyView()
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            NightEyebrow(text: "pushups.mission", tableName: PushupsLocalization.tableName)
            PushupsText("pushups.picker.title")
                .font(.serif(42))
                .fixedSize(horizontal: false, vertical: true)
            PushupsText("pushups.picker.detail")
                .font(.sans(17))
                .foregroundStyle(Night.textSoft)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(model.challenges, id: \.targetReps) { challenge in
                    challengeRow(challenge)
                    if challenge.targetReps != model.challenges.last?.targetReps {
                        NightHairline(inset: Theme.Space.m)
                    }
                }
            }
            .background(Night.panel, in: .rect(cornerRadius: Night.panelRadius))

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Label {
                    PushupsText("pushups.privacy.title")
                } icon: {
                    Image(systemName: "figure.strengthtraining.traditional")
                }
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Night.textSoft)
                PushupsText("pushups.privacy.detail")
                    .font(.sans(13))
                    .foregroundStyle(Night.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await model.prepareCamera(in: env) }
            } label: {
                PushupsText("pushups.picker.cta")
            }
            .buttonStyle(.nightPill)
            .disabled(model.selectedChallenge == nil)
        }
    }

    private func challengeRow(_ challenge: ExerciseChallenge) -> some View {
        let selected = model.selectedChallenge == challenge
        let available = challenge.rewardSeconds <= (model.configuration?.rewardSecondsRemaining ?? 0)
        return Button {
            model.select(challenge, in: env)
        } label: {
            HStack(spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    PushupsText("pushups.challenge.reps \(challenge.targetReps)")
                        .font(.sans(17, weight: .semibold))
                    PushupsText("pushups.challenge.reward \(challenge.rewardSeconds / 60)")
                        .font(.sans(13))
                        .foregroundStyle(available ? Night.cobaltText : Night.textDim)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(selected ? Night.cobaltText : Night.textFaint)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.45)
        .accessibilityLabel(Text(
            "pushups.challenge.accessibility \(challenge.targetReps) \(challenge.rewardSeconds / 60)",
            tableName: PushupsLocalization.tableName
        ))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var cameraExperience: some View {
        ZStack {
            if let detector = model.detector {
                PushupCameraView(
                    detector: detector,
                    onSnapshot: { model.received($0, in: env) },
                    onError: { model.cameraFailed($0, in: env) }
                )
                .ignoresSafeArea()
            }

            LinearGradient(
                colors: [Night.ground.opacity(0.78), Night.ground.opacity(0.18), Night.ground.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if model.phase == .setup {
                framingGuide.allowsHitTesting(false)
            }

            VStack(spacing: Theme.Space.l) {
                cameraHeader
                Spacer(minLength: Theme.Space.l)
                cameraFooter
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, Theme.Space.l)
            .padding(.bottom, Theme.Space.l)
        }
    }

    /// The only feedback that works at arm's-length-times-three: a border that changes colour
    /// and then draws itself closed while the position is held. No reading required.
    private var framingGuide: some View {
        let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)
        return shape
            .stroke(setupCueColor.opacity(0.28), lineWidth: 4)
            .overlay {
                shape
                    .trim(from: 0, to: model.setupHoldProgress)
                    .stroke(Night.moss, style: StrokeStyle(lineWidth: 8, lineCap: .round))
            }
            .padding(Theme.Space.m)
            .animation(.easeOut(duration: EarnMotion.quick), value: model.setupHoldProgress)
            .animation(.easeOut(duration: EarnMotion.standard), value: model.setupCue)
    }

    @ViewBuilder
    private var cameraHeader: some View {
        switch model.phase {
        case .setup:
            setupHeader
        case .starting:
            cameraPanel(title: "pushups.starting.title", detail: "pushups.starting.detail")
        case .countdown:
            countdownHeader
        case .active:
            activeHeader
        default:
            EmptyView()
        }
    }

    private var setupHeader: some View {
        VStack(spacing: Theme.Space.l) {
            HStack {
                Spacer()
                voiceToggle
            }

            VStack(spacing: Theme.Space.s) {
                Image(systemName: setupCueSymbol)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(setupCueColor)
                    .accessibilityHidden(true)
                // Sized to be read from a plank two metres away, not to sit politely in a card.
                PushupsText(setupCueHeadlineKey)
                    .font(.sans(44, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(setupCueColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                PushupsText(setupCueDetailKey)
                    .font(.sans(19, weight: .semibold))
                    .foregroundStyle(Night.textSoft)
                    .minimumScaleFactor(0.7)
                    .lineLimit(3)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.l)
            .padding(.horizontal, Theme.Space.m)
            .background(Night.ground.opacity(0.82), in: .rect(cornerRadius: Night.panelRadius))
            .animation(.easeOut(duration: EarnMotion.quick), value: model.setupCue)
            .accessibilityElement(children: .combine)
        }
    }

    private var voiceToggle: some View {
        Button {
            model.toggleVoice()
        } label: {
            Image(systemName: model.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(model.voiceEnabled ? Night.text : Night.textMuted)
                .frame(width: 44, height: 44)
                .background(Night.ground.opacity(0.82), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(
            model.voiceEnabled ? "pushups.voice.disable" : "pushups.voice.enable",
            tableName: PushupsLocalization.tableName
        ))
    }

    private var countdownHeader: some View {
        VStack(spacing: Theme.Space.s) {
            Text("\(model.countdownValue)")
                .font(.serif(120))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.easeOut(duration: EarnMotion.quick), value: model.countdownValue)
                .frame(width: 180, height: 180)
                .background(Night.ground.opacity(0.86), in: .circle)
            PushupsText(model.startedAutomatically ? "pushups.countdown.hold" : "pushups.countdown.get_set")
                .font(.sans(22, weight: .bold))
                .foregroundStyle(Night.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.s)
                .background(Night.ground.opacity(0.82), in: .capsule)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            "pushups.countdown.accessibility \(model.countdownValue)",
            tableName: PushupsLocalization.tableName
        ))
    }

    private var activeHeader: some View {
        VStack(spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text("\(model.repetitionCount)")
                    .font(.serif(84))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: EarnMotion.quick), value: model.repetitionCount)
                PushupsText("pushups.active.of \(model.targetReps)")
                    .font(.sans(22, weight: .semibold))
                    .foregroundStyle(Night.textSoft)
                Spacer()
            }
            TickMeter(progress: model.progress, height: 22)
            PushupsText(activeGuidanceKey)
                .font(.sans(20, weight: .bold))
                .foregroundStyle(Night.cobaltText)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Space.m)
        .background(Night.ground.opacity(0.9), in: .rect(cornerRadius: Night.panelRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            "pushups.active.progress \(model.repetitionCount) \(model.targetReps)",
            tableName: PushupsLocalization.tableName
        ))
    }

    @ViewBuilder
    private var cameraFooter: some View {
        switch model.phase {
        case .setup:
            VStack(spacing: Theme.Space.m) {
                Label {
                    PushupsText(model.setupReady ? "pushups.setup.starting" : "pushups.setup.auto_hint")
                } icon: {
                    Image(systemName: model.setupReady ? "checkmark.circle.fill" : "viewfinder")
                }
                .font(.sans(16, weight: .semibold))
                .foregroundStyle(model.setupReady ? Night.moss : Night.textSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(Theme.Space.m)
                .background(Night.ground.opacity(0.88), in: .rect(cornerRadius: Night.panelRadius))

                // The escape hatch for a camera that never converges. It buys a long countdown
                // instead of demanding a tap from someone already lying on the floor.
                Button {
                    Task { await model.start(in: env, automatic: false) }
                } label: {
                    PushupsText("pushups.setup.manual \(PushupsToEarnModel.manualCountdownSeconds)")
                }
                .buttonStyle(.quietLink)
                .frame(maxWidth: .infinity)
            }
        case .active:
            HStack(spacing: Theme.Space.m) {
                PushupsText("pushups.active.reward \(model.selectedRewardMinutes)")
                    .foregroundStyle(Night.cobaltText)
                PushupsText("pushups.active.camera_note")
                    .foregroundStyle(Night.textSoft)
            }
            .font(.sans(13, weight: .semibold))
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .background(Night.ground.opacity(0.82), in: .capsule)
        default:
            EmptyView()
        }
    }

    private var setupCueColor: Color {
        switch model.setupCue {
        case .holding: Night.moss
        case .armsExtended: Night.cobaltText
        default: Night.text
        }
    }

    private var setupCueSymbol: String {
        switch model.setupCue {
        case .searching: "person.and.background.dotted"
        case .tooFar: "arrow.down.forward.and.arrow.up.backward"
        case .lighting: "lightbulb.max"
        case .moveBack: "arrow.up.backward.and.arrow.down.forward"
        case .plank: "figure.strengthtraining.traditional"
        case .armsExtended: "arrow.up.circle"
        case .holding: "checkmark.circle.fill"
        }
    }

    private var setupCueHeadlineKey: LocalizedStringKey {
        switch model.setupCue {
        case .searching: "pushups.cue.searching"
        case .tooFar: "pushups.cue.too_far"
        case .lighting: "pushups.cue.lighting"
        case .moveBack: "pushups.cue.move_back"
        case .plank: "pushups.cue.plank"
        case .armsExtended: "pushups.cue.arms_extended"
        case .holding: "pushups.cue.holding"
        }
    }

    private var setupCueDetailKey: LocalizedStringKey {
        switch model.setupCue {
        case .searching: "pushups.cue.searching.detail"
        case .tooFar: "pushups.cue.too_far.detail"
        case .lighting: "pushups.cue.lighting.detail"
        case .moveBack: "pushups.cue.move_back.detail"
        case .plank: "pushups.cue.plank.detail"
        case .armsExtended: "pushups.cue.arms_extended.detail"
        case .holding: "pushups.cue.holding.detail"
        }
    }

    private var activeGuidanceKey: LocalizedStringKey {
        guard let guidance = model.snapshot?.guidance else { return "pushups.guidance.find_body" }
        return switch guidance {
        case .findBody: "pushups.guidance.find_body"
        case .improveLighting: "pushups.guidance.improve_lighting"
        case .moveIntoFrame: "pushups.guidance.move_into_frame"
        case .straightenBody: "pushups.guidance.straighten_body"
        case .startAtTop: "pushups.guidance.start_at_top"
        case .lowerBody: "pushups.guidance.lower_body"
        case .pushUp: "pushups.guidance.push_up"
        case .slowDown: "pushups.guidance.slow_down"
        case .none: "pushups.guidance.keep_going"
        }
    }

    private var pending: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            stateSymbol("arrow.trianglehead.2.clockwise.rotate.90", color: Night.cobaltText)
            NightEyebrow(text: "pushups.pending.eyebrow", tableName: PushupsLocalization.tableName)
            PushupsText("pushups.pending.title").font(.serif(42))
            PushupsText("pushups.pending.detail")
                .font(.sans(17))
                .foregroundStyle(Night.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            if !model.errorMessage.isEmpty {
                Text(model.errorMessage)
                    .font(.sans(13))
                    .foregroundStyle(Night.textDim)
            }
            Button {
                Task { await model.retryPendingClaim(in: env) }
            } label: {
                PushupsText("pushups.pending.retry")
            }
            .buttonStyle(.nightPill)
        }
    }

    private var success: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            stateSymbol("checkmark", color: Night.moss)
            NightEyebrow(text: "pushups.success.eyebrow", tableName: PushupsLocalization.tableName)
            PushupsText("pushups.success.title \(model.earnedRewardMinutes)")
                .font(.serif(44))
                .fixedSize(horizontal: false, vertical: true)
            PushupsText("pushups.success.detail \(model.targetReps)")
                .font(.sans(17))
                .foregroundStyle(Night.textSoft)
            Button {
                dismiss()
                onUseMinutes()
            } label: {
                PushupsText("pushups.success.use")
            }
            .buttonStyle(.nightPill)
            Button {
                Task { await model.doAnother(in: env) }
            } label: {
                PushupsText("pushups.success.again")
            }
            .buttonStyle(.quietLink)
            .frame(maxWidth: .infinity)
        }
    }

    private var dailyCap: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            stateSymbol("moon.stars", color: Night.textMuted)
            NightEyebrow(text: "pushups.limit.eyebrow", tableName: PushupsLocalization.tableName)
            PushupsText("pushups.limit.title").font(.serif(42))
            if let resetsAt = model.configuration?.resetsAt {
                PushupsText("pushups.limit.detail \(resetsAt.formatted(date: .omitted, time: .shortened))")
                    .font(.sans(17))
                    .foregroundStyle(Night.textSoft)
            } else {
                PushupsText("pushups.limit.detail.fallback")
                    .font(.sans(17))
                    .foregroundStyle(Night.textSoft)
            }
        }
    }

    private var error: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            stateSymbol(model.cameraPermissionDenied ? "camera.fill" : "figure.strengthtraining.traditional", color: Night.textMuted)
            NightEyebrow(text: "pushups.error.eyebrow", tableName: PushupsLocalization.tableName)
            PushupsText(model.cameraPermissionDenied ? "pushups.permission.title" : "pushups.error.title")
                .font(.serif(42))
            Text(model.errorMessage)
                .font(.sans(16))
                .foregroundStyle(Night.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            if model.cameraPermissionDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    PushupsText("pushups.permission.settings")
                }
                .buttonStyle(.nightPill)
            } else {
                Button {
                    Task { await model.retry(in: env) }
                } label: {
                    PushupsText("pushups.error.retry")
                }
                .buttonStyle(.nightPill)
            }
        }
    }

    private var loading: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            NightEyebrow(text: "pushups.mission", tableName: PushupsLocalization.tableName)
            PushupsText("pushups.loading.title").font(.serif(38))
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                ForEach([0.84, 0.68, 0.76], id: \.self) { width in
                    Capsule()
                        .fill(Night.text.opacity(0.09))
                        .frame(maxWidth: .infinity)
                        .frame(height: 12)
                        .scaleEffect(x: width, anchor: .leading)
                }
            }
            .padding(Theme.Space.l)
            .background(Night.panel, in: .rect(cornerRadius: Night.panelRadius))
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel(Text(
            "pushups.loading.accessibility",
            tableName: PushupsLocalization.tableName
        ))
    }

    private func processing(title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            ProgressView().tint(Night.cobalt).controlSize(.large)
            PushupsText(title).font(.serif(38))
            PushupsText(detail).font(.sans(16)).foregroundStyle(Night.textSoft)
        }
        .accessibilityElement(children: .combine)
    }

    private func cameraPanel(title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(spacing: Theme.Space.s) {
            ProgressView().tint(Night.cobalt)
            PushupsText(title).font(.sans(18, weight: .semibold))
            PushupsText(detail)
                .font(.sans(13))
                .foregroundStyle(Night.textSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.m)
        .background(Night.ground.opacity(0.9), in: .rect(cornerRadius: Night.panelRadius))
    }

    private func stateSymbol(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 64, height: 64)
            .background(Night.panel, in: .rect(cornerRadius: Night.panelRadius))
            .accessibilityHidden(true)
    }
}
