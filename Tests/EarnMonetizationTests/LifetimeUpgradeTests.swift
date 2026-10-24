import Foundation
import RevenueCat
import XCTest
@testable import Earnit

@MainActor
final class LifetimeUpgradeTests: XCTestCase {
    func testMonthlyAndAnnualSubscribersCanUpgradeButLifetimeOwnersCannot() async {
        for product in ["monthly", "yearly"] {
            let service = StubSubscriptionService(info: customerInfo(product: product))
            let manager = SubscriptionManager(service: service)
            XCTAssertTrue(manager.canUpgradeToLifetime)
            manager.applyCustomerInfo(customerInfo(product: "lifetime"), source: "test")
            XCTAssertTrue(manager.hasLifetimeAccess)
            XCTAssertFalse(manager.canUpgradeToLifetime)
        }
    }

    func testLifetimePurchaseCannotSucceedUsingExistingMonthlyAccess() async {
        let service = StubSubscriptionService(info: customerInfo(product: "monthly"))
        let manager = SubscriptionManager(service: service)
        await Task.yield() // Complete the initial refresh before checkout.
        let model = PaywallViewModel(subscriptionManager: manager, source: .settings)
        model.selectPackage(lifetimePackage())
        let succeeded = await model.purchase()
        XCTAssertFalse(succeeded)
        XCTAssertTrue(manager.isPro)
        XCTAssertFalse(manager.hasLifetimeAccess)
        XCTAssertEqual(model.alert?.kind, .entitlementInactive)
        XCTAssertTrue(model.canPurchase)
    }

    func testConfirmedLifetimePurchasePreventsDuplicatePurchase() async {
        let service = StubSubscriptionService(info: customerInfo(product: "monthly"))
        let manager = SubscriptionManager(service: service)
        await Task.yield()
        let model = PaywallViewModel(subscriptionManager: manager, source: .settings)
        model.selectPackage(lifetimePackage())
        service.purchaseInfo = customerInfo(product: "lifetime", activeMonthly: true)
        let succeeded = await model.purchase()
        XCTAssertTrue(succeeded)
        XCTAssertTrue(manager.hasLifetimeAccess)
        XCTAssertTrue(manager.hasActiveSubscription, "Buying Lifetime does not cancel monthly billing")
        XCTAssertFalse(manager.canUpgradeToLifetime)
        XCTAssertFalse(model.canPurchase)
        let repeated = await model.purchase()
        XCTAssertFalse(repeated)
        XCTAssertEqual(service.purchaseCount, 1)
    }

    func testCancelledPurchaseKeepsSubscriptionAndUpgradeAvailable() async {
        let service = StubSubscriptionService(info: customerInfo(product: "monthly"))
        service.cancelPurchase = true
        let manager = SubscriptionManager(service: service)
        let model = PaywallViewModel(subscriptionManager: manager, source: .settings)
        model.selectPackage(lifetimePackage())
        let succeeded = await model.purchase()
        XCTAssertFalse(succeeded)
        XCTAssertTrue(manager.canUpgradeToLifetime)
        XCTAssertEqual(model.selectedPackage?.plan, .lifetime)
        XCTAssertFalse(model.showsCancelNudge)
        XCTAssertTrue(model.canPurchase)
    }

    func testRestoringOnlyMonthlyDoesNotCompleteLifetimeUpgrade() async {
        let service = StubSubscriptionService(info: customerInfo(product: "monthly"))
        let model = PaywallViewModel(subscriptionManager: SubscriptionManager(service: service), source: .settings)
        let succeeded = await model.restorePurchases()
        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.alert?.kind, .noLifetime)
    }

    func testRestoredLifetimeCompletesUpgradeAndPreservesMonthlyReminder() async {
        let service = StubSubscriptionService(info: customerInfo(product: "monthly"))
        let manager = SubscriptionManager(service: service)
        let model = PaywallViewModel(subscriptionManager: manager, source: .settings)
        service.restoreInfo = customerInfo(product: "lifetime", activeMonthly: true)
        let succeeded = await model.restorePurchases()
        XCTAssertTrue(succeeded)
        XCTAssertTrue(model.hasLifetimeAccess)
        XCTAssertTrue(model.hasActiveSubscription)
    }

    func testFreeUserCanStillRestoreMonthly() async {
        let service = StubSubscriptionService(info: customerInfo(product: nil))
        let model = PaywallViewModel(subscriptionManager: SubscriptionManager(service: service), source: .settings)
        service.restoreInfo = customerInfo(product: "monthly")
        let succeeded = await model.restorePurchases()
        XCTAssertFalse(model.isLifetimeUpgrade)
        XCTAssertTrue(succeeded)
    }

    func testInactiveLifetimeCannotGrantPermanentAccess() async {
        let service = StubSubscriptionService(info: customerInfo(product: "lifetime", active: false))
        let manager = SubscriptionManager(service: service)
        XCTAssertFalse(manager.hasLifetimeAccess)
        XCTAssertFalse(manager.isPro)
    }

    func testLifetimeReconciliationRunsEvenWithExistingProAccess() async {
        let service = StubSubscriptionService(info: customerInfo(product: "monthly"))
        let manager = SubscriptionManager(service: service)
        await Task.yield()
        service.refreshInfo = customerInfo(product: "lifetime", activeMonthly: true)
        let model = PaywallViewModel(subscriptionManager: manager, source: .settings)
        model.selectPackage(lifetimePackage())
        let succeeded = await model.purchase()
        XCTAssertTrue(succeeded)
        XCTAssertTrue(manager.hasLifetimeAccess)
    }

    private func lifetimePackage() -> PaywallPackage {
        let product = TestStoreProduct(
            localizedTitle: "Lifetime", price: 30, currencyCode: "USD", localizedPriceString: "$30.00",
            productIdentifier: "lifetime", productType: .nonConsumable, localizedDescription: "Lifetime Pro", locale: Locale(identifier: "en_US")
        ).toStoreProduct()
        let package = Package(identifier: "$rc_lifetime", packageType: .lifetime, storeProduct: product,
                              presentedOfferingContext: .init(offeringIdentifier: "default"), webCheckoutUrl: nil)
        return PaywallPackage(plan: .lifetime, package: package, isEligibleForFreeTrial: false)
    }

    private func customerInfo(product: String?, active: Bool = true, activeMonthly: Bool = false) -> CustomerInfo {
        let now = Date()
        let expiry = now.addingTimeInterval(active ? 86_400 : -86_400)
        let entitlements = product.map { product in
            [Entitlements.pro: EntitlementInfo(
                identifier: Entitlements.pro, isActive: active, willRenew: product != "lifetime",
                periodType: .normal, expirationDate: product == "lifetime" ? nil : expiry,
                store: .appStore, productIdentifier: product, isSandbox: true, ownershipType: .purchased
            )]
        } ?? [:]
        var subscriptions: [String: Date] = [:]
        if let product, product != "lifetime" { subscriptions[product] = expiry }
        if activeMonthly { subscriptions["monthly"] = now.addingTimeInterval(86_400) }
        return CustomerInfo(entitlements: EntitlementInfos(entitlements: entitlements),
                            expirationDatesByProductId: subscriptions, requestDate: now,
                            firstSeen: now, originalAppUserId: "lifetime-upgrade-tests")
    }
}

@MainActor
private final class StubSubscriptionService: SubscriptionServiceProtocol {
    let isConfigured = true
    let configurationSummary = "unit test"
    var cachedCustomerInfo: CustomerInfo?
    var customerInfoUpdateHandler: ((CustomerInfo) -> Void)?
    var purchaseInfo: CustomerInfo
    var restoreInfo: CustomerInfo
    var refreshInfo: CustomerInfo
    var cancelPurchase = false
    var purchaseCount = 0

    init(info: CustomerInfo) {
        cachedCustomerInfo = info
        purchaseInfo = info
        restoreInfo = info
        refreshInfo = info
    }

    func loadOfferings() async throws -> Offerings { throw URLError(.notConnectedToInternet) }
    func eligibleFreeTrialProductIdentifiers(packages: [Package]) async -> Set<String> { [] }
    func purchase(package: Package) async throws -> PurchaseResultData {
        purchaseCount += 1
        return (transaction: nil, customerInfo: purchaseInfo, userCancelled: cancelPurchase)
    }
    func restorePurchases() async throws -> CustomerInfo { restoreInfo }
    func refreshCustomerInfo() async throws -> CustomerInfo { refreshInfo }
    func identify(appUserID: String) async throws -> CustomerInfo { refreshInfo }
}
