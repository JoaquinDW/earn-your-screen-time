import Foundation
import Testing
@testable import EarnDomain

@Suite("Pushup rep counter")
struct PushupRepCounterTests {
    private let thresholds = PushupPoseThresholds(
        minimumJointConfidence: 0.5,
        frameMargin: 0.02,
        minimumPlankAngleDegrees: 150,
        topEnterAngleDegrees: 160,
        topExitAngleDegrees: 145,
        bottomEnterAngleDegrees: 90,
        bottomExitAngleDegrees: 110,
        minimumRepDuration: 0.5,
        repDebounceDuration: 0.3,
        poseLossResetDuration: 0.75
    )

    private func pose(
        angle: Double,
        at timestamp: TimeInterval,
        confidence: Double = 1,
        framed: Bool = true,
        validPlank: Bool = true
    ) -> BodyPose {
        let shoulder = BodyPosePoint(x: framed ? 0.2 : 0.01, y: 0.4, confidence: confidence)
        let elbow = BodyPosePoint(x: 0.4, y: 0.4, confidence: confidence)
        let radians = (180 - angle) * .pi / 180
        let wrist = BodyPosePoint(
            x: elbow.x + 0.2 * cos(radians),
            y: elbow.y + 0.2 * sin(radians),
            confidence: confidence
        )
        let hip = BodyPosePoint(x: 0.5, y: 0.5, confidence: confidence)
        let ankle = validPlank
            ? BodyPosePoint(x: 0.8, y: 0.6, confidence: confidence)
            : BodyPosePoint(x: 0.5, y: 0.8, confidence: confidence)
        return BodyPose(timestamp: timestamp, points: [
            .leftShoulder: shoulder,
            .leftElbow: elbow,
            .leftWrist: wrist,
            .leftHip: hip,
            .leftAnkle: ankle
        ])
    }

    @Test("Only a complete top-bottom-top cycle counts")
    func completeCycle() {
        var counter = PushupRepCounter(thresholds: thresholds)
        #expect(counter.process(pose(angle: 165, at: 0)).status == .ready)
        #expect(counter.process(pose(angle: 140, at: 0.2)).status == .lowering)
        #expect(counter.process(pose(angle: 85, at: 0.4)).status == .bottom)
        #expect(counter.process(pose(angle: 120, at: 0.6)).status == .rising)
        let completion = counter.process(pose(angle: 165, at: 0.8))
        #expect(completion.didCountRep)
        #expect(completion.repetitionCount == 1)
    }

    @Test("Hysteresis ignores noise around top and bottom")
    func hysteresis() {
        var counter = PushupRepCounter(thresholds: thresholds)
        _ = counter.process(pose(angle: 165, at: 0))
        #expect(counter.process(pose(angle: 150, at: 0.1)).status == .ready)
        _ = counter.process(pose(angle: 85, at: 0.3))
        #expect(counter.process(pose(angle: 105, at: 0.5)).status == .bottom)
        #expect(counter.repetitionCount == 0)
    }

    @Test("Fast and debounced cycles do not count")
    func timingGuards() {
        var fast = PushupRepCounter(thresholds: thresholds)
        _ = fast.process(pose(angle: 165, at: 0))
        _ = fast.process(pose(angle: 85, at: 0.1))
        let rejected = fast.process(pose(angle: 165, at: 0.2))
        #expect(!rejected.didCountRep)
        #expect(rejected.guidance == .slowDown)

        var debounced = PushupRepCounter(thresholds: PushupPoseThresholds(
            minimumRepDuration: 0.1,
            repDebounceDuration: 1
        ))
        _ = debounced.process(pose(angle: 165, at: 0))
        _ = debounced.process(pose(angle: 85, at: 0.2))
        #expect(debounced.process(pose(angle: 165, at: 0.4)).didCountRep)
        _ = debounced.process(pose(angle: 85, at: 0.6))
        #expect(!debounced.process(pose(angle: 165, at: 0.9)).didCountRep)
        #expect(debounced.repetitionCount == 1)
    }

    @Test("Confidence, framing, and plank validation return actionable guidance")
    func validationGuidance() {
        var counter = PushupRepCounter(thresholds: thresholds)
        #expect(counter.process(pose(angle: 165, at: 0, confidence: 0.2)).status == .lowConfidence)
        #expect(counter.process(pose(angle: 165, at: 0.1, framed: false)).guidance == .moveIntoFrame)
        let plank = counter.process(pose(angle: 165, at: 0.2, validPlank: false))
        #expect(plank.status == .plankInvalid)
        #expect(plank.guidance == .straightenBody)
        #expect(counter.process(BodyPose(timestamp: 0.3, points: [:])).status == .poseLost)
    }

    @Test("Brief pose loss preserves a cycle but prolonged loss requires a new top")
    func poseLossRecovery() {
        var brief = PushupRepCounter(thresholds: thresholds)
        _ = brief.process(pose(angle: 165, at: 0))
        _ = brief.process(pose(angle: 85, at: 0.4))
        _ = brief.process(BodyPose(timestamp: 0.5, points: [:]))
        #expect(brief.process(pose(angle: 165, at: 0.8)).didCountRep)

        var prolonged = PushupRepCounter(thresholds: thresholds)
        _ = prolonged.process(pose(angle: 165, at: 0))
        _ = prolonged.process(pose(angle: 85, at: 0.4))
        _ = prolonged.process(BodyPose(timestamp: 0.5, points: [:]))
        let recovered = prolonged.process(pose(angle: 165, at: 1.3))
        #expect(!recovered.didCountRep)
        #expect(recovered.status == .ready)
    }

    @Test("The higher-confidence complete side is selected")
    func sideSelection() {
        let left = pose(angle: 165, at: 0, confidence: 0.6)
        let rightPoints = Dictionary(uniqueKeysWithValues: left.points.map { joint, point in
            let right: BodyJoint = switch joint {
            case .leftShoulder: .rightShoulder
            case .leftElbow: .rightElbow
            case .leftWrist: .rightWrist
            case .leftHip: .rightHip
            case .leftAnkle: .rightAnkle
            default: joint
            }
            return (right, BodyPosePoint(x: point.x, y: point.y, confidence: 0.9))
        })
        var counter = PushupRepCounter(thresholds: thresholds)
        let output = counter.process(BodyPose(timestamp: 0, points: left.points.merging(rightPoints) { old, _ in old }))
        #expect(output.trackedSide == .right)
    }
}

@Suite("Pushup rep counter, selfie framing")
struct PushupRepCounterFrontViewTests {
    private let thresholds = PushupPoseThresholds(
        minimumRepDuration: 0.5,
        repDebounceDuration: 0.3,
        frontMinimumJointConfidence: 0.3,
        frontTopElbowAngleDegrees: 130,
        frontElbowDropDegrees: 35,
        frontDepthGainRatio: 0.16,
        frontBottomEnterScore: 0.72,
        frontBottomExitScore: 0.5,
        frontTopEnterScore: 0.3,
        frontDepthElbowGateScore: 0.3,
        frontMaxTorsoRatio: 1.3
    )

    /// Head-on framing: both shoulders are wide apart and the torso is foreshortened.
    private func pose(
        elbowAngle: Double,
        at timestamp: TimeInterval,
        shoulderSpan: Double = 0.2,
        torsoLength: Double = 0.1,
        confidence: Double = 0.9,
        framed: Bool = true
    ) -> BodyPose {
        let center = framed ? 0.5 : 0.02
        let shoulderY = 0.62
        var points: [BodyJoint: BodyPosePoint] = [:]
        for side in BodySide.allCases {
            let direction: Double = side == .left ? -1 : 1
            let shoulder = BodyPosePoint(
                x: center + direction * shoulderSpan / 2,
                y: shoulderY,
                confidence: confidence
            )
            let elbow = BodyPosePoint(
                x: shoulder.x + direction * 0.06,
                y: shoulder.y - 0.1,
                confidence: confidence
            )
            // Rotate the elbow-to-shoulder vector by the requested angle to place the wrist.
            let toShoulder = (x: shoulder.x - elbow.x, y: shoulder.y - elbow.y)
            let length = (toShoulder.x * toShoulder.x + toShoulder.y * toShoulder.y).squareRoot()
            let unit = (x: toShoulder.x / length, y: toShoulder.y / length)
            let radians = direction * elbowAngle * .pi / 180
            let wrist = BodyPosePoint(
                x: elbow.x + 0.12 * (unit.x * cos(radians) - unit.y * sin(radians)),
                y: elbow.y + 0.12 * (unit.x * sin(radians) + unit.y * cos(radians)),
                confidence: confidence
            )
            let hip = BodyPosePoint(
                x: center + direction * 0.05,
                y: shoulderY + torsoLength,
                confidence: confidence
            )
            points[side == .left ? .leftShoulder : .rightShoulder] = shoulder
            points[side == .left ? .leftElbow : .rightElbow] = elbow
            points[side == .left ? .leftWrist : .rightWrist] = wrist
            points[side == .left ? .leftHip : .rightHip] = hip
        }
        return BodyPose(timestamp: timestamp, points: points)
    }

    @Test("Wide shoulders select the selfie pipeline, a profile keeps the side pipeline")
    func viewModeSelection() {
        var front = PushupRepCounter(thresholds: thresholds)
        #expect(front.process(pose(elbowAngle: 170, at: 0)).viewMode == .front)

        // A profile collapses both shoulders onto each other.
        let shoulder = BodyPosePoint(x: 0.2, y: 0.4, confidence: 0.9)
        let elbow = BodyPosePoint(x: 0.4, y: 0.4, confidence: 0.9)
        var side = PushupRepCounter(thresholds: thresholds)
        let profile = BodyPose(timestamp: 0, points: [
            .leftShoulder: shoulder,
            .leftElbow: elbow,
            .leftWrist: BodyPosePoint(x: 0.6, y: 0.4, confidence: 0.9),
            .leftHip: BodyPosePoint(x: 0.5, y: 0.5, confidence: 0.9),
            .leftAnkle: BodyPosePoint(x: 0.8, y: 0.6, confidence: 0.9),
            .rightShoulder: BodyPosePoint(x: 0.21, y: 0.41, confidence: 0.9),
            .rightElbow: elbow
        ])
        #expect(side.process(profile).viewMode == .side)
    }

    @Test("A selfie-framed cycle counts a repetition")
    func completeCycle() {
        var counter = PushupRepCounter(thresholds: thresholds)
        #expect(counter.process(pose(elbowAngle: 170, at: 0)).status == .ready)
        #expect(counter.process(pose(elbowAngle: 150, at: 0.2)).status == .lowering)
        #expect(counter.process(pose(elbowAngle: 128, at: 0.4)).status == .bottom)
        #expect(counter.process(pose(elbowAngle: 150, at: 0.6)).status == .bottom)
        let completion = counter.process(pose(elbowAngle: 168, at: 0.9))
        #expect(completion.didCountRep)
        #expect(completion.repetitionCount == 1)
        #expect(completion.viewMode == .front)
    }

    @Test("Shoulder growth carries the rep when the elbow bend is foreshortened")
    func depthFromShoulderGrowth() {
        var counter = PushupRepCounter(thresholds: thresholds)
        _ = counter.process(pose(elbowAngle: 170, at: 0))
        let bottom = counter.process(pose(elbowAngle: 157, at: 0.4, shoulderSpan: 0.25))
        #expect(bottom.status == .bottom)
        #expect(counter.process(pose(elbowAngle: 170, at: 0.9)).didCountRep)
    }

    @Test("Leaning into the lens with straight arms never counts")
    func depthAloneDoesNotCount() {
        var counter = PushupRepCounter(thresholds: thresholds)
        _ = counter.process(pose(elbowAngle: 170, at: 0))
        for (index, span) in [0.24, 0.3, 0.34, 0.2].enumerated() {
            let output = counter.process(pose(elbowAngle: 170, at: 0.3 * Double(index + 1), shoulderSpan: span))
            #expect(!output.didCountRep)
            #expect(output.status == .ready)
        }
        #expect(counter.repetitionCount == 0)
    }

    @Test("An upright torso in front of the lens is rejected")
    func uprightTorsoRejected() {
        var counter = PushupRepCounter(thresholds: thresholds)
        let output = counter.process(pose(elbowAngle: 170, at: 0, torsoLength: 0.32))
        #expect(output.status == .plankInvalid)
        #expect(output.guidance == .straightenBody)
    }

    @Test("One cropped hand does not stall the set while the other arm is in view")
    func croppedArmTolerated() {
        var counter = PushupRepCounter(thresholds: thresholds)
        var points = pose(elbowAngle: 170, at: 0).points
        points[.leftWrist] = BodyPosePoint(x: 0.002, y: 0.5, confidence: 0.9)
        let output = counter.process(BodyPose(timestamp: 0, points: points))
        #expect(output.status == .ready)
        #expect(output.trackedSide == .right)
    }

    @Test("Selfie framing tolerates missing legs but still needs both shoulders in frame")
    func framingValidation() {
        var counter = PushupRepCounter(thresholds: thresholds)
        var withoutLegs = pose(elbowAngle: 170, at: 0).points
        withoutLegs[.leftHip] = nil
        withoutLegs[.rightHip] = nil
        #expect(counter.process(BodyPose(timestamp: 0, points: withoutLegs)).status == .ready)
        #expect(counter.process(pose(elbowAngle: 170, at: 0.1, framed: false)).guidance == .moveIntoFrame)
        #expect(counter.process(pose(elbowAngle: 170, at: 0.2, confidence: 0.1)).status == .lowConfidence)
    }
}
