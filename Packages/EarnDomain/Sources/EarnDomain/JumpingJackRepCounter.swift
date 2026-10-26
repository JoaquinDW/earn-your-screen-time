import Foundation

public struct JumpingJackPoseThresholds: Codable, Equatable, Sendable {
    public var minimumJointConfidence: Double
    public var frameMargin: Double
    /// Shoulder width over torso height below which the athlete is side-on, not facing the lens.
    public var minimumFacingRatio: Double
    /// How far above the shoulders, in torso heights, both wrists must reach to count as up.
    public var armsUpMargin: Double
    /// How far below the shoulders, in torso heights, both wrists must hang to count as down.
    public var armsDownMargin: Double
    /// Ankle spread over shoulder width that counts as feet apart, and as feet together.
    public var feetApartRatio: Double
    public var feetTogetherRatio: Double
    public var minimumRepDuration: TimeInterval
    public var repDebounceDuration: TimeInterval
    public var poseLossResetDuration: TimeInterval

    public init(
        minimumJointConfidence: Double = 0.4,
        frameMargin: Double = 0.01,
        minimumFacingRatio: Double = 0.25,
        armsUpMargin: Double = 0.05,
        armsDownMargin: Double = 0.15,
        feetApartRatio: Double = 1.3,
        feetTogetherRatio: Double = 0.95,
        minimumRepDuration: TimeInterval = 0.4,
        repDebounceDuration: TimeInterval = 0.2,
        poseLossResetDuration: TimeInterval = 0.75
    ) {
        self.minimumJointConfidence = minimumJointConfidence
        self.frameMargin = frameMargin
        self.minimumFacingRatio = minimumFacingRatio
        self.armsUpMargin = armsUpMargin
        self.armsDownMargin = armsDownMargin
        self.feetApartRatio = feetApartRatio
        self.feetTogetherRatio = feetTogetherRatio
        self.minimumRepDuration = minimumRepDuration
        self.repDebounceDuration = repDebounceDuration
        self.poseLossResetDuration = poseLossResetDuration
    }
}

/// Counts jumping jacks facing the lens: closed (arms down, feet together) → open (wrists above
/// the shoulders, feet wider than the shoulders) → closed is one repetition.
///
/// Both halves are required, so waving the arms while standing still counts nothing. Arm height
/// is measured in torso heights and foot spread in shoulder widths, which keeps the counter
/// independent of how far away the phone is.
public struct JumpingJackRepCounter: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case poseLost
        case lowConfidence
        case notInFrame
        case notFacing
        case waitingForStart
        case ready
        case opening
        case open
        case closing
    }

    public enum Guidance: String, Equatable, Sendable {
        case findBody
        case improveLighting
        case moveIntoFrame
        case faceCamera
        case startClosed
        case jumpOut
        case jumpIn
        case slowDown
        case none
    }

    public struct Output: Equatable, Sendable {
        public let repetitionCount: Int
        public let didCountRep: Bool
        public let status: Status
        public let guidance: Guidance
    }

    private enum Phase: Equatable, Sendable {
        case waitingForStart
        case closed
        case open
    }

    private static let joints: [BodyJoint] = [
        .leftShoulder, .rightShoulder, .leftWrist, .rightWrist,
        .leftHip, .rightHip, .leftAnkle, .rightAnkle
    ]

    public let thresholds: JumpingJackPoseThresholds
    public private(set) var repetitionCount: Int
    private var phase: Phase = .waitingForStart
    private var cycleStartedAt: TimeInterval?
    private var lastRepAt: TimeInterval?
    private var poseLostAt: TimeInterval?

    public init(thresholds: JumpingJackPoseThresholds = JumpingJackPoseThresholds(), repetitionCount: Int = 0) {
        self.thresholds = thresholds
        self.repetitionCount = max(0, repetitionCount)
    }

    public mutating func reset(repetitionCount: Int = 0) {
        self.repetitionCount = max(0, repetitionCount)
        resetCycle()
        lastRepAt = nil
        poseLostAt = nil
    }

    public mutating func process(_ pose: BodyPose) -> Output {
        let points = Self.joints.compactMap { pose[$0] }
        guard points.count == Self.joints.count,
              let leftShoulder = pose[.leftShoulder], let rightShoulder = pose[.rightShoulder],
              let leftWrist = pose[.leftWrist], let rightWrist = pose[.rightWrist],
              let leftHip = pose[.leftHip], let rightHip = pose[.rightHip],
              let leftAnkle = pose[.leftAnkle], let rightAnkle = pose[.rightAnkle] else {
            return invalidPose(at: pose.timestamp, status: .poseLost, guidance: .findBody)
        }
        guard points.allSatisfy({ $0.confidence >= thresholds.minimumJointConfidence }) else {
            return invalidPose(at: pose.timestamp, status: .lowConfidence, guidance: .improveLighting)
        }
        guard points.allSatisfy(inFrame) else {
            return invalidPose(at: pose.timestamp, status: .notInFrame, guidance: .moveIntoFrame)
        }

        let shoulderY = (leftShoulder.y + rightShoulder.y) / 2
        let torso = shoulderY - (leftHip.y + rightHip.y) / 2
        let shoulderWidth = abs(leftShoulder.x - rightShoulder.x)
        guard torso > 0, shoulderWidth / torso >= thresholds.minimumFacingRatio else {
            return invalidPose(at: pose.timestamp, status: .notFacing, guidance: .faceCamera)
        }

        recoverIfNeeded(at: pose.timestamp)
        poseLostAt = nil

        let lowerWrist = min(leftWrist.y, rightWrist.y)
        let higherWrist = max(leftWrist.y, rightWrist.y)
        let armsUp = lowerWrist >= shoulderY + thresholds.armsUpMargin * torso
        let armsDown = higherWrist <= shoulderY - thresholds.armsDownMargin * torso
        let spread = abs(leftAnkle.x - rightAnkle.x) / shoulderWidth
        let isOpen = armsUp && spread >= thresholds.feetApartRatio
        let isClosed = armsDown && spread <= thresholds.feetTogetherRatio

        func output(_ status: Status, _ guidance: Guidance, didCountRep: Bool = false) -> Output {
            Output(repetitionCount: repetitionCount, didCountRep: didCountRep, status: status, guidance: guidance)
        }

        switch phase {
        case .waitingForStart:
            guard isClosed else { return output(.waitingForStart, .startClosed) }
            phase = .closed
            cycleStartedAt = pose.timestamp
            return output(.ready, .jumpOut)

        case .closed:
            if isOpen {
                phase = .open
                return output(.open, .jumpIn)
            }
            return isClosed ? output(.ready, .jumpOut) : output(.opening, .jumpOut)

        case .open:
            guard isClosed else {
                return isOpen ? output(.open, .jumpIn) : output(.closing, .jumpIn)
            }
            return completeRep(at: pose.timestamp)
                ? output(.ready, .jumpOut, didCountRep: true)
                : output(.ready, .slowDown)
        }
    }

    // MARK: - Transitions

    private mutating func completeRep(at timestamp: TimeInterval) -> Bool {
        let duration = timestamp - (cycleStartedAt ?? timestamp)
        let debounceElapsed = timestamp - (lastRepAt ?? -.infinity)
        phase = .closed
        cycleStartedAt = timestamp
        guard duration >= thresholds.minimumRepDuration,
              debounceElapsed >= thresholds.repDebounceDuration else {
            return false
        }
        repetitionCount += 1
        lastRepAt = timestamp
        return true
    }

    private mutating func invalidPose(at timestamp: TimeInterval, status: Status, guidance: Guidance) -> Output {
        if poseLostAt == nil { poseLostAt = timestamp }
        recoverIfNeeded(at: timestamp)
        return Output(repetitionCount: repetitionCount, didCountRep: false, status: status, guidance: guidance)
    }

    private mutating func recoverIfNeeded(at timestamp: TimeInterval) {
        guard let poseLostAt, timestamp - poseLostAt >= thresholds.poseLossResetDuration else { return }
        resetCycle()
    }

    private mutating func resetCycle() {
        phase = .waitingForStart
        cycleStartedAt = nil
    }

    private func inFrame(_ point: BodyPosePoint) -> Bool {
        let margin = thresholds.frameMargin
        return point.x >= margin && point.x <= 1 - margin && point.y >= margin && point.y <= 1 - margin
    }
}
