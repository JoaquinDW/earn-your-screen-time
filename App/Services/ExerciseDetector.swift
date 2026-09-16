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

struct PushupDetectionSnapshot: Equatable, Sendable {
    let count: Int
    let status: PushupRepCounter.Status
    let guidance: PushupRepCounter.Guidance
    let framing: PoseFraming
    let didCountRep: Bool
    let viewMode: PushupViewMode?
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

final class VisionPushupDetector: NSObject, ExerciseDetector, @unchecked Sendable {
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

    private var counter = PushupRepCounter()
    private var configured = false
    private var rotationAngle: CGFloat = VisionPushupDetector.portraitRotationAngle
    private var orientationIndex = 0
    private var undetectedFrameStreak = 0
    private var wantsToRun = false
    private var requestInFlight = false
    private var lastProcessedTimestamp = -Double.infinity
    private var reportedProcessingFailure = false
    private var countingEnabled = false
    private var notificationTokens: [NSObjectProtocol] = []

    @MainActor private var snapshotHandler: (@MainActor @Sendable (PushupDetectionSnapshot) -> Void)?
    @MainActor private var errorHandler: (@MainActor @Sendable (ExerciseDetectorError) -> Void)?

    init(thresholds: PushupPoseThresholds = PushupPoseThresholds()) {
        counter = PushupRepCounter(thresholds: thresholds)
        super.init()
    }

    @MainActor
    func start(
        onSnapshot: @escaping @MainActor @Sendable (PushupDetectionSnapshot) -> Void,
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
        onSnapshot: @escaping @MainActor @Sendable (PushupDetectionSnapshot) -> Void,
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

    private func emit(snapshot: PushupDetectionSnapshot) {
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

extension VisionPushupDetector: AVCaptureVideoDataOutputSampleBufferDelegate {
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
            let output = counter.process(pose)
            emit(snapshot: PushupDetectionSnapshot(
                count: output.repetitionCount,
                status: output.status,
                guidance: output.guidance,
                framing: makeFraming(points: pose.points, output: output),
                didCountRep: output.didCountRep,
                viewMode: output.viewMode
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
            (.leftAnkle, .leftAnkle),
            (.rightShoulder, .rightShoulder),
            (.rightElbow, .rightElbow),
            (.rightWrist, .rightWrist),
            (.rightHip, .rightHip),
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
        output: PushupRepCounter.Output
    ) -> PoseFraming {
        let visiblePoints: [BodyPosePoint]
        if output.viewMode == .front {
            // Selfie framing tracks the upper body; legs trail away from the lens.
            visiblePoints = Array(points.values)
        } else if let side = output.trackedSide {
            let sideJoints: [BodyJoint] = side == .left
                ? [.leftShoulder, .leftElbow, .leftWrist, .leftHip, .leftAnkle]
                : [.rightShoulder, .rightElbow, .rightWrist, .rightHip, .rightAnkle]
            visiblePoints = sideJoints.compactMap { points[$0] }
        } else {
            visiblePoints = Array(points.values)
        }

        guard !visiblePoints.isEmpty else {
            return PoseFraming(bounds: nil, state: .noBody, mode: output.viewMode)
        }
        let minX = visiblePoints.map(\.x).min() ?? 0
        let maxX = visiblePoints.map(\.x).max() ?? 0
        let minY = visiblePoints.map(\.y).min() ?? 0
        let maxY = visiblePoints.map(\.y).max() ?? 0
        let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let state: PoseFraming.State
        switch output.status {
        case .poseLost, .notInFrame:
            state = .partiallyVisible
        default:
            state = .fullyVisible
        }
        return PoseFraming(bounds: bounds, state: state, mode: output.viewMode)
    }
}
