import Foundation
import RevenueCat

@MainActor
protocol SubscriptionServiceProtocol: AnyObject {
    var isConfigured: Bool { get }
    var configurationSummary: String { get }
    var cachedCustomerInfo: CustomerInfo? { get }
    var customerInfoUpdateHandler: ((CustomerInfo) -> Void)? { get set }

    func loadOfferings() async throws -> Offerings
    func eligibleFreeTrialProductIdentifiers(packages: [Package]) async -> Set<String>
    func purchase(package: Package) async throws -> PurchaseResultData
    func restorePurchases() async throws -> CustomerInfo
    func refreshCustomerInfo() async throws -> CustomerInfo
}

@MainActor
final class RevenueCatSubscriptionService: NSObject, SubscriptionServiceProtocol, PurchasesDelegate {
    private let configuration: RevenueCatConfiguration
    var customerInfoUpdateHandler: ((CustomerInfo) -> Void)?

    var isConfigured: Bool {
        configuration.isAvailable && Purchases.isConfigured
    }

    var cachedCustomerInfo: CustomerInfo? {
        guard isConfigured else { return nil }
        return Purchases.shared.cachedCustomerInfo
    }

    init(configuration: RevenueCatConfiguration) {
        self.configuration = configuration
        super.init()

        guard let apiKey = configuration.apiKey else {
            MonetizationLog.error("RevenueCat API key missing from Info.plist; paywall cannot load products")
            return
        }

        // Verbose logging in TestFlight/Sandbox too: RevenueCat's own log states how many
        // products it asked StoreKit for and how many Apple actually returned, which is the
        // only way to tell an App Store Connect misconfiguration from a network failure.
        Purchases.logLevel = MonetizationBuild.isSandbox ? .verbose : .error

        if !Purchases.isConfigured {
            Purchases.configure(
                with: Configuration.Builder(withAPIKey: apiKey)
                    .with(storeKitVersion: .storeKit2)
                    .build()
            )
        }
        Purchases.shared.delegate = self
        MonetizationLog.info(
            "RevenueCat configured; key prefix: \(apiKey.prefix(5)); bundle: "
                + "\(Bundle.main.bundleIdentifier ?? "unknown"); sandbox: \(MonetizationBuild.isSandbox)"
        )
    }

    var configurationSummary: String {
        let keyPrefix = configuration.apiKey.map { String($0.prefix(5)) } ?? "none"
        return "key: \(keyPrefix); configured: \(Purchases.isConfigured); "
            + "bundle: \(Bundle.main.bundleIdentifier ?? "unknown")"
    }

    func loadOfferings() async throws -> Offerings {
        try await Purchases.shared.offerings()
    }

    func eligibleFreeTrialProductIdentifiers(packages: [Package]) async -> Set<String> {
        let freeTrialPackages = packages.filter {
            $0.storeProduct.introductoryDiscount?.paymentMode == .freeTrial
        }
        let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(packages: freeTrialPackages)
        return Set(eligibility.compactMap { package, value in
            value.status.isEligible ? package.storeProduct.productIdentifier : nil
        })
    }

    func purchase(package: Package) async throws -> PurchaseResultData {
        try await Purchases.shared.purchase(package: package)
    }

    func restorePurchases() async throws -> CustomerInfo {
        try await Purchases.shared.restorePurchases()
    }

    func refreshCustomerInfo() async throws -> CustomerInfo {
        try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
    }

    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor [weak self] in
            self?.customerInfoUpdateHandler?(customerInfo)
        }
    }
}
