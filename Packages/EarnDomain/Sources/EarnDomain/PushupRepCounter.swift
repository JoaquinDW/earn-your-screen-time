import Foundation

public enum BodySide: String, Codable, CaseIterable, Sendable {
    case left
    case right
}

/// How the camera sees the athlete. The rep signal differs between the two framings.
public enum PushupViewMode: String, Codable, CaseIterable, Sendable {
    /// The phone lies to the side and records a full profile.
    case side
    /// The phone faces the athlete (selfie framing), so the body is foreshortened.
    case front
}

public enum BodyJoint: String, Codable, CaseIterable, Sendable {
    case leftShoulder
    case leftElbow
    case leftWrist
    case leftHip
    case leftAnkle
    case rightShoulder
    case rightElbow
    case rightWrist
    case rightHip
    case rightAnkle
}

public struct BodyPosePoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let confidence: Double

    public init(x: Double, y: Double, confidence: Double) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

/// A normalized, framework-independent pose observation.
public struct BodyPose: Codable, Equatable, Sendable {
    public let timestamp: TimeInterval
    public let points: [BodyJoint: BodyPosePoint]

    public init(timestamp: TimeInterval, points: [BodyJoint: BodyPosePoint]) {
        self.timestamp = timestamp
        self.points = points
    }

    public subscript(_ joint: BodyJoint) -> BodyPosePoint? { points[joint] }
}

public struct PushupPoseThresholds: Codable, Equatable, Sendable {
    public var minimumJointConfidence: Double
    public var frameMargin: Double
    public var minimumPlankAngleDegrees: Double
    public var topEnterAngleDegrees: Double
    public var topExitAngleDegrees: Double
    public var bottomEnterAngleDegrees: Double
    public var bottomExitAngleDegrees: Double
    public var minimumRepDuration: TimeInterval
    public var repDebounceDuration: TimeInterval
    public var poseLossResetDuration: TimeInterval

    // Selfie framing. Absolute joint angles are unreliable head-on, so depth is
    // measured against a baseline captured while the athlete rests at the top.
    public var frontMinimumJointConfidence: Double
    public var frontFrameMargin: Double
    public var frontTopElbowAngleDegrees: Double
    public var frontElbowDropDegrees: Double
    public var frontDepthGainRatio: Double
    public var frontBottomEnterScore: Double
    public var frontBottomExitScore: Double
    public var frontTopEnterScore: Double
    public var frontDepthElbowGateScore: Double
    public var frontMaxTorsoRatio: Double
    public var frontViewEnterRatio: Double
    public var frontViewExitRatio: Double

    public init(
        minimumJointConfidence: Double = 0.55,
        frameMargin: Double = 0.03,
        minimumPlankAngleDegrees: Double = 155,
        topEnterAngleDegrees: Double = 160,
        topExitAngleDegrees: Double = 145,
        bottomEnterAngleDegrees: Double = 90,
        bottomExitAngleDegrees: Double = 110,
        minimumRepDuration: TimeInterval = 0.5,
        repDebounceDuration: TimeInterval = 0.3,
        poseLossResetDuration: TimeInterval = 0.75,
        frontMinimumJointConfidence: Double = 0.3,
        frontFrameMargin: Double = 0.01,
        frontTopElbowAngleDegrees: Double = 130,
        frontElbowDropDegrees: Double = 35,
        frontDepthGainRatio: Double = 0.16,
        frontBottomEnterScore: Double = 0.72,
        frontBottomExitScore: Double = 0.5,
        frontTopEnterScore: Double = 0.3,
        frontDepthElbowGateScore: Double = 0.3,
        frontMaxTorsoRatio: Double = 1.3,
        frontViewEnterRatio: Double = 0.9,
        frontViewExitRatio: Double = 0.6
    ) {
        self.minimumJointConfidence = minimumJointConfidence
        self.frameMargin = frameMargin
        self.minimumPlankAngleDegrees = minimumPlankAngleDegrees
        self.topEnterAngleDegrees = topEnterAngleDegrees
        self.topExitAngleDegrees = topExitAngleDegrees
        self.bottomEnterAngleDegrees = bottomEnterAngleDegrees
        self.bottomExitAngleDegrees = bottomExitAngleDegrees
        self.minimumRepDuration = minimumRepDuration
        self.repDebounceDuration = repDebounceDuration
        self.poseLossResetDuration = poseLossResetDuration
        self.frontMinimumJointConfidence = frontMinimumJointConfidence
        self.frontFrameMargin = frontFrameMargin
        self.frontTopElbowAngleDegrees = frontTopElbowAngleDegrees
        self.frontElbowDropDegrees = frontElbowDropDegrees
        self.frontDepthGainRatio = frontDepthGainRatio
        self.frontBottomEnterScore = frontBottomEnterScore
        self.frontBottomExitScore = frontBottomExitScore
        self.frontTopEnterScore = frontTopEnterScore
        self.frontDepthElbowGateScore = frontDepthElbowGateScore
        self.frontMaxTorsoRatio = frontMaxTorsoRatio
        self.frontViewEnterRatio = frontViewEnterRatio
        self.frontViewExitRatio = frontViewExitRatio
    }
}

public struct PushupRepCounter: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case poseLost
        case lowConfidence
        case notInFrame
        case plankInvalid
        case waitingForTop
        case ready
        case lowering
        case bottom
        case rising
    }

    public enum Guidance: String, Equatable, Sendable {
        case findBody
        case improveLighting
        case moveIntoFrame
        case straightenBody
        case startAtTop
        case lowerBody
        case pushUp
        case slowDown
        case none
    }

    public struct Output: Equatable, Sendable {
        public let repetitionCount: Int
        public let didCountRep: Bool
        public let status: Status
        public let guidance: Guidance
        public let trackedSide: BodySide?
        public let elbowAngleDegrees: Double?
        public let plankAngleDegrees: Double?
        public let viewMode: PushupViewMode?
        /// Depth of the current repetition, 0 at the top and 1 at full depth.
        public let depthScore: Double?
    }

    private enum Phase: Equatable, Sendable {
        case waitingForTop
        case top
        case bottom
    }

    public let thresholds: PushupPoseThresholds
    public private(set) var repetitionCount: Int
    public private(set) var viewMode: PushupViewMode?
    private var phase: Phase = .waitingForTop
    private var cycleStartedAt: TimeInterval?
    private var lastRepAt: TimeInterval?
    private var poseLostAt: TimeInterval?
    private var topElbowAngle: Double?
    private var topDepth: Double?

    public init(thresholds: PushupPoseThresholds = PushupPoseThresholds(), repetitionCount: Int = 0) {
        self.thresholds = thresholds
        self.repetitionCount = max(0, repetitionCount)
    }

    public mutating func reset(repetitionCount: Int = 0) {
        self.repetitionCount = max(0, repetitionCount)
        resetCycle()
        viewMode = nil
        lastRepAt = nil
        poseLostAt = nil
    }

    public mutating func process(_ pose: BodyPose) -> Output {
        switch resolveViewMode(in: pose) {
        case .front:
            return processFront(pose)
        case .side:
            return processSide(pose)
        }
    }

    // MARK: - View mode

    /// Head-on framing projects both shoulders wide apart; a profile collapses them
    /// onto each other. Measuring the span against the upper arm keeps the ratio
    /// independent of how far away the phone sits.
    private mutating func resolveViewMode(in pose: BodyPose) -> PushupViewMode {
        let previous = viewMode
        if let ratio = shoulderSpanRatio(in: pose) {
            let isFront = previous == .front
                ? ratio > thresholds.frontViewExitRatio
                : ratio >= thresholds.frontViewEnterRatio
            viewMode = isFront ? .front : .side
        } else if previous == nil {
            viewMode = .side
        }
        if viewMode != previous, previous != nil {
            resetCycle()
        }
        return viewMode ?? .side
    }

    private func shoulderSpanRatio(in pose: BodyPose) -> Double? {
        let minimum = min(thresholds.minimumJointConfidence, thresholds.frontMinimumJointConfidence)
        guard let left = pose[.leftShoulder], let right = pose[.rightShoulder],
              left.confidence >= minimum, right.confidence >= minimum else { return nil }
        let armLengths = [(left, pose[.leftElbow]), (right, pose[.rightElbow])].compactMap { shoulder, elbow -> Double? in
            guard let elbow, elbow.confidence >= minimum else { return nil }
            return Self.distance(shoulder, elbow)
        }
        guard let arm = armLengths.max(), arm > 0 else { return nil }
        return Self.distance(left, right) / arm
    }

    // MARK: - Side framing

    private mutating func processSide(_ pose: BodyPose) -> Output {
        guard let sample = bestSample(in: pose) else {
            return invalidPose(at: pose.timestamp, status: .poseLost, guidance: .findBody)
        }
        guard sample.points.allSatisfy({ $0.confidence >= thresholds.minimumJointConfidence }) else {
            return invalidPose(at: pose.timestamp, status: .lowConfidence, guidance: .improveLighting)
        }
        guard sample.points.allSatisfy({ inFrame($0, margin: thresholds.frameMargin) }) else {
            return invalidPose(at: pose.timestamp, status: .notInFrame, guidance: .moveIntoFrame)
        }

        let elbowAngle = Self.angle(sample.shoulder, sample.elbow, sample.wrist)
        let plankAngle = Self.angle(sample.shoulder, sample.hip, sample.ankle)
        guard plankAngle >= thresholds.minimumPlankAngleDegrees else {
            return invalidPose(
                at: pose.timestamp,
                status: .plankInvalid,
                guidance: .straightenBody,
                side: sample.side,
                elbowAngle: elbowAngle,
                plankAngle: plankAngle
            )
        }

        recoverIfNeeded(at: pose.timestamp)
        poseLostAt = nil

        func output(
            _ status: Status,
            _ guidance: Guidance,
            didCountRep: Bool = false
        ) -> Output {
            Output(
                repetitionCount: repetitionCount,
                didCountRep: didCountRep,
                status: status,
                guidance: guidance,
                trackedSide: sample.side,
                elbowAngleDegrees: elbowAngle,
                plankAngleDegrees: plankAngle,
                viewMode: .side,
                depthScore: nil
            )
        }

        switch phase {
        case .waitingForTop:
            guard elbowAngle >= thresholds.topEnterAngleDegrees else {
                return output(.waitingForTop, .startAtTop)
            }
            phase = .top
            cycleStartedAt = pose.timestamp
            return output(.ready, .lowerBody)

        case .top:
            if elbowAngle >= thresholds.topExitAngleDegrees {
                return output(.ready, .lowerBody)
            }
            if elbowAngle <= thresholds.bottomEnterAngleDegrees {
                phase = .bottom
                return output(.bottom, .pushUp)
            }
            return output(.lowering, .lowerBody)

        case .bottom:
            if elbowAngle <= thresholds.bottomExitAngleDegrees {
                return output(.bottom, .pushUp)
            }
            guard elbowAngle >= thresholds.topEnterAngleDegrees else {
                return output(.rising, .pushUp)
            }
            switch completeRep(at: pose.timestamp) {
            case .counted:
                return output(.ready, .lowerBody, didCountRep: true)
            case .tooFast:
                return output(.ready, .slowDown)
            }
        }
    }

    // MARK: - Selfie framing

    private mutating func processFront(_ pose: BodyPose) -> Output {
        guard let sample = frontSample(in: pose) else {
            return invalidPose(at: pose.timestamp, status: .poseLost, guidance: .findBody)
        }
        guard sample.isConfident(above: thresholds.frontMinimumJointConfidence) else {
            return invalidPose(at: pose.timestamp, status: .lowConfidence, guidance: .improveLighting)
        }
        guard sample.trackedPoints.allSatisfy({ inFrame($0, margin: thresholds.frontFrameMargin) }) else {
            return invalidPose(at: pose.timestamp, status: .notInFrame, guidance: .moveIntoFrame)
        }
        // Head-on, a plank foreshortens the torso; someone sitting or kneeling in
        // front of the lens keeps a long shoulder-to-hip span.
        if let torsoRatio = sample.torsoToShoulderRatio, torsoRatio > thresholds.frontMaxTorsoRatio {
            return invalidPose(
                at: pose.timestamp,
                status: .plankInvalid,
                guidance: .straightenBody,
                side: sample.side,
                elbowAngle: sample.elbowAngle,
                mode: .front
            )
        }

        recoverIfNeeded(at: pose.timestamp)
        poseLostAt = nil

        let score = depthScore(for: sample)

        func output(
            _ status: Status,
            _ guidance: Guidance,
            didCountRep: Bool = false
        ) -> Output {
            Output(
                repetitionCount: repetitionCount,
                didCountRep: didCountRep,
                status: status,
                guidance: guidance,
                trackedSide: sample.side,
                elbowAngleDegrees: sample.elbowAngle,
                plankAngleDegrees: nil,
                viewMode: .front,
                depthScore: score
            )
        }

        switch phase {
        case .waitingForTop:
            guard sample.elbowAngle >= thresholds.frontTopElbowAngleDegrees else {
                return output(.waitingForTop, .startAtTop)
            }
            captureTopBaseline(from: sample)
            phase = .top
            cycleStartedAt = pose.timestamp
            return output(.ready, .lowerBody)

        case .top:
            if score >= thresholds.frontBottomEnterScore {
                phase = .bottom
                return output(.bottom, .pushUp)
            }
            if score > thresholds.frontTopEnterScore {
                return output(.lowering, .lowerBody)
            }
            adaptTopBaseline(to: sample)
            return output(.ready, .lowerBody)

        case .bottom:
            if score > thresholds.frontBottomExitScore {
                return output(.bottom, .pushUp)
            }
            guard score <= thresholds.frontTopEnterScore else {
                return output(.rising, .pushUp)
            }
            switch completeRep(at: pose.timestamp) {
            case .counted:
                adaptTopBaseline(to: sample)
                return output(.ready, .lowerBody, didCountRep: true)
            case .tooFast:
                adaptTopBaseline(to: sample)
                return output(.ready, .slowDown)
            }
        }
    }

    /// Both cues are measured against the athlete's own top position: elbows fold and
    /// the shoulders grow as the chest drops toward a lens that is facing them. Depth
    /// only counts once the elbows have started to bend, so leaning into the camera
    /// alone never produces a repetition.
    private func depthScore(for sample: FrontSample) -> Double {
        guard let topElbowAngle else { return 0 }
        let elbowScore = Self.clamp((topElbowAngle - sample.elbowAngle) / max(1, thresholds.frontElbowDropDegrees))
        guard elbowScore >= thresholds.frontDepthElbowGateScore,
              let topDepth, topDepth > 0 else { return elbowScore }
        let growth = (sample.shoulderSpan / topDepth) - 1
        let growthScore = Self.clamp(growth / max(0.01, thresholds.frontDepthGainRatio))
        return max(elbowScore, growthScore)
    }

    private mutating func captureTopBaseline(from sample: FrontSample) {
        topElbowAngle = sample.elbowAngle
        topDepth = sample.shoulderSpan
    }

    private mutating func adaptTopBaseline(to sample: FrontSample) {
        let smoothing = 0.2
        topElbowAngle = max(
            thresholds.frontTopElbowAngleDegrees,
            (topElbowAngle ?? sample.elbowAngle) + (sample.elbowAngle - (topElbowAngle ?? sample.elbowAngle)) * smoothing
        )
        topDepth = (topDepth ?? sample.shoulderSpan)
            + (sample.shoulderSpan - (topDepth ?? sample.shoulderSpan)) * smoothing
    }

    // MARK: - Shared transitions

    private enum RepOutcome {
        case counted
        case tooFast
    }

    private mutating func completeRep(at timestamp: TimeInterval) -> RepOutcome {
        let duration = timestamp - (cycleStartedAt ?? timestamp)
        let debounceElapsed = timestamp - (lastRepAt ?? -.infinity)
        phase = .top
        cycleStartedAt = timestamp
        guard duration >= thresholds.minimumRepDuration,
              debounceElapsed >= thresholds.repDebounceDuration else {
            return .tooFast
        }
        repetitionCount += 1
        lastRepAt = timestamp
        return .counted
    }

    private mutating func invalidPose(
        at timestamp: TimeInterval,
        status: Status,
        guidance: Guidance,
        side: BodySide? = nil,
        elbowAngle: Double? = nil,
        plankAngle: Double? = nil,
        mode: PushupViewMode? = nil
    ) -> Output {
        if poseLostAt == nil { poseLostAt = timestamp }
        recoverIfNeeded(at: timestamp)
        return Output(
            repetitionCount: repetitionCount,
            didCountRep: false,
            status: status,
            guidance: guidance,
            trackedSide: side,
            elbowAngleDegrees: elbowAngle,
            plankAngleDegrees: plankAngle,
            viewMode: mode ?? viewMode,
            depthScore: nil
        )
    }

    private mutating func recoverIfNeeded(at timestamp: TimeInterval) {
        guard let poseLostAt, timestamp - poseLostAt >= thresholds.poseLossResetDuration else { return }
        resetCycle()
    }

    private mutating func resetCycle() {
        phase = .waitingForTop
        cycleStartedAt = nil
        topElbowAngle = nil
        topDepth = nil
    }

    private func inFrame(_ point: BodyPosePoint, margin: Double) -> Bool {
        point.x >= margin && point.x <= 1 - margin && point.y >= margin && point.y <= 1 - margin
    }

    // MARK: - Samples

    private struct SideSample {
        let side: BodySide
        let shoulder: BodyPosePoint
        let elbow: BodyPosePoint
        let wrist: BodyPosePoint
        let hip: BodyPosePoint
        let ankle: BodyPosePoint

        var points: [BodyPosePoint] { [shoulder, elbow, wrist, hip, ankle] }
        var confidence: Double { points.reduce(0) { $0 + $1.confidence } / Double(points.count) }
    }

    private struct FrontSample {
        let side: BodySide
        let elbowAngle: Double
        let shoulderSpan: Double
        let torsoToShoulderRatio: Double?
        let trackedPoints: [BodyPosePoint]

        func isConfident(above minimum: Double) -> Bool {
            trackedPoints.allSatisfy { $0.confidence >= minimum }
        }
    }

    private func bestSample(in pose: BodyPose) -> SideSample? {
        let samples = BodySide.allCases.compactMap { side -> SideSample? in
            let joints: (BodyJoint, BodyJoint, BodyJoint, BodyJoint, BodyJoint) = side == .left
                ? (.leftShoulder, .leftElbow, .leftWrist, .leftHip, .leftAnkle)
                : (.rightShoulder, .rightElbow, .rightWrist, .rightHip, .rightAnkle)
            guard let shoulder = pose[joints.0], let elbow = pose[joints.1], let wrist = pose[joints.2],
                  let hip = pose[joints.3], let ankle = pose[joints.4] else { return nil }
            return SideSample(side: side, shoulder: shoulder, elbow: elbow, wrist: wrist, hip: hip, ankle: ankle)
        }
        return samples.max { $0.confidence < $1.confidence }
    }

    /// Selfie framing needs both shoulders plus at least one arm; ankles and knees
    /// trail away from the lens and are routinely out of frame.
    private func frontSample(in pose: BodyPose) -> FrontSample? {
        guard let leftShoulder = pose[.leftShoulder], let rightShoulder = pose[.rightShoulder] else { return nil }
        let minimum = thresholds.frontMinimumJointConfidence

        struct Arm {
            let side: BodySide
            let angle: Double
            let points: [BodyPosePoint]
            let confidence: Double
        }

        let arms: [Arm] = BodySide.allCases.compactMap { side in
            let shoulder = side == .left ? leftShoulder : rightShoulder
            let joints: (BodyJoint, BodyJoint) = side == .left ? (.leftElbow, .leftWrist) : (.rightElbow, .rightWrist)
            guard let elbow = pose[joints.0], let wrist = pose[joints.1] else { return nil }
            let points = [shoulder, elbow, wrist]
            return Arm(
                side: side,
                angle: Self.angle(shoulder, elbow, wrist),
                points: points,
                confidence: points.reduce(0) { $0 + $1.confidence } / 3
            )
        }
        // Track the arm the lens reads cleanly; a hand cropped at the edge of a close-up
        // selfie should not stall the set while the other arm is in full view.
        let usableArms = arms.filter { arm in
            arm.points.allSatisfy { $0.confidence >= minimum && inFrame($0, margin: thresholds.frontFrameMargin) }
        }
        guard let best = (usableArms.max { $0.confidence < $1.confidence })
            ?? (arms.max { $0.confidence < $1.confidence }) else { return nil }

        // Average both arms when both are trustworthy: it smooths the noisier of the two.
        let angle = usableArms.isEmpty
            ? best.angle
            : usableArms.reduce(0) { $0 + $1.angle } / Double(usableArms.count)

        let shoulderSpan = Self.distance(leftShoulder, rightShoulder)
        let hips = [pose[.leftHip], pose[.rightHip]].compactMap { $0 }.filter { $0.confidence >= minimum }
        let torsoRatio: Double?
        if hips.count == 2, shoulderSpan > 0 {
            let shoulderMid = Self.midpoint(leftShoulder, rightShoulder)
            let hipMid = Self.midpoint(hips[0], hips[1])
            torsoRatio = Self.distance(shoulderMid, hipMid) / shoulderSpan
        } else {
            torsoRatio = nil
        }

        return FrontSample(
            side: best.side,
            elbowAngle: angle,
            shoulderSpan: shoulderSpan,
            torsoToShoulderRatio: torsoRatio,
            trackedPoints: [leftShoulder, rightShoulder] + best.points.dropFirst()
        )
    }

    // MARK: - Geometry

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    private static func distance(_ first: BodyPosePoint, _ second: BodyPosePoint) -> Double {
        hypot(first.x - second.x, first.y - second.y)
    }

    private static func midpoint(_ first: BodyPosePoint, _ second: BodyPosePoint) -> BodyPosePoint {
        BodyPosePoint(
            x: (first.x + second.x) / 2,
            y: (first.y + second.y) / 2,
            confidence: min(first.confidence, second.confidence)
        )
    }

    private static func angle(_ first: BodyPosePoint, _ vertex: BodyPosePoint, _ third: BodyPosePoint) -> Double {
        let firstVector = (x: first.x - vertex.x, y: first.y - vertex.y)
        let secondVector = (x: third.x - vertex.x, y: third.y - vertex.y)
        let denominator = hypot(firstVector.x, firstVector.y) * hypot(secondVector.x, secondVector.y)
        guard denominator > 0 else { return 0 }
        let cosine = min(1, max(-1, (firstVector.x * secondVector.x + firstVector.y * secondVector.y) / denominator))
        return acos(cosine) * 180 / .pi
    }
}
