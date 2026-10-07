import EarnDomain
import SwiftUI

enum PushupsLocalization {
    static let tableName = "PushupsLocalizable"

    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: tableName)
    }
}

struct PushupsText: View {
    private let key: LocalizedStringKey

    init(_ key: LocalizedStringKey) {
        self.key = key
    }

    var body: some View {
        Text(key, tableName: PushupsLocalization.tableName)
    }
}

/// Copy that names the exercise or describes its position. Everything else in the flow — the
/// countdown, claiming, errors — reads the same for both and keeps its `pushups.*` key.
extension ExerciseKind {
    var nameKey: LocalizedStringKey {
        switch self {
        case .pushup: "pushups.name"
        case .squat: "squats.name"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .pushup: "pushups.title"
        case .squat: "squats.title"
        }
    }

    var pickerDetailKey: LocalizedStringKey {
        switch self {
        case .pushup: "pushups.picker.detail"
        case .squat: "squats.picker.detail"
        }
    }

    var privacyDetailKey: LocalizedStringKey {
        switch self {
        case .pushup: "pushups.privacy.detail"
        case .squat: "squats.privacy.detail"
        }
    }

    var autoStartHintKey: LocalizedStringKey {
        switch self {
        case .pushup: "pushups.setup.auto_hint"
        case .squat: "squats.setup.auto_hint"
        }
    }

    var limitEyebrowKey: LocalizedStringKey {
        switch self {
        case .pushup: "pushups.limit.eyebrow"
        case .squat: "squats.limit.eyebrow"
        }
    }

    var loadingAccessibilityKey: LocalizedStringKey {
        switch self {
        case .pushup: "pushups.loading.accessibility"
        case .squat: "squats.loading.accessibility"
        }
    }

    func repsKey(_ reps: Int) -> LocalizedStringKey {
        switch self {
        case .pushup: "pushups.challenge.reps \(reps)"
        case .squat: "squats.challenge.reps \(reps)"
        }
    }

    func challengeAccessibilityKey(reps: Int, minutes: Int) -> LocalizedStringKey {
        switch self {
        case .pushup: "pushups.challenge.accessibility \(reps) \(minutes)"
        case .squat: "squats.challenge.accessibility \(reps) \(minutes)"
        }
    }

    func activeOfKey(_ target: Int) -> LocalizedStringKey {
        switch self {
        case .pushup: "pushups.active.of \(target)"
        case .squat: "squats.active.of \(target)"
        }
    }

    func activeProgressKey(_ count: Int, of target: Int) -> LocalizedStringKey {
        switch self {
        case .pushup: "pushups.active.progress \(count) \(target)"
        case .squat: "squats.active.progress \(count) \(target)"
        }
    }

    func successDetailKey(_ reps: Int) -> LocalizedStringKey {
        switch self {
        case .pushup: "pushups.success.detail \(reps)"
        case .squat: "squats.success.detail \(reps)"
        }
    }

    func limitDetailKey(_ time: String) -> LocalizedStringKey {
        switch self {
        case .pushup: "pushups.limit.detail \(time)"
        case .squat: "squats.limit.detail \(time)"
        }
    }

    func cueHeadlineKey(_ cue: PushupsToEarnModel.SetupCue) -> LocalizedStringKey {
        switch (self, cue) {
        case (_, .searching): "pushups.cue.searching"
        case (_, .tooFar): "pushups.cue.too_far"
        case (_, .lighting): "pushups.cue.lighting"
        case (_, .moveBack): "pushups.cue.move_back"
        case (.pushup, .posture): "pushups.cue.plank"
        case (.squat, .posture): "squats.cue.posture"
        case (.pushup, .startPosition): "pushups.cue.arms_extended"
        case (.squat, .startPosition): "squats.cue.start"
        case (_, .holding): "pushups.cue.holding"
        }
    }

    func cueDetailKey(_ cue: PushupsToEarnModel.SetupCue) -> LocalizedStringKey {
        switch (self, cue) {
        case (.pushup, .searching): "pushups.cue.searching.detail"
        case (.squat, .searching): "squats.cue.searching.detail"
        case (.pushup, .tooFar): "pushups.cue.too_far.detail"
        case (.squat, .tooFar): "squats.cue.too_far.detail"
        case (_, .lighting): "pushups.cue.lighting.detail"
        case (_, .moveBack): "pushups.cue.move_back.detail"
        case (.pushup, .posture): "pushups.cue.plank.detail"
        case (.squat, .posture): "squats.cue.posture.detail"
        case (.pushup, .startPosition): "pushups.cue.arms_extended.detail"
        case (.squat, .startPosition): "squats.cue.start.detail"
        case (_, .holding): "pushups.cue.holding.detail"
        }
    }

    func guidanceKey(_ guidance: ExerciseDetectionSnapshot.Guidance) -> LocalizedStringKey {
        switch (self, guidance) {
        case (_, .findBody): "pushups.guidance.find_body"
        case (_, .improveLighting): "pushups.guidance.improve_lighting"
        case (_, .moveIntoFrame): "pushups.guidance.move_into_frame"
        case (.pushup, .fixPosture): "pushups.guidance.straighten_body"
        case (.squat, .fixPosture): "squats.guidance.stand_upright"
        case (.pushup, .startAtTop): "pushups.guidance.start_at_top"
        case (.squat, .startAtTop): "squats.guidance.start_standing"
        case (.pushup, .goDown): "pushups.guidance.lower_body"
        case (.squat, .goDown): "squats.guidance.lower_hips"
        case (.pushup, .comeUp): "pushups.guidance.push_up"
        case (.squat, .comeUp): "squats.guidance.stand_up"
        case (_, .slowDown): "pushups.guidance.slow_down"
        case (_, .none): "pushups.guidance.keep_going"
        }
    }

    // MARK: - Spoken

    var voiceIntro: String {
        switch self {
        case .pushup: PushupsLocalization.string("pushups.voice.intro")
        case .squat: PushupsLocalization.string("squats.voice.intro")
        }
    }

    var startedAnnouncement: String {
        switch self {
        case .pushup: PushupsLocalization.string("pushups.active.started")
        case .squat: PushupsLocalization.string("squats.active.started")
        }
    }

    func repAnnouncement(_ count: Int, of target: Int) -> String {
        switch self {
        case .pushup: PushupsLocalization.string("pushups.active.rep_announcement \(count) \(target)")
        case .squat: PushupsLocalization.string("squats.active.rep_announcement \(count) \(target)")
        }
    }

    func voiceCue(_ cue: PushupsToEarnModel.SetupCue) -> String {
        switch (self, cue) {
        case (.pushup, .searching): PushupsLocalization.string("pushups.voice.searching")
        case (.squat, .searching): PushupsLocalization.string("squats.voice.searching")
        case (_, .tooFar): PushupsLocalization.string("pushups.voice.too_far")
        case (_, .lighting): PushupsLocalization.string("pushups.voice.lighting")
        case (_, .moveBack): PushupsLocalization.string("pushups.voice.move_back")
        case (.pushup, .posture): PushupsLocalization.string("pushups.voice.plank")
        case (.squat, .posture): PushupsLocalization.string("squats.voice.posture")
        case (.pushup, .startPosition): PushupsLocalization.string("pushups.voice.arms_extended")
        case (.squat, .startPosition): PushupsLocalization.string("squats.voice.start")
        case (_, .holding): PushupsLocalization.string("pushups.voice.holding")
        }
    }
}
