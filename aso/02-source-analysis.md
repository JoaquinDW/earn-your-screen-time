# Phase 2 step 2 — source analysis (must precede translation)

## Brand structure
- **BrandWord**: `Earnit` — proper noun, never translated.
  **Deviation from the default rule:** the skill says transliterate the brand
  into non-Latin scripts. We keep `Earnit` in Latin for ja/ko/zh-Hans/ru/ar
  because the ar-SA listing already live uses Latin `Earnit` and passed review,
  Latin brand names are the norm in those storefronts, and splitting the brand
  across scripts would fracture word-of-mouth for an app that already ships.
- **DescriptorWord**: `Earn Screen Time` — search vocabulary, translated per
  market into the term phase 1 found people actually type (not a literal
  translation of the English).

## Domain vocabulary decisions
| Term | Decision |
|---|---|
| screen time | Translate to **Apple's own local term** — that is what people search: Bildschirmzeit, temps d'écran, tiempo de pantalla, tempo di utilizzo, tempo de tela, schermtijd, スクリーンタイム, 스크린타임, 屏幕使用时间, экранное время, ekran süresi, czas przed ekranem, وقت الشاشة |
| app blocker | Translate: App Sperre, bloquear apps, bloccare app, 앱 차단, アプリ制限, 应用锁 |
| digital detox | **Keep English** in de/nl/fr/it/pl/tr — a loanword that is genuinely searched there. Translate for ja/ko/zh/ru/ar. |
| push-ups, steps, study | Translate fully. |
| Screen Time (the iOS feature) | Apple's local string, matching the OS. |

## Idioms marked for meaning-translation (never literal)
- "Your phone should not be free. Earn it."
- "Move first. Scroll later." (existing tagline)
- "A timer asks you to stop. Earnit asks you to trade."
- "no talking yourself past it"

## Verbatim atoms — byte-identical in all 16 locales
- `iPhone`, `Apple Health`, `Apple Account`, `iOS`
- `https://www.earnitscreen.com/privacy.html`
- `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`
- `Earnit`

## Deliberate change to approved copy — flagged
The live description recites subscription prices ("$4.99 per month", "$39.99
per year"). Two reasons to drop the numbers:
1. The skill classes pricing language in a description as a rejection risk.
2. Extending it to 12 new locales would mean inventing prices in 12 currencies
   that may not match the real tier — a worse failure than omitting them.

Replaced with a subscription disclosure that keeps the auto-renewal terms and
both required links, with exact pricing shown in the app's own paywall (which
is where guideline 3.1.2 actually requires it). **This edits copy Apple has
already approved three times — say the word and I will restore the numbers for
the 4 live locales.**

## Note on what the description does and does not do
Apple does **not** index the description for App Store search — only name,
subtitle and the keyword field. So the description is written for conversion,
not ranking, and the legal block at the bottom costs nothing in ASO terms.
