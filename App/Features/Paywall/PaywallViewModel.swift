import Foundation
import Observation
import RevenueCat

struct PaywallPackage: Identifiable {
    let plan: PaywallPlan
    let package: Package
    let isEligibleForFreeTrial: Bool

    var id: PaywallPlan { plan }
    var price: String { package.storeProduct.localizedPriceString }

    func freeTrialDescription(locale: Locale) -> String? {
        guard isEligibleForFreeTrial,
              let discount = package.storeProduct.introductoryDiscount,
              discount.paymentMode == .freeTrial,
              discount.subscriptionPeriod.unit == .day,
              discount.subscriptionPeriod.value == 3 else { return nil }
        return String(localized: "3-day free trial", locale: locale)
    }
}

struct PaywallAlert: Identifiable {
    enum Kind {
        case purchase
        case entitlementInactive
        case restore
        case noSubscription
    }

    let kind: Kind
    var id: String { String(describing: kind) }
}

@MainActor
@Observable
final class PaywallViewModel {
    private(set) var packages: [PaywallPackage] = []
    private(set) var selectedPackage: PaywallPackage?
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var loadFailed = false
    /// Developer-facing explanation of the last load failure. Populated only in
    /// DEBUG/Sandbox/TestFlight builds so App Store users never see internal detail.
    private(set) var loadDiagnostic: String?
    var alert: PaywallAlert?

    private let subscriptionManager: SubscriptionManager
    private let analytics: any PaywallAnalyticsProtocol
    private var hasTrackedView = false
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    var isProcessing: Bool { isPurchasing || isRestoring }
    var canPurchase: Bool { selectedPackage != nil && !isLoading && !isProcessing }

    init(
        subscriptionManager: SubscriptionManager,
        analytics: any PaywallAnalyticsProtocol = PaywallAnalytics()
    ) {
        self.subscriptionManager = subscriptionManager
        self.analytics = analytics
    }

    func viewAppeared() async {
        if !hasTrackedView {
            hasTrackedView = true
            analytics.track(.paywallViewed)
        }
        // Reappearing after a failed load retries instead of keeping the error forever.
        guard packages.isEmpty, !isLoading else { return }
        await loadOffering()
    }

    func paywallClosed() {
        analytics.track(.paywallClosed)
    }

    /// Starts a fresh load, superseding any in-flight one. A previous attempt stuck on a
    /// hanging StoreKit product request must never make the Retry button a no-op.
    func loadOffering() async {
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()

        isLoading = true
        loadFailed = false
        loadDiagnostic = nil
        packages = []
        selectedPackage = nil

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(generation: generation)
        }
        loadTask = task
        await task.value
    }

    private func performLoad(generation: Int) async {
        do {
            let offerings = try await loadOfferingsWithTimeout()
            // A superseded attempt must not touch state owned by the newer one.
            guard generation == loadGeneration else { return }

            guard let offering = offerings.current else {
                throw PaywallOfferingError.noCurrentOffering(offeringIdentifiers: offerings.all.keys.sorted())
            }
            guard !offering.availablePackages.isEmpty else {
                throw PaywallOfferingError.emptyOffering(identifier: offering.identifier)
            }
            let availableIdentifiers = offering.availablePackages.map(\.identifier)
            guard let monthly = offering.monthly else {
                throw PaywallOfferingError.missingMonthlyPackage(
                    identifier: offering.identifier,
                    available: availableIdentifiers
                )
            }
            guard let yearly = offering.annual else {
                throw PaywallOfferingError.missingAnnualPackage(
                    identifier: offering.identifier,
                    available: availableIdentifiers
                )
            }

            let eligibleProducts = await subscriptionManager.eligibleFreeTrialProductIdentifiers(
                packages: [monthly, yearly]
            )
            guard generation == loadGeneration else { return }

            packages = [
                PaywallPackage(
                    plan: .monthly,
                    package: monthly,
                    isEligibleForFreeTrial: eligibleProducts.contains(monthly.storeProduct.productIdentifier)
                ),
                PaywallPackage(
                    plan: .yearly,
                    package: yearly,
                    isEligibleForFreeTrial: eligibleProducts.contains(yearly.storeProduct.productIdentifier)
                )
            ]
            selectedPackage = packages.first { $0.plan == .yearly }
            isLoading = false
            MonetizationLog.info(
                "Offering '\(offering.identifier)' loaded with products: "
                    + "\(monthly.storeProduct.productIdentifier), \(yearly.storeProduct.productIdentifier)"
            )
        } catch {
            guard generation == loadGeneration else { return }
            loadFailed = true
            isLoading = false
            loadDiagnostic = MonetizationBuild.isSandbox
                ? "\(error.localizedDescription)\n[\(subscriptionManager.configurationSummary)]"
                : nil
            subscriptionManager.record(error, operation: "Load offerings")
        }
    }

    /// RevenueCat waits on Apple's product request, which can hang well past any reasonable
    /// wait when App Store Connect has nothing to return.
    private func loadOfferingsWithTimeout(seconds: Double = 20) async throws -> Offerings {
        guard subscriptionManager.isRevenueCatConfigured else {
            throw PaywallOfferingError.notConfigured(summary: subscriptionManager.configurationSummary)
        }

        return try await withThrowingTaskGroup(of: Offerings.self) { group in
            group.addTask { [subscriptionManager] in
                try await subscriptionManager.loadOfferings()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw PaywallOfferingError.timedOut(seconds: seconds)
            }
            defer { group.cancelAll() }
            guard let offerings = try await group.next() else {
                throw PaywallOfferingError.timedOut(seconds: seconds)
            }
            return offerings
        }
    }

    func selectPackage(_ package: PaywallPackage) {
        guard !isProcessing, selectedPackage?.plan != package.plan else { return }
        selectedPackage = package
        analytics.track(.planSelected(package.plan))
    }

    func purchase() async -> Bool {
        guard canPurchase, let selectedPackage else { return false }
        isPurchasing = true
        analytics.track(.purchaseStarted(selectedPackage.plan))
        defer { isPurchasing = false }

        do {
            let result = try await subscriptionManager.purchase(package: selectedPackage.package)
            if result.userCancelled {
                analytics.track(.purchaseCancelled(selectedPackage.plan))
                return false
            }
            guard subscriptionManager.isPro else {
                throw PaywallConfigurationError.entitlementInactive
            }
            analytics.track(.purchaseCompleted(selectedPackage.plan))
            if selectedPackage.isEligibleForFreeTrial {
                analytics.track(.trialStarted.withProperties([
                    "plan": .string(selectedPackage.plan.rawValue)
                ]))
            }
            analytics.track(.subscriptionStarted.withProperties([
                "plan": .string(selectedPackage.plan.rawValue)
            ]))
            return true
        } catch PaywallConfigurationError.entitlementInactive {
            let error = PaywallConfigurationError.entitlementInactive
            subscriptionManager.record(error, operation: "Purchase entitlement validation")
            analytics.track(.purchaseFailed(selectedPackage.plan))
            alert = PaywallAlert(kind: .entitlementInactive)
            return false
        } catch {
            subscriptionManager.record(error, operation: "Purchase")
            analytics.track(.purchaseFailed(selectedPackage.plan))
            alert = PaywallAlert(kind: .purchase)
            return false
        }
    }

    func restorePurchases() async -> Bool {
        guard !isProcessing else { return false }
        isRestoring = true
        analytics.track(.restoreStarted)
        defer { isRestoring = false }

        do {
            _ = try await subscriptionManager.restorePurchases()
            guard subscriptionManager.isPro else {
                alert = PaywallAlert(kind: .noSubscription)
                return false
            }
            analytics.track(.restoreCompleted)
            return true
        } catch {
            subscriptionManager.record(error, operation: "Restore")
            analytics.track(.restoreFailed)
            alert = PaywallAlert(kind: .restore)
            return false
        }
    }
}

/// Distinguishes the causes of an empty paywall, which otherwise all look identical on
/// device. `emptyOffering` in particular means RevenueCat received the offering but Apple
/// returned no products for it — an App Store Connect problem, not a RevenueCat one.
private enum PaywallOfferingError: LocalizedError {
    case notConfigured(summary: String)
    case noCurrentOffering(offeringIdentifiers: [String])
    case emptyOffering(identifier: String)
    case missingMonthlyPackage(identifier: String, available: [String])
    case missingAnnualPackage(identifier: String, available: [String])
    case timedOut(seconds: Double)

    var errorDescription: String? {
        switch self {
        case let .notConfigured(summary):
            return "RevenueCat is not configured (\(summary))."
        case let .noCurrentOffering(offeringIdentifiers):
            let list = offeringIdentifiers.isEmpty ? "none" : offeringIdentifiers.joined(separator: ", ")
            return "RevenueCat returned no current offering. Offerings received: \(list). "
                + "Mark an offering as Current in the RevenueCat dashboard."
        case let .emptyOffering(identifier):
            return "Offering '\(identifier)' has zero available packages. StoreKit returned no products "
                + "for this bundle: check the Paid Applications Agreement, that both subscriptions are "
                + "at least 'Ready to Submit', and that the product identifiers in RevenueCat match "
                + "App Store Connect exactly."
        case let .missingMonthlyPackage(identifier, available):
            return "Offering '\(identifier)' has no $rc_monthly package. Available: "
                + "\(available.joined(separator: ", "))."
        case let .missingAnnualPackage(identifier, available):
            return "Offering '\(identifier)' has no $rc_annual package. Available: "
                + "\(available.joined(separator: ", "))."
        case let .timedOut(seconds):
            return "Loading offerings timed out after \(Int(seconds))s. StoreKit did not answer the "
                + "product request."
        }
    }
}

private enum PaywallConfigurationError: LocalizedError {
    case entitlementInactive

    var errorDescription: String? {
        switch self {
        case .entitlementInactive:
            return "The purchase completed without activating the RevenueCat '\(Entitlements.pro)' entitlement."
        }
    }
}
