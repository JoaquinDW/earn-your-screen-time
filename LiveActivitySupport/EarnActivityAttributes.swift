import ActivityKit
import Foundation

struct EarnActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum PresentationState: Codable, Hashable {
            case normal
            case earned(minutes: Int)
            case unlocked
            case goalCompleted
            case balanceExpired
        }

        var dayKey: String
        var steps: Int
        var nextMilestoneTarget: Int
        var dailyGoalTarget: Int
        var availableMinutes: Int
        var earnedMinutesToday: Int
        var nextRewardMinutes: Int
        /// Size of the current earning interval. Optional so activities created by an older build
        /// keep decoding and can fall back to absolute progress.
        var milestoneStepAmount: Int? = nil
        var activeSessionEndsAt: Date?
        var localeIdentifier: String
        var presentation: PresentationState

        var stepsRemaining: Int {
            max(0, nextMilestoneTarget - steps)
        }

        var milestoneProgress: Double {
            guard nextMilestoneTarget > 0 else { return 0 }
            guard let milestoneStepAmount, milestoneStepAmount > 0 else {
                return min(1, max(0, Double(steps) / Double(nextMilestoneTarget)))
            }
            let start = nextMilestoneTarget - milestoneStepAmount
            return min(1, max(0, Double(steps - start) / Double(milestoneStepAmount)))
        }
    }

    let schemaVersion: Int

    init(schemaVersion: Int = 1) {
        self.schemaVersion = schemaVersion
    }
}
