# Korean localization review

Tone and terminology follow `fastlane/metadata/ko` and `marketing/app-store-screenshots/l10n/ko.json`: casual-polite Korean, 스크린타임, 앱 차단, 팔굽혀펴기, 스쿼트, 걷기 and 걸음 수. Earnit stays in Latin letters.

The five catalogs contain 1,324 translations corresponding to every Japanese entry, plus seven identity/settings entries needed for Korean bundle lookup. The separate Progress table has 47 Korean entries. Existing translations and catalog key order are unchanged. `scripts/check-korean-localization.py` checks coverage, translated state, exact format-token counts (including positional tokens and literal percent signs), newlines, inflection structure, and Progress/InfoPlist key parity.

## Screenshots

Captured on 2026-10-29 with an iPhone 17 Pro simulator running iOS 26.5, at 1206 × 2622. These are the existing SwiftUI views rendered in Korean. Native UI control failed with a ScreenCaptureKit capture error, so a temporary launch harness opened each view directly. The harness was removed before the final `make all` and is not part of this change.

Dashboard/history values, exercise challenge availability, and paywall prices are local QA fixtures. The paywall displays example KRW prices, not prices fetched from the Korean App Store. No purchase, exercise reward claim, or App Store Connect upload was performed.

- [Onboarding](screenshots/onboarding.png)
- [Dashboard](screenshots/dashboard.png)
- [Paywall](screenshots/paywall.png)
- [Settings](screenshots/settings.png)
- [Exercise challenge picker](screenshots/exercise.png)

Visual inspection caught an English `steps` suffix bypassing localization in Settings and an exercise heading that pushed the button beyond the first viewport. The suffix now uses the existing localized format; the heading is the shorter “몇 분을 벌까요?”. The final captures show the corrected screens.

## Native-speaker review priorities

| Key or context | Korean | Review question |
| --- | --- | --- |
| `friends.nudge` / `friends.event.nudge %@` | 콕 찌르기 / …님이 콕 찔렀어요 | Does this playful reminder sound encouraging rather than intrusive? |
| `friends.squads` | 그룹 | Matches the screenshot wording; is it clear enough for the weekly league? |
| `Screen time wallet` | 스크린타임 지갑 | Is the wallet metaphor natural, or would 시간 잔액 read better? |
| “temptation bundling” explanation | 유혹 묶기 | Check the Korean behavioral-science term and the long evidence explanations. |
| `pushups.cue.plank` and voice guidance | 플랭크 자세로 펴요 | Check exercise-coaching idiom, particularly maintaining a straight body without kneeling. |
| `progress.source.study` | 집중 활동 | Hidden source label avoids promoting the disabled Study feature outside its own table. |
| Lifetime upgrade and renewal notices | 평생 이용권 / 자동 갱신 | Check purchase terminology and readability of the longer reminders. |

Korean camera permission copy only describes exercise counting; it does not advertise the hidden Study feature. No feature flags or purchase/session rules were changed.
