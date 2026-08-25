import Foundation
import RevenueCat

@MainActor
protocol SubscriptionServiceProtocol: AnyObject {
    var isConfigured: Bool { get }
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

        guard let apiKey = configuration.apiKey else { return }

        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        if !Purchases.isConfigured {
            Purchases.configure(
                with: Configuration.Builder(withAPIKey: apiKey)
                    .with(storeKitVersion: .storeKit2)
                    .build()
            )
        }
        Purchases.shared.delegate = self
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

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        customerInfoUpdateHandler?(customerInfo)
    }
}
