enum AnalyticsPlan: String, Sendable {
    case monthly
    case yearly
}

enum AnalyticsPropertyValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)

    fileprivate var logDescription: String {
        switch self {
        case let .string(value):
            value.debugDescription
        case let .int(value):
            String(value)
        case let .bool(value):
            String(value)
        }
    }
}

typealias AnalyticsProperties = [String: AnalyticsPropertyValue]

struct AnalyticsEvent: Sendable, Equatable {
    let name: String
    private(set) var properties: AnalyticsProperties

    private init(_ name: String, properties: AnalyticsProperties = [:]) {
        self.name = name
        self.properties = properties
    }

    /// Adds developer-defined, privacy-safe metadata. Do not pass identifiers or opaque tokens.
    func withProperties(_ privacySafeProperties: AnalyticsProperties) -> AnalyticsEvent {
        var event = self
        event.properties.merge(privacySafeProperties) { eventValue, _ in eventValue }
        return event
    }

    static let onboardingStarted = AnalyticsEvent("onboarding_started")
    static let scrollTimeSelected = AnalyticsEvent("scroll_time_selected")
    static let currentStepsSelected = AnalyticsEvent("current_steps_selected")
    static let desiredOutcomesSelected = AnalyticsEvent("desired_outcomes_selected")
    static let scienceScreenViewed = AnalyticsEvent("science_screen_viewed")
    static let mechanismUnderstood = AnalyticsEvent("mechanism_understood")
    static let planGenerated = AnalyticsEvent("plan_generated")
    static let thirtyDayProjectionViewed = AnalyticsEvent("30_day_projection_viewed")
    static let thirtyDayProjectionCTA = AnalyticsEvent("30_day_projection_cta")
    static let appsSelected = AnalyticsEvent("apps_selected")
    static let commitmentConfirmed = AnalyticsEvent("commitment_confirmed")
    static let familyControlsRequested = AnalyticsEvent("family_controls_requested")
    static let familyControlsGranted = AnalyticsEvent("family_controls_granted")
    static let healthKitRequested = AnalyticsEvent("healthkit_requested")
    static let healthKitGranted = AnalyticsEvent("healthkit_granted")
    static let personalizedResultViewed = AnalyticsEvent("personalized_result_viewed")
    static let paywallViewed = AnalyticsEvent("paywall_viewed")
    static let trialStarted = AnalyticsEvent("trial_started")
    static let subscriptionStarted = AnalyticsEvent("subscription_started")
    static let onboardingCompleted = AnalyticsEvent("onboarding_completed")
    static let screenTimeEstimateSelected = AnalyticsEvent("screen_time_estimate_selected")
    static let primaryGoalSelected = AnalyticsEvent("primary_goal_selected")
    static let healthKitPermissionDenied = AnalyticsEvent("healthkit_permission_denied")
    static let baselineCalculated = AnalyticsEvent("baseline_calculated")
    static let baselineSelfReported = AnalyticsEvent("baseline_self_reported")
    static let recommendedGoalCreated = AnalyticsEvent("recommended_goal_created")
    static let starterPlanViewed = AnalyticsEvent("starter_plan_viewed")
    static let starterPlanCustomized = AnalyticsEvent("starter_plan_customized")
    static let starterPlanAccepted = AnalyticsEvent("starter_plan_accepted")
    static let firstEarnStarted = AnalyticsEvent("first_earn_started")
    static let firstRewardEarned = AnalyticsEvent("first_reward_earned")
    static let goalIncreaseRecommended = AnalyticsEvent("goal_increase_recommended")
    static let goalIncreaseAccepted = AnalyticsEvent("goal_increase_accepted")
    static let goalIncreaseRejected = AnalyticsEvent("goal_increase_rejected")
    static let goalDecreaseRecommended = AnalyticsEvent("goal_decrease_recommended")
    static let goalDecreaseAccepted = AnalyticsEvent("goal_decrease_accepted")
    static let goalDecreaseRejected = AnalyticsEvent("goal_decrease_rejected")
    static let earnScreenOpenedFromShield = AnalyticsEvent("earn_screen_opened_from_shield")
    static let rewardCompleted = AnalyticsEvent("reward_completed")
    static let dailyGoalCompleted = AnalyticsEvent("daily_goal_completed")
    static let sessionStarted = AnalyticsEvent("session_started")
    static let sessionExpired = AnalyticsEvent("session_expired")
    static let walletCreated = AnalyticsEvent("wallet_created")
    static let minutesEarned = AnalyticsEvent("minutes_earned")
    static let minutesConsumed = AnalyticsEvent("minutes_consumed")
    static let minutesSaved = AnalyticsEvent("minutes_saved")
    static let walletEmpty = AnalyticsEvent("wallet_empty")
    static let walletCapReached = AnalyticsEvent("wallet_cap_reached")
    static let unlockAttemptWithoutBalance = AnalyticsEvent("unlock_attempt_without_balance")
    static let sessionPaused = AnalyticsEvent("session_paused")

    static let paywallClosed = AnalyticsEvent("paywall_closed")
    static func planSelected(_ plan: AnalyticsPlan) -> AnalyticsEvent {
        AnalyticsEvent("plan_selected", properties: ["plan": .string(plan.rawValue)])
    }

    static func purchaseStarted(_ plan: AnalyticsPlan) -> AnalyticsEvent {
        AnalyticsEvent("purchase_started", properties: ["plan": .string(plan.rawValue)])
    }

    static func purchaseCompleted(_ plan: AnalyticsPlan) -> AnalyticsEvent {
        AnalyticsEvent("purchase_completed", properties: ["plan": .string(plan.rawValue)])
    }

    static func purchaseCancelled(_ plan: AnalyticsPlan) -> AnalyticsEvent {
        AnalyticsEvent("purchase_cancelled", properties: ["plan": .string(plan.rawValue)])
    }

    static func purchaseFailed(_ plan: AnalyticsPlan) -> AnalyticsEvent {
        AnalyticsEvent("purchase_failed", properties: ["plan": .string(plan.rawValue)])
    }

    static let restoreStarted = AnalyticsEvent("restore_started")
    static let restoreCompleted = AnalyticsEvent("restore_completed")
    static let restoreFailed = AnalyticsEvent("restore_failed")

    var plan: AnalyticsPlan? {
        guard case let .string(rawValue) = properties["plan"] else { return nil }
        return AnalyticsPlan(rawValue: rawValue)
    }

    var logProperties: String {
        properties.keys.sorted().compactMap { key in
            properties[key].map { "\(key)=\($0.logDescription)" }
        }.joined(separator: " ")
    }
}
