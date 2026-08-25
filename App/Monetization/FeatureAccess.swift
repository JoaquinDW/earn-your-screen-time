struct FeatureAccess: Equatable {
    let subscriptionStatus: SubscriptionStatus

    var isResolved: Bool { subscriptionStatus != .unknown }
    var isPro: Bool { subscriptionStatus == .pro }

    /// `nil` means there is no product-imposed limit.
    var maxRestrictedApps: Int? { isPro ? nil : 0 }
    var canUseUnlimitedApps: Bool { isPro }
    var canUseCustomRatios: Bool { isPro }
    var canUseWorkoutEarning: Bool { isPro }
    var canUseFocusEarning: Bool { isPro }
    var canUseAdvancedStats: Bool { isPro }

    func allowsRestrictedSelection(count: Int) -> Bool {
        guard let maxRestrictedApps else { return true }
        return count <= maxRestrictedApps
    }
}
