import Foundation
import Testing
@testable import EarnDomain

@Suite("Jumping jack rep counter")
struct JumpingJackRepCounterTests {
    /// A person facing the lens with shoulders at y 0.7, hips at 0.45 and feet at 0.1.
    private func pose(
        armsUp: Bool,
        feetApart: Bool,
        at timestamp: TimeInterval,
        confidence: Double = 1,
        shoulderHalfWidth: Double = 0.08
    ) -> BodyPose {
        let wristY = armsUp ? 0.88 : 0.48
        let ankleHalfSpread = feetApart ? 0.14 : 0.05
        func point(_ x: Double, _ y: Double) -> BodyPosePoint {
            BodyPosePoint(x: x, y: y, confidence: confidence)
        }
        return BodyPose(timestamp: timestamp, points: [
            .leftShoulder: point(0.5 - shoulderHalfWidth, 0.7),
            .rightShoulder: point(0.5 + shoulderHalfWidth, 0.7),
            .leftWrist: point(armsUp ? 0.38 : 0.4, wristY),
            .rightWrist: point(armsUp ? 0.62 : 0.6, wristY),
            .leftHip: point(0.46, 0.45),
            .rightHip: point(0.54, 0.45),
            .leftAnkle: point(0.5 - ankleHalfSpread, 0.1),
            .rightAnkle: point(0.5 + ankleHalfSpread, 0.1)
        ])
    }

    @Test("Closed, open, closed is one jumping jack")
    func completeCycle() {
        var counter = JumpingJackRepCounter()
        #expect(counter.process(pose(armsUp: false, feetApart: false, at: 0)).status == .ready)
        let open = counter.process(pose(armsUp: true, feetApart: true, at: 0.3))
        #expect(open.status == .open)
        #expect(open.guidance == .jumpIn)
        let closed = counter.process(pose(armsUp: false, feetApart: false, at: 0.6))
        #expect(closed.didCountRep)
        #expect(closed.repetitionCount == 1)
    }

    @Test("Waving the arms without jumping counts nothing")
    func armsOnly() {
        var counter = JumpingJackRepCounter()
        _ = counter.process(pose(armsUp: false, feetApart: false, at: 0))
        for step in 1...6 {
            let output = counter.process(pose(armsUp: step.isMultiple(of: 2), feetApart: false, at: Double(step) * 0.4))
            #expect(!output.didCountRep)
        }
        #expect(counter.repetitionCount == 0)
    }

    @Test("A set waits for arms down and feet together")
    func waitsForStart() {
        var counter = JumpingJackRepCounter()
        let output = counter.process(pose(armsUp: true, feetApart: true, at: 0))
        #expect(output.status == .waitingForStart)
        #expect(output.guidance == .startClosed)
    }

    @Test("Standing side-on is told to face the camera")
    func sideOn() {
        var counter = JumpingJackRepCounter()
        let output = counter.process(pose(armsUp: false, feetApart: false, at: 0, shoulderHalfWidth: 0.02))
        #expect(output.status == .notFacing)
        #expect(output.guidance == .faceCamera)
    }

    @Test("Too fast to be real is rejected")
    func tooFast() {
        var counter = JumpingJackRepCounter()
        _ = counter.process(pose(armsUp: false, feetApart: false, at: 0))
        _ = counter.process(pose(armsUp: true, feetApart: true, at: 0.1))
        let output = counter.process(pose(armsUp: false, feetApart: false, at: 0.2))
        #expect(!output.didCountRep)
        #expect(output.guidance == .slowDown)
    }

    @Test("Low confidence and a missing body are reported")
    func invalid() {
        var counter = JumpingJackRepCounter()
        #expect(counter.process(BodyPose(timestamp: 0, points: [:])).status == .poseLost)
        #expect(counter.process(pose(armsUp: false, feetApart: false, at: 0.1, confidence: 0.1)).status == .lowConfidence)
    }

    @Test("Several clean reps count one each")
    func multipleReps() {
        var counter = JumpingJackRepCounter()
        var time = 0.0
        _ = counter.process(pose(armsUp: false, feetApart: false, at: time))
        for _ in 0..<10 {
            time += 0.3
            _ = counter.process(pose(armsUp: true, feetApart: true, at: time))
            time += 0.3
            _ = counter.process(pose(armsUp: false, feetApart: false, at: time))
        }
        #expect(counter.repetitionCount == 10)
    }
}

@Suite("Lunges on the squat counter")
struct LungeRepCounterTests {
    /// Standing, both legs straight. At the bottom of a lunge the front thigh is level (hip at
    /// knee height) and the back shin lies almost flat.
    private func pose(lunging: Bool, frontLeg: BodySide = .left, at timestamp: TimeInterval) -> BodyPose {
        var points: [BodyJoint: BodyPosePoint] = [:]
        for side in BodySide.allCases {
            let x = side == .left ? 0.45 : 0.55
            let isFront = side == frontLeg
            let ankle: BodyPosePoint
            let knee: BodyPosePoint
            let hipY: Double
            if !lunging {
                ankle = BodyPosePoint(x: x, y: 0.1, confidence: 1)
                knee = BodyPosePoint(x: x, y: 0.3, confidence: 1)
                hipY = 0.52
            } else if isFront {
                ankle = BodyPosePoint(x: x, y: 0.1, confidence: 1)
                knee = BodyPosePoint(x: x, y: 0.3, confidence: 1)
                hipY = 0.31
            } else {
                ankle = BodyPosePoint(x: x, y: 0.1, confidence: 1)
                knee = BodyPosePoint(x: x, y: 0.12, confidence: 1)
                hipY = 0.31
            }
            points[side == .left ? .leftAnkle : .rightAnkle] = ankle
            points[side == .left ? .leftKnee : .rightKnee] = knee
            points[side == .left ? .leftHip : .rightHip] = BodyPosePoint(x: x, y: hipY, confidence: 1)
            points[side == .left ? .leftShoulder : .rightShoulder] = BodyPosePoint(x: x, y: hipY + 0.3, confidence: 1)
        }
        return BodyPose(timestamp: timestamp, points: points)
    }

    @Test("Alternating lunges count one per leg")
    func alternating() {
        var counter = SquatRepCounter(measure: .deepest)
        var time = 0.0
        _ = counter.process(pose(lunging: false, at: time))
        for leg in [BodySide.left, .right, .left, .right] {
            time += 0.5
            #expect(counter.process(pose(lunging: true, frontLeg: leg, at: time)).status == .bottom)
            time += 0.5
            _ = counter.process(pose(lunging: false, at: time))
        }
        #expect(counter.repetitionCount == 4)
    }

    @Test("Averaging both legs, as for squats, would not read a lunge's folded back leg")
    func squatMeasureRejectsLunge() {
        var counter = SquatRepCounter()
        _ = counter.process(pose(lunging: false, at: 0))
        let output = counter.process(pose(lunging: true, at: 0.5))
        #expect(output.status != .bottom)
    }
}

@Suite("Blocking schedule and strict mode")
struct BlockPolicyTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-10-26 is a Monday.
    private func date(day: Int = 26, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test("Windows shorter than an hour or with no days are refused")
    func validation() {
        #expect(BlockSchedule(startMinute: 540, endMinute: 570, weekdays: BlockSchedule.everyDay) == nil)
        #expect(BlockSchedule(startMinute: 540, endMinute: 600, weekdays: []) == nil)
        #expect(BlockSchedule(startMinute: 540, endMinute: 540, weekdays: BlockSchedule.everyDay) == nil)
        #expect(BlockSchedule(startMinute: 540, endMinute: 600, weekdays: [2])?.durationMinutes == 60)
    }

    @Test("A daytime window blocks inside it, on its days only")
    func daytime() throws {
        let schedule = try #require(BlockSchedule(startMinute: 9 * 60, endMinute: 18 * 60, weekdays: BlockSchedule.workdays))
        #expect(!schedule.isBlocking(at: date(8, 59), calendar: calendar))
        #expect(schedule.isBlocking(at: date(9), calendar: calendar))
        #expect(schedule.isBlocking(at: date(17, 59), calendar: calendar))
        #expect(!schedule.isBlocking(at: date(18), calendar: calendar))
        // Sunday 2026-10-25.
        #expect(!schedule.isBlocking(at: date(day: 25, 12), calendar: calendar))
    }

    @Test("A night window belongs to the evening it starts on")
    func overnight() throws {
        // Friday nights only: 2026-10-30 is a Friday.
        let schedule = try #require(BlockSchedule(startMinute: 22 * 60, endMinute: 7 * 60, weekdays: [6]))
        #expect(schedule.crossesMidnight)
        #expect(schedule.isBlocking(at: date(day: 30, 23), calendar: calendar))
        #expect(schedule.isBlocking(at: date(day: 31, 6, 59), calendar: calendar))
        #expect(!schedule.isBlocking(at: date(day: 31, 7), calendar: calendar))
        // Thursday night is not covered, so early Friday is free.
        #expect(!schedule.isBlocking(at: date(day: 30, 3), calendar: calendar))
    }

    @Test("The next change is the next window edge that flips the state")
    func nextChange() throws {
        let schedule = try #require(BlockSchedule(startMinute: 9 * 60, endMinute: 18 * 60, weekdays: BlockSchedule.workdays))
        #expect(schedule.nextChange(after: date(8), calendar: calendar) == date(9))
        #expect(schedule.nextChange(after: date(12), calendar: calendar) == date(18))
        // Friday evening: free until Monday morning.
        #expect(schedule.nextChange(after: date(day: 30, 19), calendar: calendar)
            == calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9)))
    }

    @Test("Strict mode only allows changes that never free an app")
    func strictRules() throws {
        let window = try #require(BlockSchedule(startMinute: 9 * 60, endMinute: 18 * 60, weekdays: BlockSchedule.workdays))
        #expect(StrictMode.allowsScheduleChange(from: window, to: nil))
        #expect(StrictMode.allowsScheduleChange(from: nil, to: nil))
        #expect(!StrictMode.allowsScheduleChange(from: nil, to: window))

        let rule = EarningRule(amountRequired: 1_000, rewardSeconds: 300)
        #expect(StrictMode.allowsRuleChange(from: rule, to: EarningRule(amountRequired: 2_000, rewardSeconds: 300)))
        #expect(StrictMode.allowsRuleChange(from: rule, to: EarningRule(amountRequired: 1_000, rewardSeconds: 120)))
        #expect(!StrictMode.allowsRuleChange(from: rule, to: EarningRule(amountRequired: 500, rewardSeconds: 300)))
        #expect(!StrictMode.allowsRuleChange(from: rule, to: EarningRule(amountRequired: 1_000, rewardSeconds: 600)))
    }

    @Test("Strict mode ends on its date and is capped")
    func strictEnd() {
        let start = date(12)
        var state = SharedState.initial(day: DayKey(date: start, calendar: calendar))
        state.strictModeUntil = StrictMode.endDate(startingAt: start, duration: 30 * 24 * 3_600)
        #expect(state.strictModeUntil == start.addingTimeInterval(StrictMode.maximumDuration))
        #expect(state.isStrictModeActive(at: start))
        #expect(!state.isStrictModeActive(at: start.addingTimeInterval(StrictMode.maximumDuration)))
    }
}
