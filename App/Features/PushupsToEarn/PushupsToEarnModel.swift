import AVFoundation
import AudioToolbox
import EarnDomain
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class PushupsToEarnModel {
    enum Phase: Equatable {
        case loading
        case picker
        case setup
        case starting
        case countdown
        case active
        case claiming
        case pending
        case success
        case dailyCap
        case error
    }

    /// What the athlete has to change before the set can begin. Deliberately coarse: it is
    /// read from across the room, so every case has to survive being reduced to two words.
    enum SetupCue: Equatable {
        case searching
        case tooFar
        case lighting
        case moveBack
        case plank
        case armsExtended
        case holding
    }

    enum FailedOperation: Equatable {
        case load
        case permission
        case start
        case persistCompletion
        case camera
    }

    private(set) var phase = Phase.loading
    private(set) var configuration: ExerciseConfiguration?
    private(set) var challenges: [ExerciseChallenge] = []
    private(set) var selectedChallenge: ExerciseChallenge?
    private(set) var detector: VisionPushupDetector?
    private(set) var snapshot: PushupDetectionSnapshot?
    private(set) var setupCue = SetupCue.searching
    /// How far through the hold that confirms the position, 0...1.
    private(set) var setupHoldProgress: Double = 0
    private(set) var startedAutomatically = true
    private(set) var voiceEnabled = ExerciseVoiceCoach.isEnabled
    private(set) var repetitionCount = 0
    private(set) var countdownValue = 3
    private(set) var rewardSeconds = 0
    private(set) var errorMessage = ""
    private(set) var failedOperation = FailedOperation.load
    private(set) var cameraPermissionDenied = false

    private let voice = ExerciseVoiceCoach()
    private var setupHoldFrames = 0
    private var autoStartRequested = false
    private var pendingClaim: PendingExerciseClaim?
    private var activeStartedAt: Date?
    private var countdownTask: Task<Void, Never>?
    private var opened = false
    private var sessionStarted = false
    private var setupCompleted = false
    private var targetCompleted = false
    private var lastPoseWasDetected: Bool?
    private var isClosed = false

    /// A held push-up position starts the set on its own after this many detector frames
    /// (~12 fps), because the athlete is too far from the phone to reach a button.
    private static let framesToConfirmPosition = 15
    /// The athlete is already in position, so the countdown only has to say "now".
    private static let automaticCountdownSeconds = 3
    /// The manual escape hatch has to leave enough time to walk back and get set.
    static let manualCountdownSeconds = 12

    var targetReps: Int { selectedChallenge?.targetReps ?? pendingClaim?.targetReps ?? 0 }
    var selectedRewardMinutes: Int { (selectedChallenge?.rewardSeconds ?? 0) / 60 }
    var earnedRewardMinutes: Int { rewardSeconds / 60 }
    var setupReady: Bool { setupHoldProgress >= 1 }
    var progress: Double {
        guard targetReps > 0 else { return 0 }
        return min(1, Double(repetitionCount) / Double(targetReps))
    }

    func appeared(in environment: AppEnvironment) async {
        isClosed = false
        if !opened {
            opened = true
            environment.analytics.track(.pushupsToEarnOpened)
        }
        guard phase == .loading else { return }
        await load(in: environment)
    }

    func select(_ challenge: ExerciseChallenge, in environment: AppEnvironment) {
        selectedChallenge = challenge
        environment.analytics.track(.pushupsChallengeSelected.withProperties([
            "target_reps": .int(challenge.targetReps),
            "reward_seconds": .int(challenge.rewardSeconds)
        ]))
    }

    func prepareCamera(in environment: AppEnvironment) async {
        guard let configuration, let selectedChallenge else { return }
        guard selectedChallenge.rewardSeconds <= configuration.rewardSecondsRemaining else {
            showDailyCap(in: environment)
            return
        }
        guard environment.canFitExerciseReward(seconds: selectedChallenge.rewardSeconds) else {
            show(ExerciseAccessError.walletCapacity, operation: .permission)
            return
        }

        do {
            try await requestCameraAccess(in: environment)
            let detector = VisionPushupDetector(thresholds: Self.thresholds(from: configuration.poseThresholds))
            detector.setCountingEnabled(false)
            self.detector = detector
            snapshot = nil
            setupCue = .searching
            setupHoldFrames = 0
            setupHoldProgress = 0
            autoStartRequested = false
            cameraPermissionDenied = false
            phase = .setup
            voice.say(PushupsLocalization.string("pushups.voice.intro"))
        } catch {
            cameraPermissionDenied = Self.isPermissionDenied(error)
            show(error, operation: .permission)
        }
    }

    func received(_ snapshot: PushupDetectionSnapshot, in environment: AppEnvironment) {
        self.snapshot = snapshot
        switch phase {
        case .setup:
            updateSetup(with: snapshot, in: environment)
        case .active:
            trackPoseTransition(for: snapshot, in: environment)
            guard snapshot.didCountRep, snapshot.count > repetitionCount else { return }
            repetitionCount = min(snapshot.count, targetReps)
            environment.analytics.track(.pushupsRepCounted.withProperties([
                "rep_number": .int(repetitionCount),
                "target_reps": .int(targetReps)
            ]))
            HapticManager.trigger(.light)
            AudioServicesPlaySystemSound(1104)
            // A bare number needs no translation and is short enough to keep up with a fast set.
            voice.say("\(repetitionCount)", repeatAfter: 0, interrupting: true)
            UIAccessibility.post(
                notification: .announcement,
                argument: PushupsLocalization.string("pushups.active.rep_announcement \(repetitionCount) \(targetReps)")
            )
            if repetitionCount >= targetReps {
                completeTarget(in: environment)
            }
        default:
            break
        }
    }

    func cameraFailed(_ error: ExerciseDetectorError, in environment: AppEnvironment) {
        detector?.setCountingEnabled(false)
        detector?.stop()
        cameraPermissionDenied = error == .permissionDenied
        if sessionStarted, !targetCompleted {
            environment.analytics.track(.pushupsSessionAbandoned.withProperties([
                "completed_reps": .int(repetitionCount),
                "target_reps": .int(targetReps),
                "reason": .string("camera")
            ]))
            environment.pendingExerciseClaims.clear()
            pendingClaim = nil
            sessionStarted = false
        }
        show(error, operation: .camera)
    }

    /// - Parameter automatic: `true` when the detector saw the athlete hold the top of a
    ///   push-up. The manual path is the escape hatch for a camera that never converges, and
    ///   it buys a long countdown so the athlete can walk back and get set.
    func start(in environment: AppEnvironment, automatic: Bool) async {
        guard phase == .setup, let selectedChallenge, let configuration else { return }
        guard !automatic || setupReady else { return }
        guard environment.canFitExerciseReward(seconds: selectedChallenge.rewardSeconds) else {
            show(ExerciseAccessError.walletCapacity, operation: .start)
            return
        }

        startedAutomatically = automatic
        phase = .starting
        detector?.setCountingEnabled(false)
        if !setupCompleted {
            setupCompleted = true
            environment.analytics.track(.pushupsSetupCompleted.withProperties([
                "target_reps": .int(selectedChallenge.targetReps),
                "automatic": .bool(automatic)
            ]))
        }
        let reusableRecord = pendingClaim.flatMap { record in
            record.stage == .started && record.session == nil
                && record.targetReps == selectedChallenge.targetReps
                && record.detectionVersion == configuration.detectionVersion ? record : nil
        }
        let requestID = reusableRecord?.clientRequestID ?? UUID()
        var record = reusableRecord ?? PendingExerciseClaim(
            clientRequestID: requestID,
            targetReps: selectedChallenge.targetReps,
            detectionVersion: configuration.detectionVersion
        )
        do {
            try environment.pendingExerciseClaims.save(record)
            pendingClaim = record
            let session = try await environment.exercise.start(
                challenge: selectedChallenge,
                detectionVersion: configuration.detectionVersion,
                requestID: requestID
            )
            guard !isClosed else { return }
            guard environment.canFitExerciseReward(seconds: session.rewardSeconds) else {
                throw ExerciseAccessError.walletCapacity
            }
            record.session = session
            try environment.pendingExerciseClaims.save(record)
            pendingClaim = record
            sessionStarted = true
            environment.analytics.track(.pushupsSessionStarted.withProperties([
                "target_reps": .int(session.targetReps),
                "reward_seconds": .int(session.rewardSeconds)
            ]))
            beginCountdown(in: environment)
        } catch {
            if Self.errorCode(error) == "daily_cap_reached" {
                environment.pendingExerciseClaims.clear()
                pendingClaim = nil
                showDailyCap(in: environment)
            } else {
                show(error, operation: .start)
            }
        }
    }

    func retry(in environment: AppEnvironment) async {
        switch failedOperation {
        case .load:
            phase = .loading
            await load(in: environment)
        case .permission, .camera:
            await prepareCamera(in: environment)
        case .start:
            autoStartRequested = false
            setupHoldFrames = 0
            setupHoldProgress = 0
            phase = .setup
        case .persistCompletion:
            persistCompletionAndClaim(in: environment)
        }
    }

    func retryPendingClaim(in environment: AppEnvironment) async {
        guard pendingClaim?.stage == .completed else { return }
        await claimPending(in: environment)
    }

    func doAnother(in environment: AppEnvironment) async {
        resetFlow()
        phase = .loading
        await load(in: environment)
    }

    func close(in environment: AppEnvironment) {
        isClosed = true
        voice.stop()
        countdownTask?.cancel()
        countdownTask = nil
        detector?.setCountingEnabled(false)
        detector?.stop()
        detector = nil

        guard sessionStarted, !targetCompleted else { return }
        environment.analytics.track(.pushupsSessionAbandoned.withProperties([
            "completed_reps": .int(repetitionCount),
            "target_reps": .int(targetReps),
            "reason": .string("dismissed")
        ]))
        environment.pendingExerciseClaims.clear()
        pendingClaim = nil
        sessionStarted = false
    }

    private func load(in environment: AppEnvironment) async {
        do {
            let existing = try environment.pendingExerciseClaims.load()
            if existing?.stage == .started {
                environment.analytics.track(.pushupsSessionAbandoned.withProperties([
                    "completed_reps": .int(existing?.completedReps ?? 0),
                    "target_reps": .int(existing?.targetReps ?? 0),
                    "reason": .string("interrupted")
                ]))
                environment.pendingExerciseClaims.clear()
            } else {
                pendingClaim = existing
            }

            let configuration = try await environment.prepareExerciseConfiguration()
            guard !isClosed else { return }
            self.configuration = configuration

            if pendingClaim?.stage == .completed {
                await claimPending(in: environment)
                return
            }

            challenges = configuration.challenges
                .filter { [5, 10, 20].contains($0.targetReps) }
                .sorted { $0.targetReps < $1.targetReps }
            guard !challenges.isEmpty else {
                throw ExerciseAccessError.disabled
            }
            if !challenges.contains(where: { $0.rewardSeconds <= configuration.rewardSecondsRemaining }) {
                showDailyCap(in: environment)
                return
            }
            selectedChallenge = challenges.first { $0.rewardSeconds <= configuration.rewardSecondsRemaining }
            phase = .picker
        } catch {
            show(error, operation: .load)
        }
    }

    private func requestCameraAccess(in environment: AppEnvironment) async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            environment.analytics.track(.pushupsCameraPermissionRequested)
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                throw ExerciseDetectorError.permissionDenied
            }
            environment.analytics.track(.pushupsCameraPermissionGranted)
        case .denied, .restricted:
            throw ExerciseDetectorError.permissionDenied
        @unknown default:
            throw ExerciseDetectorError.cameraUnavailable
        }
    }

    private func beginCountdown(in environment: AppEnvironment) {
        countdownTask?.cancel()
        let seconds = startedAutomatically ? Self.automaticCountdownSeconds : Self.manualCountdownSeconds
        countdownValue = seconds
        repetitionCount = 0
        lastPoseWasDetected = nil
        phase = .countdown
        voice.say(
            startedAutomatically
                ? PushupsLocalization.string("pushups.voice.countdown.auto")
                : PushupsLocalization.string("pushups.voice.countdown.manual \(seconds)"),
            repeatAfter: 0,
            interrupting: true
        )
        UIAccessibility.post(
            notification: .announcement,
            argument: PushupsLocalization.string("pushups.countdown.started")
        )
        countdownTask = Task { [weak self] in
            guard let self else { return }
            for value in stride(from: seconds, through: 1, by: -1) {
                countdownValue = value
                announceCountdown(value)
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }
            activeStartedAt = Date()
            detector?.setCountingEnabled(true)
            phase = .active
            voice.say(
                PushupsLocalization.string("pushups.voice.go"),
                repeatAfter: 0,
                interrupting: true
            )
            HapticManager.trigger(.unlocked)
            UIAccessibility.post(
                notification: .announcement,
                argument: PushupsLocalization.string("pushups.active.started")
            )
        }
    }

    /// The last three seconds are spoken; everything before that only ticks, so a long
    /// manual countdown does not talk over the athlete getting into position.
    private func announceCountdown(_ value: Int) {
        if value <= 3 {
            voice.say("\(value)", repeatAfter: 0, interrupting: true)
        } else {
            voice.tick()
        }
    }

    private func completeTarget(in environment: AppEnvironment) {
        guard !targetCompleted else { return }
        targetCompleted = true
        detector?.setCountingEnabled(false)
        voice.say(PushupsLocalization.string("pushups.voice.done"), repeatAfter: 0, interrupting: true)
        let duration = max(0, Date().timeIntervalSince(activeStartedAt ?? Date()))
        environment.analytics.track(.pushupsSessionCompleted.withProperties([
            "target_reps": .int(targetReps),
            "duration_seconds": .int(Int(duration.rounded()))
        ]))
        guard var record = pendingClaim else {
            show(ExerciseAccessError.invalidReward, operation: .persistCompletion)
            return
        }
        record.markCompleted(completedReps: repetitionCount, durationSeconds: duration, completedAt: Date())
        pendingClaim = record
        persistCompletionAndClaim(in: environment)
    }

    private func persistCompletionAndClaim(in environment: AppEnvironment) {
        guard let pendingClaim else { return }
        do {
            try environment.pendingExerciseClaims.save(pendingClaim)
            Task { [weak self] in
                await self?.claimPending(in: environment)
            }
        } catch {
            show(error, operation: .persistCompletion)
        }
    }

    private func claimPending(in environment: AppEnvironment) async {
        guard let record = pendingClaim,
              let session = record.session,
              let completedReps = record.completedReps,
              let durationSeconds = record.durationSeconds,
              let completedAt = record.completedAt else {
            environment.pendingExerciseClaims.clear()
            pendingClaim = nil
            show(ExerciseAccessError.invalidReward, operation: .load)
            return
        }
        phase = .claiming
        do {
            let reward = try await environment.exercise.claim(
                sessionID: session.id,
                completedReps: completedReps,
                durationSeconds: durationSeconds,
                completedAt: completedAt,
                detectionVersion: record.detectionVersion
            )
            guard !isClosed else { return }
            _ = try environment.applyExerciseReward(reward)
            rewardSeconds = reward.amountSeconds
            environment.pendingExerciseClaims.clear()
            pendingClaim = nil
            phase = .success
            UIAccessibility.post(
                notification: .announcement,
                argument: PushupsLocalization.string("pushups.success.announcement \(reward.amountSeconds / 60)")
            )
        } catch {
            let code = Self.errorCode(error)
            if code == "daily_cap_reached" {
                rejectPending(error, in: environment)
                showDailyCap(in: environment)
            } else if Self.isTerminalClaimCode(code) {
                rejectPending(error, in: environment)
                show(error, operation: .load)
            } else if error is ExerciseAccessError {
                show(error, operation: .persistCompletion)
            } else {
                errorMessage = error.localizedDescription
                phase = .pending
            }
        }
    }

    private func rejectPending(_ error: Error, in environment: AppEnvironment) {
        environment.analytics.track(.pushupsRewardRejected.withProperties([
            "reason": .string(Self.errorCode(error) ?? "unknown")
        ]))
        environment.pendingExerciseClaims.clear()
        pendingClaim = nil
    }

    private func showDailyCap(in environment: AppEnvironment) {
        if phase != .dailyCap {
            environment.analytics.track(.pushupsDailyCapReached)
        }
        phase = .dailyCap
    }

    func toggleVoice() {
        voiceEnabled.toggle()
        ExerciseVoiceCoach.isEnabled = voiceEnabled
        if voiceEnabled {
            voice.say(PushupsLocalization.string(Self.voiceKey(for: setupCue)), repeatAfter: 0)
        } else {
            voice.stop()
        }
    }

    /// The setup screen is the one the athlete cannot reach: they are in a plank two metres
    /// from the phone. So the position itself is the trigger — hold the top of a push-up for
    /// about a second and the countdown starts on its own.
    private func updateSetup(with snapshot: PushupDetectionSnapshot, in environment: AppEnvironment) {
        let cue = Self.cue(for: snapshot)
        if cue != setupCue {
            setupCue = cue
            if cue == .holding { HapticManager.trigger(.light) }
        }
        voice.say(PushupsLocalization.string(Self.voiceKey(for: cue)))

        // A frame the detector drops, or an elbow angle sitting on the threshold, should not
        // undo a second of good position — so the hold decays instead of resetting.
        setupHoldFrames = cue == .holding
            ? setupHoldFrames + 1
            : max(0, setupHoldFrames - 3)
        setupHoldProgress = min(1, Double(setupHoldFrames) / Double(Self.framesToConfirmPosition))

        guard setupReady, !autoStartRequested else { return }
        autoStartRequested = true
        Task { [weak self] in
            await self?.start(in: environment, automatic: true)
        }
    }

    /// `ready` means the counter sees a full body, a valid plank and extended arms — the top
    /// of a push-up. That is a far better "I am set" signal than a body merely being in frame,
    /// which a standing athlete also satisfies.
    private static func cue(for snapshot: PushupDetectionSnapshot) -> SetupCue {
        switch snapshot.status {
        case .poseLost:
            .searching
        case .lowConfidence:
            isDistant(snapshot.framing.bounds) ? .tooFar : .lighting
        case .notInFrame:
            .moveBack
        case .plankInvalid:
            .plank
        case .waitingForTop:
            .armsExtended
        case .ready, .lowering, .bottom, .rising:
            .holding
        }
    }

    /// A body that reads as a small smudge is usually too far for the joints to score, not
    /// badly lit. The bounds are normalized, so the diagonal is a distance proxy.
    private static func isDistant(_ bounds: CGRect?) -> Bool {
        guard let bounds else { return false }
        return hypot(bounds.width, bounds.height) < 0.3
    }

    private static func voiceKey(for cue: SetupCue) -> String.LocalizationValue {
        switch cue {
        case .searching: "pushups.voice.searching"
        case .tooFar: "pushups.voice.too_far"
        case .lighting: "pushups.voice.lighting"
        case .moveBack: "pushups.voice.move_back"
        case .plank: "pushups.voice.plank"
        case .armsExtended: "pushups.voice.arms_extended"
        case .holding: "pushups.voice.holding"
        }
    }

    private func trackPoseTransition(for snapshot: PushupDetectionSnapshot, in environment: AppEnvironment) {
        let detected: Bool
        switch snapshot.status {
        case .poseLost, .lowConfidence, .notInFrame:
            detected = false
        default:
            detected = true
        }
        guard detected != lastPoseWasDetected else { return }
        lastPoseWasDetected = detected
        environment.analytics.track(detected ? .pushupsPoseDetected : .pushupsPoseLost)
    }

    private func show(_ error: Error, operation: FailedOperation) {
        errorMessage = error.localizedDescription
        failedOperation = operation
        phase = .error
    }

    private func resetFlow() {
        countdownTask?.cancel()
        detector?.setCountingEnabled(false)
        detector?.stop()
        detector = nil
        voice.stop()
        snapshot = nil
        configuration = nil
        challenges = []
        selectedChallenge = nil
        pendingClaim = nil
        activeStartedAt = nil
        setupCue = .searching
        setupHoldFrames = 0
        setupHoldProgress = 0
        autoStartRequested = false
        startedAutomatically = true
        repetitionCount = 0
        countdownValue = 3
        rewardSeconds = 0
        errorMessage = ""
        cameraPermissionDenied = false
        sessionStarted = false
        setupCompleted = false
        targetCompleted = false
        lastPoseWasDetected = nil
        isClosed = false
    }

    private static func thresholds(from remote: ExercisePoseThresholds) -> PushupPoseThresholds {
        var thresholds = PushupPoseThresholds()
        thresholds.minimumJointConfidence = remote.minimumConfidence
        thresholds.bottomEnterAngleDegrees = remote.downElbowAngleDegrees
        thresholds.topEnterAngleDegrees = remote.upElbowAngleDegrees
        thresholds.minimumPlankAngleDegrees = remote.minimumBodyAngleDegrees
        thresholds.minimumRepDuration = remote.minimumRepDurationSeconds
        // Head-on, joints score lower and the elbow travel the lens sees is roughly
        // half of the real range, so the selfie limits are derived from the same
        // server tuning instead of being hard-coded beside it.
        thresholds.frontMinimumJointConfidence = max(0.2, remote.minimumConfidence * 0.55)
        thresholds.frontTopElbowAngleDegrees = max(90, remote.upElbowAngleDegrees - 30)
        thresholds.frontElbowDropDegrees = max(
            20,
            (remote.upElbowAngleDegrees - remote.downElbowAngleDegrees) * 0.5
        )
        return thresholds
    }

    private static func errorCode(_ error: Error) -> String? {
        (error as? ExerciseServiceError)?.code
    }

    private static func isPermissionDenied(_ error: Error) -> Bool {
        (error as? ExerciseDetectorError) == .permissionDenied
    }

    private static func isTerminalClaimCode(_ code: String?) -> Bool {
        guard let code else { return false }
        return [
            "challenge_incomplete", "invalid_duration", "detection_version_mismatch",
            "invalid_completion_time",
            "session_not_found", "session_inactive", "session_expired", "entitlement_required",
            "update_required", "pushups_disabled"
        ].contains(code)
    }
}
