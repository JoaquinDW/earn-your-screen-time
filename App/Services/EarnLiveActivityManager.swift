import ActivityKit
import Foundation
import os

@MainActor
final class EarnLiveActivityManager {
    struct Snapshot: Equatable {
        var isEligible: Bool
        var dayKey: String
        var steps: Int
        var nextMilestoneTarget: Int
        var dailyGoalTarget: Int
        var availableMinutes: Int
        var earnedMinutesToday: Int
        var nextRewardMinutes: Int
        var milestoneStepAmount: Int
        var activeSessionEndsAt: Date?
        var localeIdentifier: String

        func content(
            presentation: EarnActivityAttributes.ContentState.PresentationState = .normal
        ) -> EarnActivityAttributes.ContentState {
            EarnActivityAttributes.ContentState(
                dayKey: dayKey,
                steps: steps,
                nextMilestoneTarget: nextMilestoneTarget,
                dailyGoalTarget: dailyGoalTarget,
                availableMinutes: availableMinutes,
                earnedMinutesToday: earnedMinutesToday,
                nextRewardMinutes: nextRewardMinutes,
                milestoneStepAmount: milestoneStepAmount,
                activeSessionEndsAt: activeSessionEndsAt,
                localeIdentifier: localeIdentifier,
                presentation: presentation
            )
        }
    }

    private static let transientDuration: Duration = .seconds(8)
    private static let transientTimeInterval: TimeInterval = 8
    private let logger = Logger(subsystem: "com.balthasardeweert.earnyourscreentime", category: "LiveActivity")
    private var latestSnapshot: Snapshot?
    private var operationTail: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    private var transientEndsAt: Date?

    func synchronize(
        _ snapshot: Snapshot,
        presentation: EarnActivityAttributes.ContentState.PresentationState? = nil
    ) {
        latestSnapshot = snapshot

        guard snapshot.isEligible else {
            restoreTask?.cancel()
            transientEndsAt = nil
            enqueue { [weak self] in await self?.endAll(using: snapshot) }
            return
        }

        if let presentation, presentation != .normal {
            let expiresAt = Date().addingTimeInterval(Self.transientTimeInterval)
            transientEndsAt = expiresAt
            enqueue { [weak self] in
                await self?.apply(snapshot, presentation: presentation, staleDate: expiresAt)
            }
            scheduleRestore()
            return
        }

        if let transientEndsAt, transientEndsAt > Date() {
            return
        }

        reconcilePersistentState(using: snapshot)
    }

    private func scheduleRestore() {
        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            try? await Task.sleep(for: Self.transientDuration)
            guard !Task.isCancelled, let self, let snapshot = self.latestSnapshot else { return }
            self.transientEndsAt = nil
            self.reconcilePersistentState(using: snapshot)
        }
    }

    private func reconcilePersistentState(using snapshot: Snapshot) {
        enqueue { [weak self] in
            guard let self else { return }
            if snapshot.isEligible, snapshot.activeSessionEndsAt.map({ $0 > Date() }) == true {
                await self.apply(snapshot, presentation: .normal, staleDate: snapshot.activeSessionEndsAt)
            } else {
                await self.endAll(using: snapshot)
            }
        }
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = operationTail
        operationTail = Task {
            await previous?.value
            await operation()
        }
    }

    private func apply(
        _ snapshot: Snapshot,
        presentation: EarnActivityAttributes.ContentState.PresentationState,
        staleDate: Date?
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let contentState = snapshot.content(presentation: presentation)
        let activities = Activity<EarnActivityAttributes>.activities
        if let activity = activities.first {
            for duplicate in activities.dropFirst() {
                await duplicate.end(
                    ActivityContent(state: contentState, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }

            guard activity.content.state != contentState || activity.content.staleDate != staleDate else { return }
            await activity.update(ActivityContent(
                state: contentState,
                staleDate: staleDate,
                relevanceScore: presentation == .normal ? 50 : 100
            ))
            return
        }

        do {
            _ = try Activity.request(
                attributes: EarnActivityAttributes(),
                content: ActivityContent(
                    state: contentState,
                    staleDate: staleDate,
                    relevanceScore: presentation == .normal ? 50 : 100
                ),
                pushType: nil
            )
        } catch {
            #if DEBUG
            logger.debug("Unable to start Live Activity: \(String(describing: error), privacy: .public)")
            #endif
        }
    }

    private func endAll(using snapshot: Snapshot) async {
        let finalState = snapshot.content()
        for activity in Activity<EarnActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }
}
