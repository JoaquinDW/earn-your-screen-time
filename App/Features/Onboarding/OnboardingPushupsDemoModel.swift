import AVFoundation
import AudioToolbox
import EarnDomain
import Foundation
import Observation
import UIKit

/// Drives the optional push-up demo inside onboarding.
///
/// It deliberately shares nothing with `PushupsToEarnModel`: no backend session, no claim, no
/// wallet. Three reps in front of the camera prove the product works and then the flow moves
/// on. `OnboardingPushupDemo` owns every transition so the paths are testable without a camera.
@MainActor
@Observable
final class OnboardingPushupsDemoModel {
    /// What the athlete has to change before the set can begin, read from across the room.
    enum FramingCue: Equatable {
        case searching
        case tooFar
        case lighting
        case moveBack
        case ready

        var analyticsValue: String {
            switch self {
            case .searching: "searching"
            case .tooFar: "too_far"
            case .lighting: "lighting"
            case .moveBack: "move_back"
            case .ready: "ready"
            }
        }
    }

    private(set) var demo: OnboardingPushupDemo
    private(set) var detector: VisionExerciseDetector?
    private(set) var cue = FramingCue.searching
    /// The last thing framing asked for before it gave up — what the trouble screen leads with.
    private(set) var troubleCue = FramingCue.searching
    /// Every real completion so far needed a retry; after two misses the demo stops insisting.
    private(set) var troubleCount = 0
    /// A device-level camera failure, shown verbatim on the error screen.
    private(set) var errorMessage = ""

    private var countdownTask: Task<Void, Never>?
    private var startedAt: Date?
    private var introTracked = false
    private var explanationTracked = false
    private var isClosed = false
    #if targetEnvironment(simulator)
    private var rehearsalTask: Task<Void, Never>?
    #endif

    init(demo: OnboardingPushupDemo? = nil) {
        self.demo = demo ?? OnboardingPushupDemo(isSupported: OnboardingPushupsDemoModel.isDetectionSupported)
    }

    /// Pose detection needs a front camera. Without one the intro promises nothing.
    /// The Simulator has no camera but does run the flow against a scripted rehearsal, the
    /// same way `AppEnvironment` substitutes mock Health and Screen Time services there.
    nonisolated static var isDetectionSupported: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
        #endif
    }

    var phase: OnboardingPushupDemo.Phase { demo.phase }
    var repsDetected: Int { demo.repsDetected }
    var targetReps: Int { OnboardingPushupDemo.targetReps }
    var countdownValue: Int { demo.countdownRemaining }
    var progress: Double { demo.progress }
    var offersDemo: Bool { demo.isSupported }

    // MARK: - Intro

    func introAppeared(in environment: AppEnvironment) {
        guard !introTracked else { return }
        introTracked = true
        environment.analytics.track(.onboardingPushupsIntroViewed.withProperties([
            "detection_supported": .bool(demo.isSupported)
        ]))
    }

    func tapTryNow(in environment: AppEnvironment) {
        guard demo.isSupported else { return }
        demo.tryNow()
        environment.analytics.track(.onboardingPushupsTryNowTapped)
    }

    func explanationAppeared(in environment: AppEnvironment) {
        guard !explanationTracked else { return }
        explanationTracked = true
        environment.analytics.track(.onboardingCameraExplanationViewed.withProperties([
            "camera_permission_status": .string(Self.permissionStatus.analyticsValue)
        ]))
    }

    /// "I'll do it later", from the intro. No permission is requested on this path.
    func tapLater(in environment: AppEnvironment) {
        demo.skip()
        environment.analytics.track(.onboardingPushupsLaterTapped)
        environment.recordOnboardingPushupDemo(demo.outcome)
    }

    // MARK: - Camera

    /// Asks for camera access, but only after the contextual explanation has been shown.
    func requestCamera(in environment: AppEnvironment) async {
        guard demo.phase == .cameraExplanation else { return }
        let status = Self.permissionStatus
        switch status {
        case .authorized:
            beginDemo(in: environment)
        case .notDetermined:
            environment.analytics.track(.onboardingCameraPermissionRequested)
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard !isClosed else { return }
            if granted {
                environment.analytics.track(.onboardingCameraPermissionGranted)
                beginDemo(in: environment)
            } else {
                environment.analytics.track(.onboardingCameraPermissionDenied.withProperties([
                    "camera_permission_status": .string(Self.permissionStatus.analyticsValue)
                ]))
                demo.cameraDenied()
            }
        case .denied, .restricted:
            environment.analytics.track(.onboardingCameraPermissionDenied.withProperties([
                "camera_permission_status": .string(status.analyticsValue)
            ]))
            demo.cameraDenied()
        @unknown default:
            fail(with: .cameraUnavailable, in: environment)
        }
    }

    func received(_ snapshot: ExerciseDetectionSnapshot, in environment: AppEnvironment) {
        cue = Self.cue(for: snapshot)
        if cue != .ready, cue != .searching || troubleCue == .searching { troubleCue = cue }
        switch demo.phase {
        case .framing, .countdown:
            let started = demo.observed(bodyVisible: cue == .ready, at: Self.now)
            if started { beginCountdown(in: environment) }
            if demo.phase == .framing { countdownTask?.cancel() }
            if demo.phase == .trouble {
                stopDetecting()
                troubleCount += 1
                environment.analytics.track(.onboardingPushupsDemoTrouble.withProperties([
                    "last_cue": .string(troubleCue.analyticsValue),
                    "trouble_count": .int(troubleCount),
                    "seconds_since_start": .int(secondsSinceStart)
                ]))
            }
        case .counting:
            guard snapshot.didCountRep else { return }
            countRep(in: environment)
        default:
            break
        }
    }

    func cameraFailed(_ error: ExerciseDetectorError, in environment: AppEnvironment) {
        guard error != .permissionDenied else {
            environment.analytics.track(.onboardingCameraPermissionDenied.withProperties([
                "camera_permission_status": .string(Self.permissionStatus.analyticsValue)
            ]))
            demo.cameraDenied()
            stopDetecting()
            return
        }
        fail(with: error, in: environment)
    }

    // MARK: - Exits

    /// Cancel, from the prep screen or mid-set. Onboarding continues either way.
    func cancel(in environment: AppEnvironment) {
        guard !demo.isFinished else { return }
        let reason = demo.exitReason ?? .cancelled
        demo.cancel()
        stopDetecting()
        trackAbandon(reason: reason, in: environment)
        environment.recordOnboardingPushupDemo(demo.outcome)
    }

    func retry(in environment: AppEnvironment) {
        guard demo.phase == .trouble || demo.phase == .cameraError else { return }
        errorMessage = ""
        demo.retry(at: Self.now)
        cue = .searching
        troubleCue = .searching
        startDetecting()
        environment.analytics.track(.onboardingPushupsDemoStarted.withProperties([
            "attempt": .string("retry")
        ]))
        startedAt = Date()
        beginRehearsalIfNeeded(in: environment)
    }

    /// Called when the demo screens go away for any reason, including a swipe back.
    func close(in environment: AppEnvironment) {
        isClosed = true
        stopDetecting()
        guard !demo.isFinished, demo.hasStarted else { return }
        let reason = demo.exitReason ?? .cancelled
        demo.cancel()
        trackAbandon(reason: reason, in: environment)
        environment.recordOnboardingPushupDemo(demo.outcome)
    }

    // MARK: - Internals

    private func beginDemo(in environment: AppEnvironment) {
        demo.cameraReady(at: Self.now)
        cue = .searching
        startedAt = Date()
        errorMessage = ""
        startDetecting()
        environment.analytics.track(.onboardingPushupsDemoStarted.withProperties([
            "attempt": .string("first"),
            "target_reps": .int(targetReps)
        ]))
        beginRehearsalIfNeeded(in: environment)
    }

    private func startDetecting() {
        #if targetEnvironment(simulator)
        detector = nil
        #else
        let detector = VisionExerciseDetector()
        detector.setCountingEnabled(false)
        self.detector = detector
        #endif
    }

    private func stopDetecting() {
        countdownTask?.cancel()
        countdownTask = nil
        detector?.setCountingEnabled(false)
        detector?.stop()
        detector = nil
        #if targetEnvironment(simulator)
        rehearsalTask?.cancel()
        rehearsalTask = nil
        #endif
    }

    private func beginCountdown(in environment: AppEnvironment) {
        countdownTask?.cancel()
        UIAccessibility.post(
            notification: .announcement,
            argument: String(localized: "Get set. Starting in 3.", locale: environment.appLanguage.locale)
        )
        countdownTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, demo.phase == .countdown else { return }
                if demo.tickCountdown() {
                    detector?.setCountingEnabled(true)
                    HapticManager.trigger(.unlocked)
                    return
                }
            }
        }
    }

    private func countRep(in environment: AppEnvironment) {
        let before = demo.repsDetected
        let completed = demo.countRep()
        // A rep that arrives after the third one changes nothing and must not be reported.
        guard demo.repsDetected > before else { return }
        HapticManager.trigger(.light)
        AudioServicesPlaySystemSound(1104)
        environment.analytics.track(.onboardingPushupsRepDetected.withProperties([
            "rep_number": .int(demo.repsDetected),
            "target_reps": .int(targetReps)
        ]))
        UIAccessibility.post(
            notification: .announcement,
            argument: String(
                localized: "\(demo.repsDetected) of \(targetReps) push-ups",
                locale: environment.appLanguage.locale
            )
        )
        guard completed else { return }
        stopDetecting()
        HapticManager.trigger(.earned)
        environment.analytics.track(.onboardingPushupsDemoCompleted.withProperties([
            "reps_detected": .int(demo.repsDetected),
            "seconds_since_start": .int(secondsSinceStart)
        ]))
        environment.recordOnboardingPushupDemo(demo.outcome)
    }

    private func fail(with error: ExerciseDetectorError, in environment: AppEnvironment) {
        errorMessage = error.localizedDescription
        demo.cameraFailed()
        stopDetecting()
        environment.analytics.track(.onboardingPushupsDemoError.withProperties([
            "reason": .string(String(describing: error)),
            "reps_detected": .int(demo.repsDetected)
        ]))
    }

    private func trackAbandon(reason: OnboardingPushupDemo.ExitReason, in environment: AppEnvironment) {
        environment.analytics.track(.onboardingPushupsDemoAbandoned.withProperties([
            "reason": .string(reason.rawValue),
            "reps_detected": .int(demo.repsDetected),
            "last_cue": .string(troubleCue.analyticsValue),
            "trouble_count": .int(troubleCount),
            "camera_permission_status": .string(Self.permissionStatus.analyticsValue),
            "seconds_since_start": .int(secondsSinceStart)
        ]))
    }

    private var secondsSinceStart: Int {
        guard let startedAt else { return 0 }
        return Int(Date().timeIntervalSince(startedAt).rounded())
    }

    private static var now: TimeInterval { Date().timeIntervalSinceReferenceDate }

    private static var permissionStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// `ready` means the counter sees a full body in a plank — the same signal the real
    /// feature uses to start a set, so the demo behaves like the thing it demonstrates.
    private static func cue(for snapshot: ExerciseDetectionSnapshot) -> FramingCue {
        switch snapshot.status {
        case .poseLost:
            .searching
        case .lowConfidence:
            isDistant(snapshot.framing.bounds) ? .tooFar : .lighting
        case .notInFrame:
            .moveBack
        case .postureInvalid, .waitingForTop, .ready, .lowering, .bottom, .rising:
            .ready
        }
    }

    /// A body that reads as a small smudge is usually too far for the joints to score, not
    /// badly lit. The bounds are normalized, so the diagonal is a distance proxy.
    private static func isDistant(_ bounds: CGRect?) -> Bool {
        guard let bounds else { return false }
        return hypot(bounds.width, bounds.height) < 0.3
    }

    // MARK: - Simulator rehearsal

    /// The Simulator has no camera, so the visual flow is driven by a script: find a body,
    /// count down, then land three reps a second apart. Device builds never run this.
    private func beginRehearsalIfNeeded(in environment: AppEnvironment) {
        #if targetEnvironment(simulator)
        rehearsalTask?.cancel()
        rehearsalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !Task.isCancelled, demo.phase == .framing else { return }
            cue = .ready
            if demo.observed(bodyVisible: true, at: Self.now) { beginCountdown(in: environment) }

            while demo.phase == .countdown {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            for _ in 0..<OnboardingPushupDemo.targetReps {
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled, demo.phase == .counting else { return }
                countRep(in: environment)
            }
        }
        #endif
    }
}

private extension AVAuthorizationStatus {
    var analyticsValue: String {
        switch self {
        case .authorized: "authorized"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "not_determined"
        @unknown default: "unknown"
        }
    }
}
