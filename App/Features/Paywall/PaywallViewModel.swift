import Foundation
import Observation
import RevenueCat

struct PaywallPackage: Identifiable {
    let plan: PaywallPlan
    let package: Package
    let isEligibleForFreeTrial: Bool

    var id: PaywallPlan { plan }
    var price: String { package.storeProduct.localizedPriceString }
    /// "$0.00" in the storefront's own currency, for the trial's "due today" line.
    var zeroPrice: String {
        package.storeProduct.priceFormatter?.string(from: 0) ?? "0"
    }

    func monthlyEquivalentPrice() -> String? {
        guard plan == .yearly,
              let formatter = package.storeProduct.priceFormatter?.copy() as? NumberFormatter else {
            return nil
        }
        let monthlyPrice = NSDecimalNumber(decimal: package.storeProduct.price)
            .dividing(by: NSDecimalNumber(value: 12))
        formatter.maximumFractionDigits = 2
        return formatter.string(from: monthlyPrice)
    }

    func freeTrialDescription(locale: Locale) -> String? {
        guard isEligibleForFreeTrial,
              let discount = package.storeProduct.introductoryDiscount,
              discount.paymentMode == .freeTrial,
              discount.subscriptionPeriod.unit == .day,
              discount.subscriptionPeriod.value == 3 else { return nil }
        return Self.localized("3-day free trial", locale: locale)
    }

    static func localized(_ key: String, locale: Locale) -> String {
        let identifiers = [
            locale.identifier.replacingOccurrences(of: "_", with: "-"),
            locale.language.languageCode?.identifier
        ].compactMap { $0 }

        for identifier in identifiers {
            if let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle.localizedString(forKey: key, value: key, table: nil)
            }
        }
        return key
    }
}

/// Where the paywall was opened from, reported on every paywall event so conversion can be
/// read per entry point.
enum PaywallSource: String {
    /// The paywall after the free unlock's session has ended. It can be closed; closing it only
    /// lasts until the app next goes to the background.
    case firstUnlock = "first_unlock"
    /// Someone who closed that paywall tried to spend minutes again.
    case unlockAttempt = "unlock_attempt"
    /// Protecting apps beyond the free allowance.
    case appSelection = "app_selection"
    /// Push-ups after the one free push-up reward has been used.
    case pushups
    case study
    case settings
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
    /// Shown after someone backs out of Apple's purchase sheet: price surprise at that sheet is
    /// the one objection the paywall can still answer.
    private(set) var showsCancelNudge = false

    private let subscriptionManager: SubscriptionManager
    private let analytics: any PaywallAnalyticsProtocol
    private let source: PaywallSource
    private var hasTrackedView = false
    /// A successful purchase must not be repeatable from the same screen: a second tap while the
    /// paywall is dismissing used to replay the whole purchase and double-report it.
    private var hasActivated = false
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    var isProcessing: Bool { isPurchasing || isRestoring }
    var canPurchase: Bool { selectedPackage != nil && !isLoading && !isProcessing && !hasActivated }
    var trialPackage: PaywallPackage? { packages.first(where: \.isEligibleForFreeTrial) }

    init(
        subscriptionManager: SubscriptionManager,
        source: PaywallSource,
        analytics: any PaywallAnalyticsProtocol = PaywallAnalytics()
    ) {
        self.subscriptionManager = subscriptionManager
        self.source = source
        self.analytics = analytics
    }

    func viewAppeared() async {
        if !hasTrackedView {
            hasTrackedView = true
            analytics.track(.paywallViewed.withProperties(context))
        }
        // Reappearing after a failed load retries instead of keeping the error forever.
        guard packages.isEmpty, !isLoading else { return }
        await loadOffering()
    }

    func paywallClosed() {
        analytics.track(.paywallClosed.withProperties(context))
    }

    /// Properties shared by every paywall event. Prices are the localized App Store strings,
    /// which identify a storefront, never a person.
    private var context: AnalyticsProperties {
        var properties: AnalyticsProperties = ["source": .string(source.rawValue)]
        if let selectedPackage {
            properties["trial_eligible"] = .bool(selectedPackage.isEligibleForFreeTrial)
            properties["price"] = .string(selectedPackage.price)
        }
        return properties
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
            analytics.track(.paywallOfferLoaded.withProperties([
                "source": .string(source.rawValue),
                "trial_eligible_monthly": .bool(packages[0].isEligibleForFreeTrial),
                "trial_eligible_yearly": .bool(packages[1].isEligibleForFreeTrial),
                "price_monthly": .string(packages[0].price),
                "price_yearly": .string(packages[1].price)
            ]))
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
        analytics.track(.planSelected(package.plan).withProperties(context))
    }

    func purchase() async -> Bool {
        guard canPurchase, let selectedPackage else { return false }
        isPurchasing = true
        showsCancelNudge = false
        let context = context
        analytics.track(.purchaseStarted(selectedPackage.plan).withProperties(context))
        defer { isPurchasing = false }

        do {
            let result = try await subscriptionManager.purchase(package: selectedPackage.package)
            if result.userCancelled {
                analytics.track(.purchaseCancelled(selectedPackage.plan).withProperties(context))
                offerTrialAfterCancel()
                return false
            }
            guard subscriptionManager.isPro else {
                throw PaywallConfigurationError.entitlementInactive
            }
            hasActivated = true
            analytics.track(.purchaseCompleted(selectedPackage.plan).withProperties(context))
            let planContext = context.merging(["plan": .string(selectedPackage.plan.rawValue)]) { current, _ in current }
            if selectedPackage.isEligibleForFreeTrial {
                analytics.track(.trialStarted.withProperties(planContext))
            }
            analytics.track(.subscriptionStarted.withProperties(planContext))
            return true
        } catch PaywallConfigurationError.entitlementInactive {
            let error = PaywallConfigurationError.entitlementInactive
            subscriptionManager.record(error, operation: "Purchase entitlement validation")
            analytics.track(.purchaseFailed(selectedPackage.plan).withProperties(context))
            alert = PaywallAlert(kind: .entitlementInactive)
            return false
        } catch {
            subscriptionManager.record(error, operation: "Purchase")
            analytics.track(.purchaseFailed(selectedPackage.plan).withProperties(context))
            alert = PaywallAlert(kind: .purchase)
            return false
        }
    }

    /// Backing out of Apple's sheet usually means the price read as a charge today. When a
    /// free trial exists, move the selection onto it and say plainly that nothing is charged.
    private func offerTrialAfterCancel() {
        guard let trialPackage else { return }
        if selectedPackage?.plan != trialPackage.plan {
            selectedPackage = trialPackage
        }
        showsCancelNudge = true
        analytics.track(.paywallCancelNudgeShown.withProperties(context))
    }

    func restorePurchases() async -> Bool {
        guard !isProcessing, !hasActivated else { return false }
        isRestoring = true
        analytics.track(.restoreStarted.withProperties(context))
        defer { isRestoring = false }

        do {
            _ = try await subscriptionManager.restorePurchases()
            guard subscriptionManager.isPro else {
                alert = PaywallAlert(kind: .noSubscription)
                return false
            }
            hasActivated = true
            analytics.track(.restoreCompleted.withProperties(context))
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
