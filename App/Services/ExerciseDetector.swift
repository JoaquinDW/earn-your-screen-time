import AVFoundation
import EarnDomain
import Foundation
import ImageIO
import Vision

protocol ExerciseDetector: AnyObject {
    associatedtype Snapshot: Sendable

    @MainActor
    func start(
        onSnapshot: @escaping @MainActor @Sendable (Snapshot) -> Void,
        onError: @escaping @MainActor @Sendable (ExerciseDetectorError) -> Void
    )

    @MainActor func stop()
}

enum ExerciseDetectorError: LocalizedError, Sendable {
    case permissionDenied
    case cameraUnavailable
    case configurationFailed
    case interrupted
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Allow camera access in Settings to count exercises."
        case .cameraUnavailable:
            "The front camera is not available on this device."
        case .configurationFailed:
            "Earnit could not start the exercise camera."
        case .interrupted:
            "The camera was interrupted. Exercise detection is paused."
        case .processingFailed:
            "Earnit could not analyze the camera image."
        }
    }
}

struct PoseFraming: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case noBody
        case partiallyVisible
        case fullyVisible
    }

    /// Vision-normalized coordinates with a lower-left origin.
    let bounds: CGRect?
    let state: State
    let mode: PushupViewMode?
}

/// One analyzed camera frame, in terms every exercise shares.
struct ExerciseDetectionSnapshot: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case poseLost
        case lowConfidence
        case notInFrame
        /// Visible but not in the exercise's position at all: kneeling instead of a plank,
        /// lying down instead of standing.
        case postureInvalid
        case waitingForTop
        case ready
        case lowering
        case bottom
        case rising
    }

    enum Guidance: Equatable, Sendable {
        case findBody
        case improveLighting
        case moveIntoFrame
        case fixPosture
        case startAtTop
        case goDown
        case comeUp
        case slowDown
        case none
    }

    let count: Int
    let status: Status
    let guidance: Guidance
    let framing: PoseFraming
    let didCountRep: Bool
    let viewMode: PushupViewMode?
}

/// The domain rep counters behind one interface, so the camera pipeline is the same for every
/// exercise.
enum ExerciseRepCounter: Sendable {
    case pushup(PushupRepCounter)
    case squat(SquatRepCounter)

    struct Reading: Sendable {
        let count: Int
        let didCountRep: Bool
        let status: ExerciseDetectionSnapshot.Status
        let guidance: ExerciseDetectionSnapshot.Guidance
        let viewMode: PushupViewMode?
        /// The joints the counter judged, which is what the framing should be measured on.
        let trackedJoints: [BodyJoint]?
    }

    mutating func reset() {
        switch self {
        case var .pushup(counter):
            counter.reset()
            self = .pushup(counter)
        case var .squat(counter):
            counter.reset()
            self = .squat(counter)
        }
    }

    mutating func process(_ pose: BodyPose) -> Reading {
        switch self {
        case var .pushup(counter):
            let output = counter.process(pose)
            self = .pushup(counter)
            return Reading(
                count: output.repetitionCount,
                didCountRep: output.didCountRep,
                status: Self.status(output.status),
                guidance: Self.guidance(output.guidance),
                viewMode: output.viewMode,
                trackedJoints: Self.pushupJoints(output)
            )
        case var .squat(counter):
            let output = counter.process(pose)
            self = .squat(counter)
            return Reading(
                count: output.repetitionCount,
                didCountRep: output.didCountRep,
                status: Self.status(output.status),
                guidance: Self.guidance(output.guidance),
                viewMode: nil,
                trackedJoints: nil
            )
        }
    }

    /// In profile only the near side is tracked; selfie framing tracks the whole upper body.
    private static func pushupJoints(_ output: PushupRepCounter.Output) -> [BodyJoint]? {
        guard output.viewMode != .front, let side = output.trackedSide else { return nil }
        return side == .left
            ? [.leftShoulder, .leftElbow, .leftWrist, .leftHip, .leftAnkle]
            : [.rightShoulder, .rightElbow, .rightWrist, .rightHip, .rightAnkle]
    }

    private static func status(_ status: PushupRepCounter.Status) -> ExerciseDetectionSnapshot.Status {
        switch status {
        case .poseLost: .poseLost
        case .lowConfidence: .lowConfidence
        case .notInFrame: .notInFrame
        case .plankInvalid: .postureInvalid
        case .waitingForTop: .waitingForTop
        case .ready: .ready
        case .lowering: .lowering
        case .bottom: .bottom
        case .rising: .rising
        }
    }

    private static func status(_ status: SquatRepCounter.Status) -> ExerciseDetectionSnapshot.Status {
        switch status {
        case .poseLost: .poseLost
        case .lowConfidence: .lowConfidence
        case .notInFrame: .notInFrame
        case .notUpright: .postureInvalid
        case .waitingForTop: .waitingForTop
        case .ready: .ready
        case .lowering: .lowering
        case .bottom: .bottom
        case .rising: .rising
        }
    }

    private static func guidance(_ guidance: PushupRepCounter.Guidance) -> ExerciseDetectionSnapshot.Guidance {
        switch guidance {
        case .findBody: .findBody
        case .improveLighting: .improveLighting
        case .moveIntoFrame: .moveIntoFrame
        case .straightenBody: .fixPosture
        case .startAtTop: .startAtTop
        case .lowerBody: .goDown
        case .pushUp: .comeUp
        case .slowDown: .slowDown
        case .none: .none
        }
    }

    private static func guidance(_ guidance: SquatRepCounter.Guidance) -> ExerciseDetectionSnapshot.Guidance {
        switch guidance {
        case .findBody: .findBody
        case .improveLighting: .improveLighting
        case .moveIntoFrame: .moveIntoFrame
        case .standUpright: .fixPosture
        case .startStanding: .startAtTop
        case .lowerHips: .goDown
        case .standUp: .comeUp
        case .slowDown: .slowDown
        case .none: .none
        }
    }
}

@MainActor
final class MockExerciseDetector<Snapshot: Sendable>: ExerciseDetector {
    private var onSnapshot: (@MainActor @Sendable (Snapshot) -> Void)?
    private var onError: (@MainActor @Sendable (ExerciseDetectorError) -> Void)?
    private var initialSnapshots: [Snapshot]

    init(snapshots: [Snapshot] = []) {
        initialSnapshots = snapshots
    }

    func start(
        onSnapshot: @escaping @MainActor @Sendable (Snapshot) -> Void,
        onError: @escaping @MainActor @Sendable (ExerciseDetectorError) -> Void
    ) {
        self.onSnapshot = onSnapshot
        self.onError = onError
        for snapshot in initialSnapshots {
            onSnapshot(snapshot)
        }
        initialSnapshots.removeAll()
    }

    func stop() {
        onSnapshot = nil
        onError = nil
    }

    func emit(_ snapshot: Snapshot) {
        onSnapshot?(snapshot)
    }

    func fail(with error: ExerciseDetectorError) {
        onError?(error)
    }
}

final class VisionExerciseDetector: NSObject, ExerciseDetector, @unchecked Sendable {
    static let portraitRotationAngle: CGFloat = 90

    /// Fallbacks for a phone propped at an angle the interface orientation cannot describe,
    /// such as lying flat on the floor.
    private static let orientationCandidates: [CGImagePropertyOrientation] = [.up, .right, .left, .down]
    private static let orientationSearchStreak = 10

    let captureSession = AVCaptureSession()

    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.earnit.pushups.camera-session")
    private let processingQueue = DispatchQueue(label: "com.earnit.pushups.vision", qos: .userInitiated)
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private let frameInterval = 1.0 / 12.0

    private var counter: ExerciseRepCounter
    private var configured = false
    private var rotationAngle: CGFloat = VisionExerciseDetector.portraitRotationAngle
    private var orientationIndex = 0
    private var undetectedFrameStreak = 0
    private var wantsToRun = false
    private var requestInFlight = false
    private var lastProcessedTimestamp = -Double.infinity
    private var reportedProcessingFailure = false
    private var countingEnabled = false
    private var notificationTokens: [NSObjectProtocol] = []

    @MainActor private var snapshotHandler: (@MainActor @Sendable (ExerciseDetectionSnapshot) -> Void)?
    @MainActor private var errorHandler: (@MainActor @Sendable (ExerciseDetectorError) -> Void)?

    init(counter: ExerciseRepCounter = .pushup(PushupRepCounter())) {
        self.counter = counter
        super.init()
    }

    @MainActor
    func start(
        onSnapshot: @escaping @MainActor @Sendable (ExerciseDetectionSnapshot) -> Void,
        onError: @escaping @MainActor @Sendable (ExerciseDetectorError) -> Void
    ) {
        snapshotHandler = onSnapshot
        errorHandler = onError

        sessionQueue.async { [weak self] in
            guard let self else { return }
            wantsToRun = true
            authorizeAndStart()
        }
    }

    @MainActor
    func stop() {
        snapshotHandler = nil
        errorHandler = nil
        sessionQueue.async { [self] in
            wantsToRun = false
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    @MainActor
    func updateHandlers(
        onSnapshot: @escaping @MainActor @Sendable (ExerciseDetectionSnapshot) -> Void,
        onError: @escaping @MainActor @Sendable (ExerciseDetectorError) -> Void
    ) {
        snapshotHandler = onSnapshot
        errorHandler = onError
    }

    @MainActor
    func setCountingEnabled(_ enabled: Bool) {
        processingQueue.async { [weak self] in
            guard let self else { return }
            countingEnabled = enabled
            counter.reset()
        }
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    private func authorizeAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                sessionQueue.async {
                    if granted {
                        self.configureAndStart()
                    } else {
                        self.emit(error: .permissionDenied)
                    }
                }
            }
        case .denied, .restricted:
            emit(error: .permissionDenied)
        @unknown default:
            emit(error: .cameraUnavailable)
        }
    }

    private func configureAndStart() {
        guard wantsToRun else { return }

        do {
            if !configured {
                try configureSession()
                observeSession()
                configured = true
            }
            if !captureSession.isRunning {
                captureSession.startRunning()
            }
        } catch let error as ExerciseDetectorError {
            emit(error: error)
        } catch {
            emit(error: .configurationFailed)
        }
    }

    private func configureSession() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        captureSession.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw ExerciseDetectorError.cameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input), captureSession.canAddOutput(videoOutput) else {
            throw ExerciseDetectorError.configurationFailed
        }

        captureSession.addInput(input)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        captureSession.addOutput(videoOutput)

        applyRotationAngle()
    }

    /// Vision needs an upright person, so the sensor-native landscape buffer is
    /// rotated to match the interface before any pose request runs.
    private func applyRotationAngle() {
        guard let connection = videoOutput.connection(with: .video),
              connection.isVideoRotationAngleSupported(rotationAngle) else { return }
        connection.videoRotationAngle = rotationAngle
    }

    @MainActor
    func setRotationAngle(_ angle: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, rotationAngle != angle else { return }
            rotationAngle = angle
            applyRotationAngle()
            // The buffer arrives a different way up, so restart the orientation search.
            processingQueue.async { [weak self] in
                self?.orientationIndex = 0
                self?.undetectedFrameStreak = 0
            }
        }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: captureSession,
                queue: nil
            ) { [weak self] _ in
                self?.emit(error: .interrupted)
            },
            center.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification,
                object: captureSession,
                queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                sessionQueue.async { self.configureAndStart() }
            },
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: captureSession,
                queue: nil
            ) { [weak self] notification in
                guard let self else { return }
                let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
                sessionQueue.async {
                    if error?.code == .mediaServicesWereReset {
                        self.configureAndStart()
                    } else {
                        self.emit(error: .configurationFailed)
                    }
                }
            }
        ]
    }

    private func emit(snapshot: ExerciseDetectionSnapshot) {
        Task { @MainActor [weak self] in
            self?.snapshotHandler?(snapshot)
        }
    }

    private func emit(error: ExerciseDetectorError) {
        Task { @MainActor [weak self] in
            self?.errorHandler?(error)
        }
    }
}

extension VisionExerciseDetector: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let timestamp = sampleBuffer.presentationTimeStamp.seconds
        guard timestamp.isFinite,
              timestamp - lastProcessedTimestamp >= frameInterval,
              !requestInFlight else { return }

        lastProcessedTimestamp = timestamp
        requestInFlight = true
        defer { requestInFlight = false }

        do {
            let handler = VNImageRequestHandler(
                cmSampleBuffer: sampleBuffer,
                orientation: Self.orientationCandidates[orientationIndex],
                options: [:]
            )
            try handler.perform([poseRequest])
            reportedProcessingFailure = false

            let observation = poseRequest.results?.first
            searchOrientationIfNeeded(detected: observation != nil)
            let pose = makeBodyPose(from: observation, timestamp: timestamp)
            if !countingEnabled { counter.reset() }
            let reading = counter.process(pose)
            emit(snapshot: ExerciseDetectionSnapshot(
                count: reading.count,
                status: reading.status,
                guidance: reading.guidance,
                framing: makeFraming(points: pose.points, reading: reading),
                didCountRep: reading.didCountRep,
                viewMode: reading.viewMode
            ))
        } catch {
            if !reportedProcessingFailure {
                reportedProcessingFailure = true
                emit(error: .processingFailed)
            }
        }
        // The sample buffer is neither stored nor captured by asynchronous work.
    }

    /// A phone propped against a wall or lying on the floor can present the athlete
    /// sideways. When no body shows up for a while, try the next image orientation.
    private func searchOrientationIfNeeded(detected: Bool) {
        guard !detected else {
            undetectedFrameStreak = 0
            return
        }
        undetectedFrameStreak += 1
        guard undetectedFrameStreak >= Self.orientationSearchStreak else { return }
        undetectedFrameStreak = 0
        orientationIndex = (orientationIndex + 1) % Self.orientationCandidates.count
    }

    private func makeBodyPose(
        from observation: VNHumanBodyPoseObservation?,
        timestamp: TimeInterval
    ) -> BodyPose {
        guard let observation else {
            return BodyPose(timestamp: timestamp, points: [:])
        }

        let joints: [(BodyJoint, VNHumanBodyPoseObservation.JointName)] = [
            (.leftShoulder, .leftShoulder),
            (.leftElbow, .leftElbow),
            (.leftWrist, .leftWrist),
            (.leftHip, .leftHip),
            (.leftKnee, .leftKnee),
            (.leftAnkle, .leftAnkle),
            (.rightShoulder, .rightShoulder),
            (.rightElbow, .rightElbow),
            (.rightWrist, .rightWrist),
            (.rightHip, .rightHip),
            (.rightKnee, .rightKnee),
            (.rightAnkle, .rightAnkle)
        ]

        var points: [BodyJoint: BodyPosePoint] = [:]
        for (bodyJoint, visionJoint) in joints {
            guard let point = try? observation.recognizedPoint(visionJoint) else { continue }
            points[bodyJoint] = BodyPosePoint(
                x: point.location.x,
                y: point.location.y,
                confidence: Double(point.confidence)
            )
        }
        return BodyPose(timestamp: timestamp, points: points)
    }

    private func makeFraming(
        points: [BodyJoint: BodyPosePoint],
        reading: ExerciseRepCounter.Reading
    ) -> PoseFraming {
        let visiblePoints = reading.trackedJoints.map { joints in joints.compactMap { points[$0] } }
            ?? Array(points.values)

        guard !visiblePoints.isEmpty else {
            return PoseFraming(bounds: nil, state: .noBody, mode: reading.viewMode)
        }
        let minX = visiblePoints.map(\.x).min() ?? 0
        let maxX = visiblePoints.map(\.x).max() ?? 0
        let minY = visiblePoints.map(\.y).min() ?? 0
        let maxY = visiblePoints.map(\.y).max() ?? 0
        let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let state: PoseFraming.State
        switch reading.status {
        case .poseLost, .notInFrame:
            state = .partiallyVisible
        default:
            state = .fullyVisible
        }
        return PoseFraming(bounds: bounds, state: state, mode: reading.viewMode)
    }
}
