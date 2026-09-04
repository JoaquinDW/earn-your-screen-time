# Monetization

## Architecture

Monetization is app-only under `App/Monetization`. RevenueCat is not linked into `Shared` or the
Device Activity extension. Screen-time credits remain exclusively in `EarnDomain` and cannot be
purchased.

`AppEnvironment` owns one `SubscriptionManager`, which configures RevenueCat once during app
startup and explicitly selects RevenueCat's StoreKit 2 implementation. SwiftUI reads:

- `subscriptionManager.status`: `unknown`, `free`, or `pro`
- `subscriptionManager.isPro`: convenience access to the active entitlement
- `env.featureAccess`: centralized active-subscription capabilities

An unavailable network refresh does not change the last known status. RevenueCat cached
`CustomerInfo` is applied before a refresh when available. A build with no SDK key intentionally
keeps subscription access inactive instead of trying to initialize RevenueCat.

`ProPaywallView` is a fully app-owned SwiftUI paywall. `PaywallViewModel` owns its loading,
selection, purchase, restore, and error state; `SubscriptionService` is the only layer that calls
RevenueCat. RevenueCat supplies packages and localized prices but does not control paywall UI.

`restrictedAppSelectionGate` wraps the existing Family Controls picker and never reads or derives
token identities. Product UI is available only while the subscription entitlement is active.

New users build their app selection during onboarding before seeing a mandatory personalized
paywall. Activating the product requires an active `Earn your Screen Time Pro` entitlement from a
trial subscription, direct subscription, or restore. There is no permanent free tier, and expired
subscribers return to the non-dismissible subscription screen.
The free trial lasts three days. Trial copy is shown only when RevenueCat reports a three-day free
introductory offer and eligibility for the selected product.

## RevenueCat Configuration

The single entitlement is:

```text
Earn your Screen Time Pro
```

Expected product identifiers are currently:

```text
monthly
yearly
```

These values are centralized in `App/Monetization/Entitlements.swift`. Change them there and in the
StoreKit/App Store/RevenueCat product definitions if the final identifiers differ.

The public RevenueCat SDK key is read from the `RevenueCatAPIKey` Info.plist value, backed by the
`REVENUECAT_API_KEY` build setting in `project.yml`. Debug uses the project's `test_` RevenueCat Test
Store key. Release intentionally uses an empty value and therefore cannot activate subscription
access until the real Apple app is connected. Never submit an App Store build containing a `test_` key.

When the Apple app is connected, set its `appl_` public SDK key for Release through CI or a local
`.xcconfig`. Keep the generated `.xcodeproj` and any local `.xcconfig` overrides out of source
control.

The default/current RevenueCat Offering is used. Attach monthly and annual packages to it; no
RevenueCat-hosted paywall is required. Terms and Privacy URLs are centralized as build settings in
`project.yml` and exposed through Info.plist rather than duplicated in views. Their checked-in
checked-in values point to the repository's Terms and Privacy documents. Replace them with the final
published legal-page URLs before distribution if those locations change.

For the current Test Store project:

1. Create a one-month subscription product with identifier `monthly`.
2. Create a one-year subscription product with identifier `yearly`.
3. Attach both products to the `Earn your Screen Time Pro` entitlement.
4. Add `monthly` to the monthly package and `yearly` to the annual package in the current Offering.
5. Configure a three-day free trial for both products.
6. Run the normal `EarnYourScreenTime` scheme. RevenueCat presents its Test Store purchase modal,
   where success, failure, and cancellation can be simulated.

Test Store purchases update `CustomerInfo` and renew on accelerated schedules. A monthly product
renews every five minutes and a yearly product every hour, up to five renewals.

## Local StoreKit Testing

`StoreKit/EarnYourScreenTime.storekit` separately defines `monthly` and `yearly` Apple
auto-renewable subscriptions with three-day introductory offers in one subscription group. It is
not used by RevenueCat Test Store:
the current Debug `test_` key intentionally bypasses Apple's purchase flow.

Once an Apple `appl_` SDK key and Apple product mappings are available, regenerate with `make gen`,
configure that Apple key for the StoreKit scheme, and run `EarnYourScreenTime StoreKit` from Xcode.
Use Xcode's StoreKit transaction manager to accelerate renewals, expire subscriptions, interrupt
purchases, and clear transaction history.

RevenueCat must know how local products map to the entitlement before its paywall can sell them:

1. Create a RevenueCat project/app and configure its public SDK key.
2. Add `monthly` and `yearly` as Apple products in RevenueCat.
3. Attach both products to the `Earn your Screen Time Pro` entitlement.
4. Add monthly and annual packages to the current Offering.
5. In Xcode, open the `.storekit` file and use **Editor > Save Public Certificate**.
6. Upload that certificate in the RevenueCat iOS app's StoreKit testing framework settings.
7. Run the `EarnYourScreenTime StoreKit` scheme directly from Xcode.

Without an Apple RevenueCat SDK key/product mapping, the app cannot activate and displays the
non-purchasing fallback. The local StoreKit file alone cannot produce the RevenueCat
entitlement. Xcode local tests are useful for transaction lifecycle behavior, but RevenueCat notes
that some Xcode cancellation/refund simulations are not fully represented in its dashboard.

## App Store Connect And RevenueCat

Once products exist in App Store Connect:

1. Connect the App Store Connect app to the RevenueCat project.
2. Import the monthly and yearly products into RevenueCat.
3. Attach both products to the `Earn your Screen Time Pro` entitlement.
4. Attach monthly and annual packages to the current Offering.
5. Configure a three-day free trial for both products in App Store Connect.
6. Configure the production RevenueCat Apple SDK key for Release builds.

## Diagnosing An Empty Paywall

An empty paywall in TestFlight and in App Review is the same failure, and it blocks the reviewer
behind the non-dismissible subscription screen (Guideline 2.1 rejection). `PaywallViewModel`
distinguishes the causes instead of reporting one generic "missing packages" error:

| Diagnostic | Cause |
| --- | --- |
| `RevenueCat is not configured` | `REVENUECAT_API_KEY` did not reach Info.plist for this configuration. |
| `no current offering` | No offering is marked Current in the RevenueCat dashboard. |
| `zero available packages` | RevenueCat has the offering, but StoreKit returned no products for this bundle. Almost always the Paid Applications Agreement, a product still in "Missing Metadata", or a product identifier that differs from App Store Connect. |
| `no $rc_monthly / $rc_annual package` | Products are attached to custom packages instead of the monthly and annual package slots the paywall reads. |
| `timed out after 20s` | StoreKit never answered the product request. |

The message is shown on the paywall itself in DEBUG, Apple Sandbox and TestFlight builds
(`MonetizationBuild.isSandbox`) and hidden in App Store builds. It is always written to the
unified log: connect the device and filter Console.app by the `Monetization` category, or by the
`RevenueCat` subsystem for the SDK's own verbose product-request log, which is enabled in sandbox
builds and reduced to `.error` in App Store builds.

A mismatch between `Entitlements.pro` and the RevenueCat entitlement **identifier** (not its
display name) logs `Entitlement mismatch` whenever a customer has some other active entitlement.
That fault lets the purchase succeed while leaving the app locked.

## Customer Center

Active subscribers see **Manage subscription** in Settings. This presents RevenueCatUI's
`CustomerCenterView` through `SubscriptionCustomerCenterView`, keeping RevenueCat APIs inside the
monetization layer. Restore callbacks update `SubscriptionManager` immediately.

Configure and publish Customer Center in the RevenueCat dashboard before production. Include the
appropriate subscription management, cancellation, refund/support, and restore paths. Inactive
users continue to use Restore Purchases from the paywall.

For Apple Sandbox, disable the local StoreKit configuration by using the normal
`EarnYourScreenTime` scheme. Sign into a Sandbox Apple Account on a physical device, purchase and
restore, then test renewal, expiration, billing retry, and cancellation. Repeat the purchase and
restore flows through TestFlight before release. Sandbox timing and prices are not production
behavior.

## Subscription Access

`App/Monetization/FeatureAccess.swift` is the source of truth for product capabilities. An active
subscription unlocks the product; an inactive subscription has no product access. This is not a
freemium capability matrix.

Future gates should consume `FeatureAccess` rather than import RevenueCat or compare entitlement
strings. RevenueCat code should remain confined to the monetization layer.

## TODO once Apple Developer account is active

- Create a subscription group in App Store Connect.
- Create the monthly subscription.
- Create the annual subscription.
- Configure a three-day free trial for both subscriptions.
- Add localization and pricing.
- Complete required subscription metadata and review information.
- Accept paid-app agreements and complete tax/banking requirements.
- Connect the App Store Connect app to RevenueCat.
- Import products into RevenueCat.
- Attach products to an Offering.
- Attach products to the `Earn your Screen Time Pro` entitlement.
- Configure the production RevenueCat SDK key.
- Confirm the production Terms of Service and Privacy Policy URLs in `project.yml`.
- Configure and publish RevenueCat Customer Center.
- Test purchases using Apple Sandbox.
- Test through TestFlight.
- Verify restore purchases.
- Verify subscription renewal, expiration, billing retry, and cancellation behavior.
