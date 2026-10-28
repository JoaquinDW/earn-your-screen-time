import Foundation

/// Decides when to ask for an App Store rating.
///
/// Apple's guidance is to ask right after a moment of success, never mid-task. The first version
/// waited for three unlocks and two days, and asked once per install: of 77 installs in its first
/// 60 days, 2 people qualified. This one asks at the moment someone has just earned or spent
/// minutes, as soon as they have used a real unlock, and tries once more two weeks later because
/// iOS may silently skip a request.
public enum ReviewPromptPolicy {
    /// What just happened. Each one is a small win the person can feel.
    public enum Moment: String, Sendable {
        /// A session started with earned minutes. The count passed in already includes it.
        case unlockStarted
        /// Minutes earned by push-ups, another camera exercise or a study session.
        case activeRewardEarned
        /// The day's step goal reached.
        case dailyGoalCompleted
    }

    public static let maximumRequests = 2
    public static let minimumIntervalBetweenRequests: TimeInterval = 14 * 24 * 60 * 60

    public static func shouldRequest(
        at moment: Moment,
        in state: SharedState,
        now: Date = Date()
    ) -> Bool {
        guard state.onboardingCompleted,
              state.reviewPromptRequestCount < maximumRequests
        else { return false }
        if let last = state.lastReviewPromptRequestedAt,
           now.timeIntervalSince(last) < minimumIntervalBetweenRequests {
            return false
        }
        // The first unlock of a free user ends in the paywall, so the unlock that earns a
        // prompt is the second. An earning moment only needs one unlock behind it: the person
        // has already seen the block lift once.
        let requiredUnlocks = moment == .unlockStarted ? 2 : 1
        return state.successfulUnlockCount >= requiredUnlocks
    }
}
