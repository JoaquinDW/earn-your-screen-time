struct FeatureAccess: Equatable {
    let subscriptionStatus: SubscriptionStatus
    /// A free user who has not yet spent the one unlock that precedes the paywall. They need
    /// protected apps for that unlock to mean anything.
    var isFreePreview = false
    /// Someone who has not paid gets one push-up reward (enforced per account on the server).
    var hasFreePushupsReward = false

    var isResolved: Bool { subscriptionStatus != .unknown }
    var isPro: Bool { subscriptionStatus == .pro }

    /// `nil` means there is no product-imposed limit.
    var maxRestrictedApps: Int? { isPro || isFreePreview ? nil : 0 }
    var canUseUnlimitedApps: Bool { isPro || isFreePreview }
    var canUseCustomRatios: Bool { isPro }
    var canUseWorkoutEarning: Bool { isPro || hasFreePushupsReward }
    var canUseFocusEarning: Bool { isPro }
    var canUseAdvancedStats: Bool { isPro }

    func allowsRestrictedSelection(count: Int) -> Bool {
        guard let maxRestrictedApps else { return true }
        return count <= maxRestrictedApps
    }
}
