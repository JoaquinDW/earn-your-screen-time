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
              discount.paymentMode == .freeTrial else { return nil }
        let period = discount.subscriptionPeriod
        switch period.unit {
        case .day:
            return String(localized: "paywall.trial.days \(period.value)", locale: locale)
        case .week:
            return String(localized: "paywall.trial.weeks \(period.value)", locale: locale)
        case .month:
            return String(localized: "paywall.trial.months \(period.value)", locale: locale)
        case .year:
            return String(localized: "paywall.trial.years \(period.value)", locale: locale)
        @unknown default: return nil
        }
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
    var alert: PaywallAlert?

    private let subscriptionManager: SubscriptionManager
    private let analytics: any PaywallAnalyticsProtocol
    private var hasLoaded = false

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
        guard !hasLoaded else { return }
        hasLoaded = true
        analytics.track(.paywallViewed)
        await loadOffering()
    }

    func paywallClosed() {
        analytics.track(.paywallClosed)
    }

    func loadOffering() async {
        guard !isLoading else { return }
        isLoading = true
        loadFailed = false
        packages = []
        selectedPackage = nil
        defer { isLoading = false }

        do {
            let offerings = try await subscriptionManager.loadOfferings()
            guard let offering = offerings.current,
                  !offering.availablePackages.isEmpty,
                  let monthly = offering.monthly,
                  let yearly = offering.annual else {
                throw PaywallConfigurationError.missingPackages
            }

            let eligibleProducts = await subscriptionManager.eligibleFreeTrialProductIdentifiers(
                packages: [monthly, yearly]
            )
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
        } catch {
            loadFailed = true
            subscriptionManager.record(error, operation: "Load offerings")
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

private enum PaywallConfigurationError: LocalizedError {
    case missingPackages
    case entitlementInactive

    var errorDescription: String? {
        switch self {
        case .missingPackages:
            return "The current RevenueCat offering is missing its monthly or annual package."
        case .entitlementInactive:
            return "The purchase completed without activating the RevenueCat '\(Entitlements.pro)' entitlement."
        }
    }
}
