import Foundation

/// How the optional push-up demo inside onboarding ended, persisted so the demo can be
/// offered again later and never twice by accident.
public enum OnboardingPushupDemoOutcome: String, Codable, Equatable, Sendable {
    /// The user has not reached the demo, or left onboarding before answering it.
    case notAttempted
    /// The user chose "I'll do it later", cancelled, or ran into an error. Still offerable.
    case skipped
    case completed
}

/// The optional "Push-ups to Earn" demonstration inside onboarding.
///
/// Deliberately free of camera, network and reward code. The demo must never create a real
/// balance, and every path through it has to be reachable from a test, so the app layer owns
/// the capture session and feeds this three facts: whether a body is visible, that a rep was
/// counted, and that something failed.
public struct OnboardingPushupDemo: Equatable, Sendable {
    /// Three is the whole promise. A demo long enough to fail at is not a demo.
    public static let targetReps = 3
    public static let countdownSeconds = 3
    /// How long the camera may look for a body before the demo offers help instead of silence.
    public static let secondsBeforeTrouble: TimeInterval = 10

    public enum Phase: Equatable, Sendable {
        /// The value proposition. No permission has been asked for yet.
        case intro
        /// Why the camera is needed, shown before the system prompt.
        case cameraExplanation
        /// The camera is live and looking for a body.
        case framing
        case countdown
        case counting
        /// Several seconds with no body found: tips, retry, or leave.
        case trouble
        case completed
        case permissionDenied
        case cameraError
        /// The user continued onboarding without the demo.
        case skipped
    }

    /// Why a demo that had already started ended without three reps.
    public enum ExitReason: String, Equatable, Sendable {
        case cancelled
        case permissionDenied
        case cameraError
        case detectionFailed
    }

    /// `false` on a device whose front camera cannot run pose detection. The intro then
    /// promises nothing it cannot deliver and only offers Continue.
    public let isSupported: Bool
    public private(set) var phase: Phase
    public private(set) var repsDetected: Int
    public private(set) var countdownRemaining: Int
    /// Why an already-started demo ended without three reps. `nil` when nothing was abandoned,
    /// which is what separates "I'll do it later" from walking out of a running demo.
    public private(set) var exitReason: ExitReason?
    /// When the current search for a body began, in the caller's timebase.
    private var searchingSince: TimeInterval?

    public init(isSupported: Bool = true) {
        self.isSupported = isSupported
        phase = .intro
        repsDetected = 0
        countdownRemaining = Self.countdownSeconds
    }

    /// Onboarding may move on: the demo is either done or deliberately behind us.
    public var isFinished: Bool { phase == .completed || phase == .skipped }

    /// True once the camera has been asked for, which is what makes an exit an *abandon*
    /// rather than a plain "later".
    public var hasStarted: Bool {
        switch phase {
        case .intro, .cameraExplanation, .skipped: false
        default: true
        }
    }

    public var progress: Double {
        Double(min(repsDetected, Self.targetReps)) / Double(Self.targetReps)
    }

    public var outcome: OnboardingPushupDemoOutcome {
        switch phase {
        case .completed: .completed
        case .skipped: .skipped
        default: .notAttempted
        }
    }

    /// "Try it now". Only the explanation follows — never the system prompt directly.
    public mutating func tryNow() {
        guard phase == .intro, isSupported else { return }
        phase = .cameraExplanation
    }

    /// Camera access was granted and the preview is live.
    public mutating func cameraReady(at time: TimeInterval) {
        guard phase == .cameraExplanation else { return }
        beginFraming(at: time)
    }

    public mutating func cameraDenied() {
        guard phase == .cameraExplanation || phase == .framing else { return }
        phase = .permissionDenied
        exitReason = .permissionDenied
    }

    public mutating func cameraFailed() {
        guard !isFinished, phase != .permissionDenied else { return }
        phase = .cameraError
        exitReason = .cameraError
    }

    /// Feeds the framing and countdown phases. Returns `true` when the countdown just began.
    @discardableResult
    public mutating func observed(bodyVisible: Bool, at time: TimeInterval) -> Bool {
        switch phase {
        case .framing:
            guard bodyVisible else {
                if let searchingSince, time - searchingSince >= Self.secondsBeforeTrouble {
                    phase = .trouble
                    exitReason = .detectionFailed
                }
                return false
            }
            searchingSince = nil
            countdownRemaining = Self.countdownSeconds
            phase = .countdown
            return true
        case .countdown:
            // Losing the body before the set begins rewinds to framing rather than counting
            // down at an empty room.
            guard !bodyVisible else { return false }
            beginFraming(at: time)
            return false
        default:
            return false
        }
    }

    /// One second of the pre-set countdown. Returns `true` when counting has begun.
    @discardableResult
    public mutating func tickCountdown() -> Bool {
        guard phase == .countdown else { return false }
        countdownRemaining = max(0, countdownRemaining - 1)
        guard countdownRemaining == 0 else { return false }
        phase = .counting
        return true
    }

    /// Returns `true` when this repetition was the third and the demo is done.
    @discardableResult
    public mutating func countRep() -> Bool {
        guard phase == .counting, repsDetected < Self.targetReps else { return false }
        repsDetected += 1
        guard repsDetected == Self.targetReps else { return false }
        phase = .completed
        return true
    }

    /// Leaving the demo on purpose — from the prep screen, mid-set, or an error screen.
    /// Whatever already went wrong keeps its reason; a clean walk-out reports `cancelled`.
    public mutating func cancel() {
        guard !isFinished else { return }
        if exitReason == nil, hasStarted { exitReason = .cancelled }
        phase = .skipped
    }

    /// "I'll do it later", from the intro. Nothing was started, so nothing was abandoned.
    public mutating func skip() {
        guard !isFinished else { return }
        phase = .skipped
    }

    /// Another attempt after the camera lost its way. The counter starts over at zero.
    public mutating func retry(at time: TimeInterval) {
        guard phase == .trouble || phase == .cameraError else { return }
        beginFraming(at: time)
    }

    private mutating func beginFraming(at time: TimeInterval) {
        phase = .framing
        repsDetected = 0
        countdownRemaining = Self.countdownSeconds
        searchingSince = time
        exitReason = nil
    }
}
