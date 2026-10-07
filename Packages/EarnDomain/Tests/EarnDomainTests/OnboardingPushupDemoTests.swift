import Foundation
import Testing
@testable import EarnDomain

@Suite("Onboarding push-up demo")
struct OnboardingPushupDemoTests {

    /// Walks a demo from the explanation screen to the first counted rep.
    private func counting(at start: TimeInterval = 0) -> OnboardingPushupDemo {
        var demo = OnboardingPushupDemo()
        demo.tryNow()
        demo.cameraReady(at: start)
        demo.observed(bodyVisible: true, at: start + 1)
        for _ in 0..<OnboardingPushupDemo.countdownSeconds { demo.tickCountdown() }
        return demo
    }

    @Test("Continuing without the demo never touches the camera and ends onboarding's demo step")
    func continuesWithoutDemo() {
        var demo = OnboardingPushupDemo()
        #expect(demo.phase == .intro)

        demo.skip()

        #expect(demo.phase == .skipped)
        #expect(demo.isFinished)
        #expect(demo.outcome == .skipped)
        // "Later" is not an abandon: nothing had started.
        #expect(demo.exitReason == nil)
        #expect(demo.repsDetected == 0)
    }

    @Test("Try it now shows the explanation first, never the system prompt")
    func explainsBeforeAsking() {
        var demo = OnboardingPushupDemo()
        demo.tryNow()

        #expect(demo.phase == .cameraExplanation)
        #expect(!demo.hasStarted)
    }

    @Test("Granted permission looks for a body, counts down, then counts reps")
    func permissionGranted() {
        var demo = OnboardingPushupDemo()
        demo.tryNow()
        demo.cameraReady(at: 0)
        #expect(demo.phase == .framing)
        #expect(demo.hasStarted)

        let startedCountdown = demo.observed(bodyVisible: true, at: 1)
        #expect(startedCountdown)
        #expect(demo.phase == .countdown)
        #expect(demo.countdownRemaining == 3)

        let ticks = (0..<3).map { _ in demo.tickCountdown() }
        #expect(ticks == [false, false, true])
        #expect(demo.phase == .counting)
        #expect(demo.countdownRemaining == 0)
    }

    @Test("A body lost during the countdown rewinds to framing instead of counting an empty room")
    func countdownNeedsABody() {
        var demo = OnboardingPushupDemo()
        demo.tryNow()
        demo.cameraReady(at: 0)
        demo.observed(bodyVisible: true, at: 1)

        demo.observed(bodyVisible: false, at: 2)

        #expect(demo.phase == .framing)
        #expect(demo.countdownRemaining == 3)
    }

    @Test("Denied permission stops the demo but leaves onboarding continuable")
    func permissionDenied() {
        var demo = OnboardingPushupDemo()
        demo.tryNow()
        demo.cameraDenied()

        #expect(demo.phase == .permissionDenied)
        #expect(demo.exitReason == .permissionDenied)
        #expect(!demo.isFinished)

        demo.cancel()
        #expect(demo.phase == .skipped)
        #expect(demo.outcome == .skipped)
        // The reason the demo ended survives the exit, for the abandon event.
        #expect(demo.exitReason == .permissionDenied)
    }

    @Test("Cancelling mid-set reports an abandon with the reps already done")
    func cancellation() {
        var demo = counting()
        demo.countRep()

        demo.cancel()

        #expect(demo.phase == .skipped)
        #expect(demo.exitReason == .cancelled)
        #expect(demo.repsDetected == 1)
        #expect(demo.outcome == .skipped)
    }

    @Test("Three reps complete the demo and further reps are ignored")
    func completesAtThreeReps() {
        var demo = counting()

        let reps = (0..<3).map { _ in demo.countRep() }
        #expect(reps == [false, false, true])

        #expect(demo.phase == .completed)
        #expect(demo.repsDetected == OnboardingPushupDemo.targetReps)
        #expect(demo.progress == 1)
        #expect(demo.outcome == .completed)
        #expect(demo.exitReason == nil)

        let extraRep = demo.countRep()
        #expect(!extraRep)
        #expect(demo.repsDetected == OnboardingPushupDemo.targetReps)
    }

    @Test("A demo that finished cannot be cancelled back into a skip")
    func completionIsFinal() {
        var demo = counting()
        for _ in 0..<OnboardingPushupDemo.targetReps { demo.countRep() }

        demo.cancel()

        #expect(demo.phase == .completed)
        #expect(demo.outcome == .completed)
    }

    @Test("Seconds without a body surface help rather than silence")
    func detectionTrouble() {
        var demo = OnboardingPushupDemo()
        demo.tryNow()
        demo.cameraReady(at: 100)

        demo.observed(bodyVisible: false, at: 105)
        #expect(demo.phase == .framing)

        demo.observed(bodyVisible: false, at: 100 + OnboardingPushupDemo.secondsBeforeTrouble)
        #expect(demo.phase == .trouble)
        #expect(demo.exitReason == .detectionFailed)
    }

    @Test("Retrying after trouble restarts the search with a clean counter")
    func retryResetsTheCounter() {
        var demo = counting(at: 0)
        demo.countRep()
        demo.countRep()
        demo.cameraFailed()
        #expect(demo.phase == .cameraError)
        #expect(demo.exitReason == .cameraError)

        demo.retry(at: 50)

        #expect(demo.phase == .framing)
        #expect(demo.repsDetected == 0)
        #expect(demo.countdownRemaining == OnboardingPushupDemo.countdownSeconds)
        #expect(demo.exitReason == nil)
        #expect(demo.progress == 0)

        // The retried search gets its own full grace period before offering help again.
        demo.observed(bodyVisible: false, at: 55)
        #expect(demo.phase == .framing)
        demo.observed(bodyVisible: false, at: 50 + OnboardingPushupDemo.secondsBeforeTrouble)
        #expect(demo.phase == .trouble)
    }

    @Test("A camera error mid-set is recoverable and never completes the demo")
    func detectionError() {
        var demo = counting()
        demo.countRep()

        demo.cameraFailed()

        #expect(demo.phase == .cameraError)
        #expect(demo.outcome == .notAttempted)
        #expect(!demo.isFinished)
    }

    @Test("A device without pose detection is never offered the demo")
    func unsupportedDevice() {
        var demo = OnboardingPushupDemo(isSupported: false)

        demo.tryNow()

        #expect(demo.phase == .intro)
        demo.skip()
        #expect(demo.phase == .skipped)
    }
}
