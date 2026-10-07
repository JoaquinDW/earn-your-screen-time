import Foundation
import Testing
@testable import EarnDomain

@Suite("Squat rep counter")
struct SquatRepCounterTests {
    private let thresholds = SquatPoseThresholds(
        minimumJointConfidence: 0.5,
        frameMargin: 0.02,
        standingRatio: 0.7,
        minimumShinHeight: 0.04,
        bottomEnterScore: 0.5,
        bottomExitScore: 0.35,
        topEnterScore: 0.2,
        minimumRepDuration: 0.6,
        repDebounceDuration: 0.3,
        poseLossResetDuration: 0.75
    )

    /// A person facing the lens. `thighDegrees` is the thigh's tilt away from vertical: 0
    /// standing, 90 with the hips at knee height. Facing the camera that tilt points the thigh
    /// at the lens, so on screen only its vertical extent changes.
    private func pose(
        thighDegrees: Double,
        at timestamp: TimeInterval,
        scale: Double = 1,
        confidence: Double = 1,
        footY: Double = 0.1,
        shoulders: Bool = true,
        lyingDown: Bool = false,
        legs: [BodySide] = [.left, .right]
    ) -> BodyPose {
        let shin = 0.2 * scale
        let thigh = 0.22 * scale
        let shinTilt = thighDegrees / 3 * .pi / 180
        var points: [BodyJoint: BodyPosePoint] = [:]
        for side in legs {
            let x = side == .left ? 0.45 : 0.55
            let ankle = BodyPosePoint(x: x, y: footY, confidence: confidence)
            let knee: BodyPosePoint
            let hip: BodyPosePoint
            if lyingDown {
                knee = BodyPosePoint(x: x + shin, y: footY + 0.01, confidence: confidence)
                hip = BodyPosePoint(x: x + shin + thigh, y: footY + 0.02, confidence: confidence)
            } else {
                knee = BodyPosePoint(x: x, y: footY + shin * cos(shinTilt), confidence: confidence)
                hip = BodyPosePoint(
                    x: x,
                    y: knee.y + thigh * cos(thighDegrees * .pi / 180),
                    confidence: confidence
                )
            }
            points[side == .left ? .leftAnkle : .rightAnkle] = ankle
            points[side == .left ? .leftKnee : .rightKnee] = knee
            points[side == .left ? .leftHip : .rightHip] = hip
            if shoulders {
                let shoulderY = lyingDown ? footY + 0.02 : hip.y + 0.3 * scale
                let shoulderX = lyingDown ? hip.x + 0.3 * scale : x
                points[side == .left ? .leftShoulder : .rightShoulder] = BodyPosePoint(
                    x: min(0.97, shoulderX),
                    y: shoulderY,
                    confidence: confidence
                )
            }
        }
        return BodyPose(timestamp: timestamp, points: points)
    }

    private func standing(_ counter: inout SquatRepCounter, at timestamp: TimeInterval = 0) {
        _ = counter.process(pose(thighDegrees: 0, at: timestamp))
    }

    @Test("Only a full stand-squat-stand cycle counts")
    func completeCycle() {
        var counter = SquatRepCounter(thresholds: thresholds)
        #expect(counter.process(pose(thighDegrees: 0, at: 0)).status == .ready)
        #expect(counter.process(pose(thighDegrees: 50, at: 0.3)).status == .lowering)
        let bottom = counter.process(pose(thighDegrees: 80, at: 0.6))
        #expect(bottom.status == .bottom)
        #expect(bottom.guidance == .standUp)
        #expect(counter.process(pose(thighDegrees: 45, at: 0.9)).status == .rising)
        let completion = counter.process(pose(thighDegrees: 5, at: 1.2))
        #expect(completion.didCountRep)
        #expect(completion.repetitionCount == 1)
    }

    @Test("A shallow knee bend never counts")
    func shallowBend() {
        var counter = SquatRepCounter(thresholds: thresholds)
        standing(&counter)
        for step in 1...6 {
            let degrees = step.isMultiple(of: 2) ? 0.0 : 40.0
            #expect(!counter.process(pose(thighDegrees: degrees, at: Double(step) * 0.4)).didCountRep)
        }
        #expect(counter.repetitionCount == 0)
    }

    @Test("Hysteresis holds the bottom through noise just above it")
    func hysteresis() {
        var counter = SquatRepCounter(thresholds: thresholds)
        standing(&counter)
        _ = counter.process(pose(thighDegrees: 80, at: 0.4))
        // Score drops to ~0.4: above the exit threshold, so still at the bottom.
        #expect(counter.process(pose(thighDegrees: 55, at: 0.5)).status == .bottom)
        #expect(counter.repetitionCount == 0)
    }

    @Test("Moving closer to the phone mid-set does not read as a squat")
    func scaleInvariance() {
        var counter = SquatRepCounter(thresholds: thresholds)
        standing(&counter)
        let closer = counter.process(pose(thighDegrees: 0, at: 0.4, scale: 1.6))
        #expect(closer.status == .ready)
        #expect((closer.depthScore ?? 1) < 0.05)
    }

    @Test("A rep faster than the minimum duration is rejected")
    func tooFast() {
        var counter = SquatRepCounter(thresholds: thresholds)
        standing(&counter)
        _ = counter.process(pose(thighDegrees: 85, at: 0.2))
        let rejected = counter.process(pose(thighDegrees: 0, at: 0.4))
        #expect(!rejected.didCountRep)
        #expect(rejected.guidance == .slowDown)
        #expect(counter.repetitionCount == 0)
    }

    @Test("The set waits for the athlete to stand up first")
    func waitsForStanding() {
        var counter = SquatRepCounter(thresholds: thresholds)
        let crouched = counter.process(pose(thighDegrees: 70, at: 0))
        #expect(crouched.status == .waitingForTop)
        #expect(crouched.guidance == .startStanding)
        #expect(counter.process(pose(thighDegrees: 0, at: 0.3)).status == .ready)
    }

    @Test("Feet out of frame, low confidence and an empty frame are reported")
    func invalidFraming() {
        var counter = SquatRepCounter(thresholds: thresholds)
        #expect(counter.process(BodyPose(timestamp: 0, points: [:])).status == .poseLost)
        #expect(counter.process(pose(thighDegrees: 0, at: 0.1, confidence: 0.2)).status == .lowConfidence)
        let cropped = counter.process(pose(thighDegrees: 0, at: 0.2, footY: 0.005))
        #expect(cropped.status == .notInFrame)
        #expect(cropped.guidance == .moveIntoFrame)
    }

    @Test("Someone lying on the floor is told to stand")
    func lyingDown() {
        var counter = SquatRepCounter(thresholds: thresholds)
        let output = counter.process(pose(thighDegrees: 0, at: 0, lyingDown: true))
        #expect(output.status == .notUpright)
        #expect(output.guidance == .standUpright)
    }

    @Test("One clearly visible leg is enough, as in profile")
    func singleLeg() {
        var counter = SquatRepCounter(thresholds: thresholds)
        _ = counter.process(pose(thighDegrees: 0, at: 0, legs: [.right]))
        _ = counter.process(pose(thighDegrees: 85, at: 0.5, legs: [.right]))
        let completion = counter.process(pose(thighDegrees: 0, at: 1.0, legs: [.right]))
        #expect(completion.didCountRep)
    }

    @Test("Losing the body for a while restarts the cycle without losing the count")
    func poseLossResets() {
        var counter = SquatRepCounter(thresholds: thresholds)
        standing(&counter)
        _ = counter.process(pose(thighDegrees: 85, at: 0.5))
        _ = counter.process(pose(thighDegrees: 0, at: 1.0))
        #expect(counter.repetitionCount == 1)
        _ = counter.process(pose(thighDegrees: 85, at: 1.5))
        _ = counter.process(BodyPose(timestamp: 1.6, points: [:]))
        _ = counter.process(BodyPose(timestamp: 2.5, points: [:]))
        // Back in view standing: the half-finished rep was dropped, not counted.
        let back = counter.process(pose(thighDegrees: 0, at: 2.6))
        #expect(!back.didCountRep)
        #expect(back.status == .ready)
        #expect(counter.repetitionCount == 1)
    }

    @Test("Several clean reps count one each")
    func multipleReps() {
        var counter = SquatRepCounter(thresholds: thresholds)
        var time = 0.0
        standing(&counter, at: time)
        for _ in 0..<5 {
            time += 0.5
            _ = counter.process(pose(thighDegrees: 85, at: time))
            time += 0.5
            _ = counter.process(pose(thighDegrees: 0, at: time))
        }
        #expect(counter.repetitionCount == 5)
    }
}
