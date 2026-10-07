import Foundation

public struct SquatPoseThresholds: Codable, Equatable, Sendable {
    public var minimumJointConfidence: Double
    public var frameMargin: Double
    /// Thigh height over shin height an athlete has to show standing before a set can begin.
    public var standingRatio: Double
    /// Below this shin height (normalized) the legs are lying down, not standing.
    public var minimumShinHeight: Double
    public var bottomEnterScore: Double
    public var bottomExitScore: Double
    public var topEnterScore: Double
    public var minimumRepDuration: TimeInterval
    public var repDebounceDuration: TimeInterval
    public var poseLossResetDuration: TimeInterval

    public init(
        minimumJointConfidence: Double = 0.4,
        frameMargin: Double = 0.01,
        standingRatio: Double = 0.7,
        minimumShinHeight: Double = 0.04,
        bottomEnterScore: Double = 0.5,
        bottomExitScore: Double = 0.35,
        topEnterScore: Double = 0.2,
        minimumRepDuration: TimeInterval = 0.6,
        repDebounceDuration: TimeInterval = 0.3,
        poseLossResetDuration: TimeInterval = 0.75
    ) {
        self.minimumJointConfidence = minimumJointConfidence
        self.frameMargin = frameMargin
        self.standingRatio = standingRatio
        self.minimumShinHeight = minimumShinHeight
        self.bottomEnterScore = bottomEnterScore
        self.bottomExitScore = bottomExitScore
        self.topEnterScore = topEnterScore
        self.minimumRepDuration = minimumRepDuration
        self.repDebounceDuration = repDebounceDuration
        self.poseLossResetDuration = poseLossResetDuration
    }
}

/// Counts squats from the height of the thighs measured against the shins.
///
/// Standing, the hips sit a thigh's length above the knees; at depth they drop to knee height.
/// Facing the lens the thigh points at the camera and the knee angle barely changes on screen,
/// but the vertical hip-to-knee gap still collapses, so the same signal works head-on and in
/// profile. Dividing by the shin height keeps it independent of how far away the phone is.
public struct SquatRepCounter: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case poseLost
        case lowConfidence
        case notInFrame
        case notUpright
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
        case standUpright
        case startStanding
        case lowerHips
        case standUp
        case slowDown
        case none
    }

    public struct Output: Equatable, Sendable {
        public let repetitionCount: Int
        public let didCountRep: Bool
        public let status: Status
        public let guidance: Guidance
        /// Depth of the current repetition, 0 standing and 1 with the hips at knee height.
        public let depthScore: Double?
    }

    private enum Phase: Equatable, Sendable {
        case waitingForTop
        case top
        case bottom
    }

    public let thresholds: SquatPoseThresholds
    public private(set) var repetitionCount: Int
    private var phase: Phase = .waitingForTop
    private var cycleStartedAt: TimeInterval?
    private var lastRepAt: TimeInterval?
    private var poseLostAt: TimeInterval?
    private var topRatio: Double?

    public init(thresholds: SquatPoseThresholds = SquatPoseThresholds(), repetitionCount: Int = 0) {
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
        let legs = legs(in: pose)
        guard !legs.isEmpty else {
            return invalidPose(at: pose.timestamp, status: .poseLost, guidance: .findBody)
        }
        // A leg the lens reads cleanly is enough; the far leg is often hidden in profile.
        let usable = legs.filter { leg in leg.points.allSatisfy { $0.confidence >= thresholds.minimumJointConfidence } }
        guard !usable.isEmpty else {
            return invalidPose(at: pose.timestamp, status: .lowConfidence, guidance: .improveLighting)
        }
        guard usable.allSatisfy({ $0.points.allSatisfy(inFrame) }) else {
            return invalidPose(at: pose.timestamp, status: .notInFrame, guidance: .moveIntoFrame)
        }

        let count = Double(usable.count)
        let hipY = usable.reduce(0) { $0 + $1.hip.y } / count
        let thigh = usable.reduce(0) { $0 + ($1.hip.y - $1.knee.y) } / count
        let shin = usable.reduce(0) { $0 + ($1.knee.y - $1.ankle.y) } / count
        guard shin >= thresholds.minimumShinHeight, !isTorsoBelowHips(in: pose, hipY: hipY) else {
            return invalidPose(at: pose.timestamp, status: .notUpright, guidance: .standUpright)
        }

        recoverIfNeeded(at: pose.timestamp)
        poseLostAt = nil

        let ratio = max(0, thigh) / shin
        let score = depthScore(for: ratio)

        func output(_ status: Status, _ guidance: Guidance, didCountRep: Bool = false) -> Output {
            Output(
                repetitionCount: repetitionCount,
                didCountRep: didCountRep,
                status: status,
                guidance: guidance,
                depthScore: phase == .waitingForTop ? nil : score
            )
        }

        switch phase {
        case .waitingForTop:
            guard ratio >= thresholds.standingRatio else {
                return output(.waitingForTop, .startStanding)
            }
            topRatio = ratio
            phase = .top
            cycleStartedAt = pose.timestamp
            return output(.ready, .lowerHips)

        case .top:
            if score >= thresholds.bottomEnterScore {
                phase = .bottom
                return output(.bottom, .standUp)
            }
            if score > thresholds.topEnterScore {
                return output(.lowering, .lowerHips)
            }
            adaptTopRatio(to: ratio)
            return output(.ready, .lowerHips)

        case .bottom:
            if score > thresholds.bottomExitScore {
                return output(.bottom, .standUp)
            }
            guard score <= thresholds.topEnterScore else {
                return output(.rising, .standUp)
            }
            let outcome = completeRep(at: pose.timestamp)
            adaptTopRatio(to: ratio)
            return outcome
                ? output(.ready, .lowerHips, didCountRep: true)
                : output(.ready, .slowDown)
        }
    }

    // MARK: - Depth

    private func depthScore(for ratio: Double) -> Double {
        guard let topRatio, topRatio > 0 else { return 0 }
        return min(1, max(0, 1 - ratio / topRatio))
    }

    /// Standing height drifts as the athlete shifts their feet, so the reference follows them
    /// slowly while they are up. It never sinks below what counts as standing, so a set of
    /// shallow reps cannot redefine "standing" as half-way down.
    private mutating func adaptTopRatio(to ratio: Double) {
        let current = topRatio ?? ratio
        topRatio = max(thresholds.standingRatio, current + (ratio - current) * 0.2)
    }

    /// Someone lying on the floor can still show three leg joints in a column; shoulders level
    /// with or under the hips give them away.
    private func isTorsoBelowHips(in pose: BodyPose, hipY: Double) -> Bool {
        let shoulders = [pose[.leftShoulder], pose[.rightShoulder]]
            .compactMap { $0 }
            .filter { $0.confidence >= thresholds.minimumJointConfidence }
        guard !shoulders.isEmpty else { return false }
        let shoulderY = shoulders.reduce(0) { $0 + $1.y } / Double(shoulders.count)
        return shoulderY <= hipY
    }

    // MARK: - Transitions

    private mutating func completeRep(at timestamp: TimeInterval) -> Bool {
        let duration = timestamp - (cycleStartedAt ?? timestamp)
        let debounceElapsed = timestamp - (lastRepAt ?? -.infinity)
        phase = .top
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
        return Output(
            repetitionCount: repetitionCount,
            didCountRep: false,
            status: status,
            guidance: guidance,
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
        topRatio = nil
    }

    private func inFrame(_ point: BodyPosePoint) -> Bool {
        let margin = thresholds.frameMargin
        return point.x >= margin && point.x <= 1 - margin && point.y >= margin && point.y <= 1 - margin
    }

    // MARK: - Samples

    private struct Leg {
        let hip: BodyPosePoint
        let knee: BodyPosePoint
        let ankle: BodyPosePoint

        var points: [BodyPosePoint] { [hip, knee, ankle] }
    }

    private func legs(in pose: BodyPose) -> [Leg] {
        BodySide.allCases.compactMap { side in
            let joints: (BodyJoint, BodyJoint, BodyJoint) = side == .left
                ? (.leftHip, .leftKnee, .leftAnkle)
                : (.rightHip, .rightKnee, .rightAnkle)
            guard let hip = pose[joints.0], let knee = pose[joints.1], let ankle = pose[joints.2] else { return nil }
            return Leg(hip: hip, knee: knee, ankle: ankle)
        }
    }
}
