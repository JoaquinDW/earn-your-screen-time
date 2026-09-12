# Meta Ads attribution

Earnit integrates Meta iOS SDK `FacebookCore` for App Events, ATT, and SKAdNetwork attribution.
The integration is fail-closed: when either public client identifier is missing, the SDK does not
initialize, events continue only in the unified OS log, and the ATT prompt is not shown.

## Values to configure

Get both values from **Meta App Dashboard → Settings → Advanced** (the exact section name can vary):

- `FACEBOOK_APP_ID`: the numeric Meta App ID.
- `FACEBOOK_CLIENT_TOKEN`: the iOS client token. This is not the Meta App Secret and not Apple's
  app-specific shared secret.

Set them as Xcode build-setting overrides for both Debug and Release. For a command-line build:

```bash
xcodebuild \
  -project EarnYourScreenTime.xcodeproj \
  -scheme EarnYourScreenTime \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  FACEBOOK_APP_ID=123456789012345 \
  FACEBOOK_CLIENT_TOKEN=replace_with_client_token \
  build
```

For normal Xcode Run/Archive builds, add the same user-defined build settings to the app target or
supply them from the release build system. They are embedded in the app bundle by design; never use
the Meta App Secret here.

## Meta dashboard

Configure the iOS platform with:

- Bundle ID: `com.balthasardeweert.earnyourscreentime`
- URL scheme suffix: empty
- iPhone Store ID: the numeric Apple ID from App Store Connect
- iPad Store ID: empty (Earnit targets iPhone only)
- Shared secret: the app-specific shared secret from App Store Connect, if Meta requests it for
  automatic StoreKit purchase verification

Leave automatic App Events enabled. SDK 18 automatically observes StoreKit 2 transactions, which
avoids emitting a second manual purchase event with incomplete price or currency data. Earnit's
existing funnel events are also forwarded as custom events, and `onboarding_completed` additionally
emits Meta's standard `CompletedRegistration` conversion.

## Verification before spending

1. Regenerate the project with `make gen`, provide the two Meta build settings, and install a fresh
   build on a physical iPhone.
2. In **Events Manager → Test Events**, open the app and confirm `fb_mobile_activate_app`.
3. Complete onboarding and confirm both `onboarding_completed` and
   `fb_mobile_complete_registration`.
4. Make a Sandbox/TestFlight subscription purchase and confirm Meta's automatic trial,
   subscription, or purchase event. Do not use an Xcode local StoreKit transaction as proof of
   production attribution.
5. Test once with ATT allowed and once with it denied. App functionality must be identical. A denied
   ATT prompt does not disable SKAdNetwork attribution.

Before App Store submission, update App Privacy answers to disclose the Meta and RevenueCat data
actually collected and linked, and keep `PRIVACY.md` aligned with those answers.
