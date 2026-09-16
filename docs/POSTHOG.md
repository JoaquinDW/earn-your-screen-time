# PostHog product analytics

Earnit integrates the PostHog iOS SDK for product analytics. The integration is fail-closed: when
`POSTHOG_API_KEY` is missing, the SDK does not initialize and events continue only in the unified
OS log. Autocapture, screen-view autocapture, session replay, and application-lifecycle autocapture
are all explicitly disabled in code — only the app's existing, manually reviewed event taxonomy
(`AnalyticsEvent.swift`) is ever sent, including a generic `screen_viewed` event fired centrally
whenever the onboarding route or a top-level screen changes.

## Values to configure

Get both values from a PostHog project you create at **posthog.com** (US Cloud region, per the
`POSTHOG_HOST` default):

- `POSTHOG_API_KEY`: **Project Settings → Project API Key** (starts with `phc_`).
- `POSTHOG_HOST`: `https://us.i.posthog.com` for US Cloud (default), `https://eu.i.posthog.com`
  for EU Cloud, or your self-hosted ingestion URL.

Set them as Xcode build-setting overrides. For a command-line build:

```bash
xcodebuild \
  -project EarnYourScreenTime.xcodeproj \
  -scheme EarnYourScreenTime \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  POSTHOG_API_KEY=phc_replace_with_project_key \
  build
```

For normal Xcode Run/Archive builds, add the same user-defined build setting to the app target or
supply it from the release build system. It is embedded in the app bundle by design — a PostHog
project API key is a public write-only key, never a personal API key or a project secret.

One project is shared across Debug, TestFlight, and Release builds. Every event automatically
carries an `environment` super property (`debug` / `testflight` / `release`), computed from the
build configuration and, for non-Debug builds, whether the app was installed via a sandbox receipt.
Filter or break down any PostHog insight by `environment` to exclude development noise.

## Building insights

- **Onboarding drop-off funnel**: create a Funnel insight from the `screen_viewed` event, breakdown
  or filter on `screen_name`, ordered to match `OnboardingView.Route` (`onboarding_hook` →
  `onboarding_scrolling` → `onboarding_timeCost` → `onboarding_intent` → `onboarding_previousAttempt`
  → `onboarding_difference` → `onboarding_mechanism` → `onboarding_science` → `onboarding_health` →
  `onboarding_manualBaseline` → `onboarding_baselineResult` → `onboarding_progressiveGoal` →
  `onboarding_apps` → `onboarding_plan` → `onboarding_customize` → `onboarding_projection` →
  `onboarding_paywall` → `onboarding_mission`). The step with the largest drop is where people quit.
- **Paywall / purchase funnel**: already fully instrumented (`paywall_viewed` → `plan_selected` →
  `purchase_started` → `purchase_completed`/`purchase_cancelled`/`purchase_failed`) — no new
  wiring needed, PostHog just needs to be configured to receive it.
- **Earn-method comparison**: compare `first_earn_started`/`reward_completed` (steps),
  `pushups_session_started`/`pushups_reward_claimed`, and `study_scan_started`/`study_reward_granted`
  to see which earning method people actually finish versus abandon.
- **Retention**: use `onboarding_completed` as the activation event and any later `screen_viewed` or
  `minutes_earned` event as the return event, filtered to `environment=release`.

## Verification before shipping

1. Regenerate the project with `make gen`, provide `POSTHOG_API_KEY`, and install a Debug build.
2. In PostHog's **Live Events**, open the app and confirm `onboarding_started` and
   `screen_viewed` (`screen_name=onboarding_hook`) arrive tagged `environment=debug`.
3. Step through onboarding, including at least one back-navigation, and confirm 18 distinct
   `screen_viewed` events fire in route order.
4. Visit Dashboard, Earn Time, Settings, Pushups to Earn, and Study to Earn once each and confirm
   exactly one `screen_viewed` per screen, not repeated on every re-render.
5. Make a Sandbox/TestFlight purchase and confirm `purchase_completed` arrives tagged
   `environment=testflight`.
6. After the SPM package resolves, confirm the built app includes PostHog's own bundled
   `PrivacyInfo.xcprivacy` (no separate app-level manifest is expected to be needed).

Before App Store submission, update App Privacy answers to disclose the anonymous analytics data
collected via PostHog, and keep `PRIVACY.md` aligned with those answers.
