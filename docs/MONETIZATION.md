# Monetization

## Offers

The app offers **monthly with an eligible three-day free trial** and **lifetime without a trial**.
Lifetime is selected first, with a US base price of **USD 30**. Every displayed price comes from
StoreKit in the customer's currency. The yearly option is hidden in the new app version.

| Store | Product identifier | RevenueCat package |
| --- | --- | --- |
| Apple | `com.balthasardeweert.earnyourscreentime.pro.monthly` | `$rc_monthly` |
| Apple | `lifetime` | `$rc_lifetime` |
| Test Store | `monthly` | `$rc_monthly` |
| Test Store | `lifetime` | `$rc_lifetime` |

Lifetime is a **non-consumable**, never a subscription or consumable. Apple product ID:
`6824755138`; RevenueCat Apple product ID: `prod81c2efe98b`. All products grant the existing
`Earn your Screen Time Pro` entitlement.

The monthly price and its existing three-day introductory offer remain unchanged. Trial messaging
requires both an actual three-day introductory offer and customer eligibility. Lifetime never
shows a free trial, monthly equivalent, or automatic-renewal disclosure. Canceling its purchase
sheet leaves Lifetime selected and does not switch the user into a subscription.

## Architecture

Monetization is app-only. RevenueCat is not linked into `Shared` or the Device Activity extension.
Screen-time credits remain exclusively in `EarnDomain` and cannot be purchased.

`AppEnvironment` owns one `SubscriptionManager`, configured with StoreKit 2. SwiftUI uses:

- `subscriptionManager.status`: `unknown`, `free`, or `pro`
- `subscriptionManager.isPro`: active entitlement access
- `env.featureAccess`: centralized product capabilities

RevenueCat cached `CustomerInfo` is applied before a refresh. Failed network refreshes preserve
last-known access. Both active subscriptions and lifetime purchases use the same entitlement check;
a lifetime entitlement does not need an expiration date. A missing SDK key leaves access inactive.

`ProPaywallView` owns the SwiftUI presentation. `PaywallViewModel` owns loading, selection,
purchase, restore, and errors. `SubscriptionService` calls RevenueCat. The paywall uses the current
offering and requires valid monthly and lifetime packages. Product type validation prevents a
recurring subscription from being sold as lifetime access.

For an existing Pro subscriber, the upgrade paywall requires only the Lifetime package; a missing
monthly product must not block that purchase. The normal free-user paywall requires both.

The free earned-unlock preview and its closable paywall are unchanged. Access decisions remain in
`FeatureAccess`; Screen Time shield decisions remain in `RestrictionCoordinator`.

## Existing subscribers and installed versions

Keep the annual product attached to the Pro entitlement. Existing monthly and annual customers
retain access while their entitlement is active, and Restore Purchases continues to work.

Keep `$rc_annual` in the current RevenueCat offering alongside monthly/lifetime: older installed
versions require both monthly and annual to load their paywall. The new app explicitly displays
only lifetime and monthly. Removing the old package before those versions have migrated would
break their paywall. Do not cancel existing subscriptions or remove their product mappings.

## Configuration

The current offering is `default` (`ofrng93996309c6`). It does not require a RevenueCat-hosted
paywall. Attach lifetime to both `$rc_lifetime` and `Earn your Screen Time Pro`.

The public SDK key comes from `RevenueCatAPIKey` in Info.plist and `REVENUECAT_API_KEY` in
`project.yml`. Debug and Release use Apple's `appl_` key. `DebugTestStore` uses a `test_` key;
never submit that configuration to the App Store. The generated Xcode project is ignored.

Terms and Privacy URLs are build settings in `project.yml`. Publish updated `TERMS.md` before
release so the live document describes both monthly subscriptions and lifetime purchases.

## Testing

- `make all`: regenerate project, run domain tests, build simulator app.
- `make test-monetization`: simulator unit tests with mocked RevenueCat responses for
  subscription-to-Lifetime purchases, cancellation, restoration and entitlement validation.
- `EarnYourScreenTime Test Store`: simulated purchases, cancellation, failure, and restore. Create
  `monthly` and non-consumable `lifetime` in Test Store and attach them to the same Pro entitlement
  and respective packages. Test Store does not represent Apple's trial eligibility.
- `EarnYourScreenTime StoreKit`: local StoreKit catalog, including USD 30 lifetime and legacy
  subscription fixtures. The Apple products must match RevenueCat's identifiers; export the
  StoreKit public certificate and upload it to RevenueCat's StoreKit testing settings.
- Apple Sandbox/TestFlight: verify the actual monthly trial, lifetime immediate payment, purchase
  cancellation, restoration after reinstall, existing annual access, and refund/revocation.

Lifetime must emit `purchase_completed` with `plan=lifetime`, without `trial_started` or
`subscription_started`. Monthly retains its existing subscription/trial events. Offer events
include both localized prices, monthly eligibility, and the paywall entry point.

Settings offers **Switch to Lifetime** to Pro subscribers who do not already own Lifetime.
That paywall displays only Lifetime, without a trial, and explains that the purchase does not
cancel the existing subscription. Purchase and restore completion must verify the active Pro
entitlement's `lifetime` product with no expiration; existing monthly/annual Pro access alone
cannot complete this flow. A post-purchase prompt opens Apple's subscription management sheet,
and Settings retains a cancellation reminder while an active subscription also exists. Lifetime
owners see **Lifetime Pro** and no upgrade button. A canceled subscription may remain active
until expiry, so the reminder explicitly applies only if renewal is still enabled.

Settings opens RevenueCat Customer Center under **Manage purchases** for Pro users. Restore
callbacks update the manager immediately. Configure support/refund and subscription management
paths in Customer Center; the latter still matters to existing subscribers.

## Release

Version **1.3.2 (2)** adds the subscriber upgrade path. For App Review, an existing monthly or
annual subscriber can use **Settings → Plan → Switch to Lifetime**. A free user can use
**Settings → Plan → Explore Pro**. The reviewer no longer needs to clear sandbox purchase history
to find Lifetime. Build 2 must be uploaded and assigned before these instructions apply.

Configured on October 19, 2026 (Argentina): Apple reports `READY_TO_SUBMIT`, with the USD 30
price, availability in 175 territories, English/Spanish metadata, review notes, and a processed
review screenshot. RevenueCat Apple and Test Store lifetime products are attached to Pro and
`$rc_lifetime` in `default`. Simulator screenshots are in `.build/monetization-review/`.


The product and price configuration are separate from app release. Complete Apple review metadata
and the review screenshot, submit the new non-consumable with a version containing this paywall,
and verify Apple Sandbox/TestFlight before releasing. Do not distribute a build whose current
RevenueCat offering cannot return both monthly and lifetime products.

## Diagnostics

Sandbox/TestFlight builds display configuration details and log them under `Monetization`:

| Diagnostic | Check |
| --- | --- |
| Not configured | Public SDK key in the built Info.plist |
| No current offering | RevenueCat current/default offering |
| Zero available packages | Apple agreements, product metadata, identifiers, availability |
| Missing monthly package | `$rc_monthly` with an auto-renewable subscription |
| Missing lifetime package | `$rc_lifetime` with a non-consumable |
| Entitlement inactive after purchase | Product attached to the exact Pro entitlement identifier |
| Offer loading timeout | StoreKit product request/network availability |

Purchase completion alone never grants Pro: the active RevenueCat entitlement must be verified.
