import Foundation

/// The user-facing state of a shield. It describes the earning journey, never whether shields
/// should be applied; that decision remains in `RestrictionCoordinator`.
public enum ShieldState: String, Equatable, Sendable {
    case noTime
    case progress
    case almostThere
    case rewardAvailable
    case sessionExpired
    case dailyGoalCompleted
}

/// A compact, framework-free projection shared by the native shield and the app detail screen.
public struct ShieldViewModel: Equatable, Sendable {
    public let state: ShieldState
    public let availableMinutes: Int
    public let currentSteps: Int
    public let targetSteps: Int
    public let stepsRemaining: Int
    public let progress: Double
    public let estimatedWalkMinutes: Int
    public let rewardMinutes: Int
    public let dailyGoalCompleted: Bool
    public let streak: Int
    public let sessionDurationMinutes: Int?
    public let earnedMinutesToday: Int
    public let consumedMinutesToday: Int
    public let hasActivityData: Bool

    public init(sharedState: SharedState, now: Date = Date()) {
        let ledger = sharedState.ledger
        let milestone = CreditEngine.nextMilestone(in: ledger)
        let amountRequired = max(1, ledger.rule.amountRequired)
        let milestoneSteps = amountRequired - milestone.remainingAmount
        let milestoneProgress = min(1, max(0, Double(milestoneSteps) / Double(amountRequired)))
        let isDailyGoalComplete = ledger.activityAmount >= sharedState.dailyStepGoal
        let availableMinutes = ledger.wallet.availableMinutes

        self.availableMinutes = availableMinutes
        currentSteps = ledger.activityAmount
        targetSteps = milestone.targetAmount
        stepsRemaining = milestone.remainingAmount
        progress = milestoneProgress
        estimatedWalkMinutes = milestone.remainingAmount == 0
            ? 0
            : max(1, Int((Double(milestone.remainingAmount) / 100).rounded()))
        rewardMinutes = milestone.rewardMinutes
        dailyGoalCompleted = isDailyGoalComplete
        streak = sharedState.history.streak(endingOn: ledger.day, including: ledger)
        sessionDurationMinutes = sharedState.currentSession?.durationMinutes
        earnedMinutesToday = ledger.wallet.earnedSeconds / 60
        consumedMinutesToday = ledger.wallet.consumedSeconds / 60
        hasActivityData = sharedState.lastActivitySyncAt != nil

        if let session = sharedState.currentSession,
           session.status == .completed,
           now.timeIntervalSince(session.endsAt) >= 0,
           now.timeIntervalSince(session.endsAt) <= 120 {
            state = .sessionExpired
        } else if availableMinutes > 0 {
            state = .rewardAvailable
        } else if isDailyGoalComplete {
            state = .dailyGoalCompleted
        } else if milestoneProgress >= 0.75 {
            state = .almostThere
        } else if milestoneSteps > 0 {
            state = .progress
        } else {
            state = .noTime
        }
    }
}
