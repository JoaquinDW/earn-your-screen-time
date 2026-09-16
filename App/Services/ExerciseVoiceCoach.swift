import AVFoundation
import AudioToolbox
import Foundation

/// Spoken and audible coaching for the camera exercises.
///
/// During a set the athlete is a couple of metres from a phone they physically cannot read,
/// so every state the camera flow wants to communicate — framing, the countdown, each counted
/// repetition — also has to arrive by ear. Speech is throttled so a jittery detector cannot
/// turn into a stutter of half-sentences.
@MainActor
final class ExerciseVoiceCoach {
    static let preferenceKey = "exercise.voice.enabled.v1"

    static var isEnabled: Bool {
        get {
            guard AppGroup.defaults.object(forKey: preferenceKey) != nil else { return true }
            return AppGroup.defaults.bool(forKey: preferenceKey)
        }
        set { AppGroup.defaults.set(newValue, forKey: preferenceKey) }
    }

    /// Shortest gap between two different phrases. Below this the athlete hears a pile-up.
    private static let minimumGap: TimeInterval = 1.1

    private let synthesizer = AVSpeechSynthesizer()
    private var lastPhrase: String?
    private var lastSpokenAt = Date.distantPast
    private var sessionActive = false

    /// - Parameters:
    ///   - repeatAfter: how long the same phrase stays suppressed, so a held cue is not chanted.
    ///   - interrupting: cuts the current utterance short. For cues that stop being true the
    ///     moment they are spoken, such as the countdown or a counted repetition.
    func say(_ phrase: String, repeatAfter: TimeInterval = 7, interrupting: Bool = false) {
        guard Self.isEnabled else { return }
        let phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }

        let now = Date()
        if phrase == lastPhrase, now.timeIntervalSince(lastSpokenAt) < repeatAfter { return }
        // Cues are offered on every camera frame, so a phrase that arrives mid-sentence is
        // dropped rather than queued: the next frame offers it again once the voice is free.
        if !interrupting, synthesizer.isSpeaking { return }
        if !interrupting, now.timeIntervalSince(lastSpokenAt) < Self.minimumGap { return }

        lastPhrase = phrase
        lastSpokenAt = now
        activateSession()
        if interrupting, synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        utterance.postUtteranceDelay = 0.05
        synthesizer.speak(utterance)
    }

    /// A short tick for moments that need to land without waiting for a sentence.
    func tick() {
        guard Self.isEnabled else { return }
        AudioServicesPlaySystemSound(1113)
    }

    func stop() {
        lastPhrase = nil
        lastSpokenAt = .distantPast
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        guard sessionActive else { return }
        sessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Ducks whatever the athlete is training to instead of stopping it, and keeps the cues
    /// audible on a phone whose ringer switch is silenced.
    private func activateSession() {
        guard !sessionActive else { return }
        sessionActive = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true)
    }
}
