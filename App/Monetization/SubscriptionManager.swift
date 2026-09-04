import Foundation
import Observation
import RevenueCat

@MainActor
@Observable
final class SubscriptionManager {
    private(set) var status: SubscriptionStatus = .unknown
    private(set) var lastError: String?

    let configuration: RevenueCatConfiguration
    private let service: any SubscriptionServiceProtocol
    private var isRefreshing = false
    private var customerInfoRevision = 0

    var isPro: Bool { status == .pro }
    var featureAccess: FeatureAccess { FeatureAccess(subscriptionStatus: status) }
    var isRevenueCatConfigured: Bool { service.isConfigured }
    var configurationSummary: String { service.configurationSummary }

    init(
        configuration: RevenueCatConfiguration = RevenueCatConfiguration(),
        service: (any SubscriptionServiceProtocol)? = nil
    ) {
        self.configuration = configuration
        self.service = service ?? RevenueCatSubscriptionService(configuration: configuration)

        self.service.customerInfoUpdateHandler = { [weak self] customerInfo in
            self?.apply(customerInfo, source: "delegate")
        }

        guard self.service.isConfigured else {
            status = .free
            log("RevenueCat SDK key is not configured; subscription access is inactive")
            return
        }

        if let cachedCustomerInfo = self.service.cachedCustomerInfo {
            apply(cachedCustomerInfo, source: "cache")
        }

        Task { await refresh() }
    }

    func refresh() async {
        guard isRevenueCatConfigured, !isRefreshing else { return }
        isRefreshing = true
        let revision = customerInfoRevision
        defer { isRefreshing = false }

        do {
            let customerInfo = try await service.refreshCustomerInfo()
            guard revision == customerInfoRevision else { return }
            apply(customerInfo, source: "refresh")
            lastError = nil
        } catch {
            // Never revoke last-known Pro access because a network refresh failed.
            record(error, operation: "Customer info refresh")
        }
    }

    func loadOfferings() async throws -> Offerings {
        guard isRevenueCatConfigured else { throw SubscriptionServiceError.notConfigured }
        return try await service.loadOfferings()
    }

    func eligibleFreeTrialProductIdentifiers(packages: [Package]) async -> Set<String> {
        guard isRevenueCatConfigured else { return [] }
        return await service.eligibleFreeTrialProductIdentifiers(packages: packages)
    }

    func purchase(package: Package) async throws -> PurchaseResultData {
        guard isRevenueCatConfigured else { throw SubscriptionServiceError.notConfigured }
        let result = try await service.purchase(package: package)
        customerInfoRevision += 1
        apply(result.customerInfo, source: "purchase")

        if !result.userCancelled, !isPro {
            do {
                let customerInfo = try await service.refreshCustomerInfo()
                customerInfoRevision += 1
                apply(customerInfo, source: "purchase reconciliation")
            } catch {
                record(error, operation: "Post-purchase customer info refresh")
            }
        }

        if isPro { lastError = nil }
        return result
    }

    func restorePurchases() async throws -> CustomerInfo {
        guard isRevenueCatConfigured else { throw SubscriptionServiceError.notConfigured }
        let customerInfo = try await service.restorePurchases()
        customerInfoRevision += 1
        apply(customerInfo, source: "restore")
        lastError = nil
        return customerInfo
    }

    func applyCustomerInfo(_ customerInfo: CustomerInfo, source: String) {
        customerInfoRevision += 1
        apply(customerInfo, source: source)
        lastError = nil
    }

    func record(_ error: Error, operation: String) {
        lastError = error.localizedDescription
        MonetizationLog.error("\(operation) failed: \(error.localizedDescription)")
    }

    private func apply(_ customerInfo: CustomerInfo, source: String) {
        let newStatus: SubscriptionStatus = customerInfo.entitlements[Entitlements.pro]?.isActive == true
            ? .pro
            : .free
        status = newStatus
        let activeEntitlements = customerInfo.entitlements.active.keys.sorted()
        let entitlementSummary = activeEntitlements.isEmpty ? "none" : activeEntitlements.joined(separator: ", ")
        log(
            "Customer info applied from \(source); status: \(String(describing: newStatus)); "
                + "active entitlements: \(entitlementSummary)"
        )

        // A subscriber with some other active entitlement means the dashboard identifier
        // does not match `Entitlements.pro` (a common display-name-vs-identifier mistake),
        // which silently locks paying users out of the product.
        if newStatus != .pro, !activeEntitlements.isEmpty {
            MonetizationLog.error(
                "Entitlement mismatch: expected '\(Entitlements.pro)' but RevenueCat reports "
                    + "active entitlements: \(entitlementSummary)"
            )
        }
    }

    private func log(_ message: String) {
        MonetizationLog.info(message)
    }
}

private enum SubscriptionServiceError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "RevenueCat is not configured; the RevenueCatAPIKey Info.plist value is missing or invalid."
        }
    }
}
