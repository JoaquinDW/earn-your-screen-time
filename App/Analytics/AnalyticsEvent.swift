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
    static let sessionStarted = AnalyticsEvent("screen_time_session_started")
    static let sessionExpired = AnalyticsEvent("screen_time_session_completed")
    static let walletCreated = AnalyticsEvent("wallet_created")
    static let minutesEarned = AnalyticsEvent("minutes_earned")
    static let minutesConsumed = AnalyticsEvent("minutes_consumed")
    static let minutesSaved = AnalyticsEvent("minutes_saved")
    static let walletEmpty = AnalyticsEvent("screen_time_wallet_empty")
    static let walletCapReached = AnalyticsEvent("wallet_cap_reached")
    static let unlockAttemptWithoutBalance = AnalyticsEvent("unlock_attempt_without_balance")
    static let sessionPaused = AnalyticsEvent("screen_time_session_ended_early")
    static let sessionTimeReturned = AnalyticsEvent("screen_time_session_time_returned")
    static let studyToEarnOpened = AnalyticsEvent("study_to_earn_opened")
    static let studyScanStarted = AnalyticsEvent("study_scan_started")
    static let studyScanCaptured = AnalyticsEvent("study_scan_captured")
    static let studyOCRSucceeded = AnalyticsEvent("study_ocr_succeeded")
    static let studyOCRFailed = AnalyticsEvent("study_ocr_failed")
    static let studyQuestionGenerated = AnalyticsEvent("study_question_generated")
    static let studyQuestionRegenerated = AnalyticsEvent("study_question_regenerated")
    static let studyAnswerSubmitted = AnalyticsEvent("study_answer_submitted")
    static let studyAnswerPassed = AnalyticsEvent("study_answer_passed")
    static let studyAnswerFailed = AnalyticsEvent("study_answer_failed")
    static let studyRewardGranted = AnalyticsEvent("study_reward_granted")
    static let studyDailyCapReached = AnalyticsEvent("study_daily_cap_reached")
    static let studyFlowAbandoned = AnalyticsEvent("study_flow_abandoned")
    static let pushupsIntroShown = AnalyticsEvent("pushups_intro_shown")
    static let pushupsIntroAccepted = AnalyticsEvent("pushups_intro_accepted")
    static let pushupsIntroDismissed = AnalyticsEvent("pushups_intro_dismissed")
    static let pushupsEntryTapped = AnalyticsEvent("pushups_entry_tapped")
    static let pushupsToEarnOpened = AnalyticsEvent("pushups_to_earn_opened")
    static let pushupsChallengeSelected = AnalyticsEvent("pushups_challenge_selected")
    static let pushupsCameraPermissionRequested = AnalyticsEvent("pushups_camera_permission_requested")
    static let pushupsCameraPermissionGranted = AnalyticsEvent("pushups_camera_permission_granted")
    static let pushupsSetupCompleted = AnalyticsEvent("pushups_setup_completed")
    static let pushupsSessionStarted = AnalyticsEvent("pushups_session_started")
    static let pushupsPoseDetected = AnalyticsEvent("pushups_pose_detected")
    static let pushupsPoseLost = AnalyticsEvent("pushups_pose_lost")
    static let pushupsRepCounted = AnalyticsEvent("pushups_rep_counted")
    static let pushupsSessionCompleted = AnalyticsEvent("pushups_session_completed")
    static let pushupsRewardClaimed = AnalyticsEvent("pushups_reward_claimed")
    static let pushupsRewardRejected = AnalyticsEvent("pushups_reward_rejected")
    static let pushupsDailyCapReached = AnalyticsEvent("pushups_daily_cap_reached")
    static let pushupsSessionAbandoned = AnalyticsEvent("pushups_session_abandoned")
    /// Switching between push-ups and squats. The `pushups_*` events above predate squats and
    /// cover both; each carries an `exercise` property.
    static let exerciseSelected = AnalyticsEvent("exercise_selected")

    // The optional push-up demo inside onboarding. Kept separate from the `pushups_*` events
    // above because the demo grants nothing: mixing them would pollute the earning funnel.
    static let onboardingPushupsIntroViewed = AnalyticsEvent("onboarding_pushups_intro_viewed")
    static let onboardingPushupsTryNowTapped = AnalyticsEvent("onboarding_pushups_try_now_tapped")
    static let onboardingPushupsLaterTapped = AnalyticsEvent("onboarding_pushups_later_tapped")
    static let onboardingCameraExplanationViewed = AnalyticsEvent("onboarding_camera_explanation_viewed")
    static let onboardingCameraPermissionRequested = AnalyticsEvent("onboarding_camera_permission_requested")
    static let onboardingCameraPermissionGranted = AnalyticsEvent("onboarding_camera_permission_granted")
    static let onboardingCameraPermissionDenied = AnalyticsEvent("onboarding_camera_permission_denied")
    static let onboardingPushupsDemoStarted = AnalyticsEvent("onboarding_pushups_demo_started")
    static let onboardingPushupsRepDetected = AnalyticsEvent("onboarding_pushups_rep_detected")
    static let onboardingPushupsDemoCompleted = AnalyticsEvent("onboarding_pushups_demo_completed")
    static let onboardingPushupsDemoAbandoned = AnalyticsEvent("onboarding_pushups_demo_abandoned")
    static let onboardingPushupsDemoError = AnalyticsEvent("onboarding_pushups_demo_error")
    static let onboardingContinueWithoutDemo = AnalyticsEvent("onboarding_continue_without_demo")
    static let onboardingScreenTimePermissionRequested =
        AnalyticsEvent("onboarding_screen_time_permission_requested")
    static let firstAppBlocked = AnalyticsEvent("first_app_blocked")
    static let firstRealUnlockCompleted = AnalyticsEvent("first_real_unlock_completed")
    static let reviewPromptRequested = AnalyticsEvent("review_prompt_requested")
    static let rateAppTapped = AnalyticsEvent("rate_app_tapped")

    static let paywallClosed = AnalyticsEvent("paywall_closed")
    /// The offering finished loading, so what the person was actually offered is known.
    static let paywallOfferLoaded = AnalyticsEvent("paywall_offer_loaded")
    static let paywallCancelNudgeShown = AnalyticsEvent("paywall_cancel_nudge_shown")
    static let familyControlsDenied = AnalyticsEvent("family_controls_denied")
    static let onboardingPushupsDemoTrouble = AnalyticsEvent("onboarding_pushups_demo_trouble")
    static let onboardingBackTapped = AnalyticsEvent("onboarding_back_tapped")

    /// The first reward someone earned by doing something (push-ups, study). `first_reward_earned`
    /// stays as it was, but it fires whenever HealthKit credits steps in the background, even
    /// mid-onboarding, so it cannot answer "did this person engage?".
    static let firstActiveRewardEarned = AnalyticsEvent("first_active_reward_earned")
    /// Fired once per local calendar day the app comes to the foreground. Retention reads this
    /// instead of SDK lifecycle events, which carry neither onboarding state nor day counts.
    static let appActiveDay = AnalyticsEvent("app_active_day")
    /// The protected-app selection changed size. `new_count == 0` is someone switching Earnit off.
    static let restrictedAppsChanged = AnalyticsEvent("restricted_apps_changed")
    /// One event for every Settings control, told apart by its `action` property.
    static let settingsAction = AnalyticsEvent("settings_action")
    static let notificationsPromptViewed = AnalyticsEvent("notifications_prompt_viewed")
    static let notificationsPromptSkipped = AnalyticsEvent("notifications_prompt_skipped")
    static let notificationsPermissionRequested = AnalyticsEvent("notifications_permission_requested")
    static let notificationsPermissionGranted = AnalyticsEvent("notifications_permission_granted")
    static let notificationsPermissionDenied = AnalyticsEvent("notifications_permission_denied")
    /// Someone opened the app by tapping a local notification; `kind` names which one.
    static let notificationOpened = AnalyticsEvent("notification_opened")

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

    static func screenViewed(_ screen: String) -> AnalyticsEvent {
        // "$screen_name" is PostHog's reserved property for mobile screen views; using it (instead
        // of a plain custom key) is what populates the "URL / Screen" column in PostHog's Activity view.
        AnalyticsEvent("screen_viewed", properties: ["$screen_name": .string(screen)])
    }

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
