# ASO working directory

Everything produced by the App Store Optimization pass. **Phases 1–2 are done and
live in App Store Connect; phase 5 is merged for the five finished locales.** Read
the status table before continuing.

## Status

| Phase | State |
|---|---|
| 1 Keyword research | **Done** — `01-keyword-research.md` |
| 2 Store metadata (16 locales) | **Done and verified live** — name/subtitle/keywords/description on 1.1 (now `READY_FOR_SALE`); release notes + promotional text refreshed and verified live on draft **1.2** for this submission |
| 3 Screenshots | **en-US/en-GB/es-ES/es-MX/de-DE done** on draft version 1.2 (`APP_IPHONE_65`, 6 each); the other 11 locales still have no set and fall back to English |
| 4 Territory pricing (GNI bands) | **Applied** — `aso/pricing.py`, 130 of 175 territories cut on both subscriptions |
| 5 In-app strings | **5 of 12 locales translated and merged into the app** (de, fr, it, ja, pt-BR) |
| 6 Submission | **Not started** |

**1.3.0 draft** (`4dafd77d-77aa-4bb9-9187-979c7f6e420e`, `PREPARE_FOR_SUBMISSION`, no build yet)
was created 2026-10-07; every script here now points at it and at the editable appInfo
`b5370e75-460e-4bb7-b721-2ed575e04da0`. Description, keywords, support URL and screenshots
carried over from live 1.2.2; release notes (squats + inactivity reminders) were pushed for all
16 locales. Note: the live en-US name/subtitle/keywords and the (empty) promotional text were
edited in App Store Connect after `metadata.json` was generated, so `verify.py` reports them as
mismatches. Do not run `reconcile.py`/`push.py` without first deciding which side is right.

## Phase 3 — screenshots on version 1.2

Screenshots attach to an editable `appStoreVersion`, and all four existing versions
(1.0–1.1) were already `READY_FOR_SALE` — no draft to attach to. Created **1.2**
(`fdeb596c-9821-4b3a-aca7-3eaf2cbee43a`, `PREPARE_FOR_SUBMISSION`, no build attached
yet, so it cannot be submitted as-is) and re-pushed all 16 locales' description/
keywords/promotional text/release notes/support URL onto it — creating a version via
the API does **not** carry that text forward, only the screenshots do, and skipping
this step would have shipped an all-English 1.2 over the localized 1.1 listing.

Source screenshots came in at 853×1844, short of the `APP_IPHONE_65` requirement
(1242×2688 — checked from the existing en-US set); upscaled 1.46× with
`ffmpeg -vf scale=1242:2688:flags=lanczos` before upload. A screenshot set carried
forward from the prior version arrives pre-populated with the old images — the
en-US set on 1.2 inherited 1.1's 7 screenshots and had to be cleared before the new
6 replaced them; en-GB/es-ES/es-MX/de-DE had no prior set and uploaded clean.

Remaining locales (fr-FR, it, pt-BR, nl-NL, pl, tr, ru, ja, ko, zh-Hans, ar-SA) have
no screenshot set on 1.2 and fall back to English, same as before. To finish one:
export at 1242×2688 (or 1284×2778), then write an uploader following `push.py`'s
`asc()` pattern pointed at `fdeb596c-9821-4b3a-aca7-3eaf2cbee43a` — GET the locale's
`appStoreVersionLocalization` id, POST/reuse its `appScreenshotSet`
(`APP_IPHONE_65`), then per image: POST `appScreenshots` (fileName/fileSize) to get
`uploadOperations`, PUT each byte range with its given headers, PATCH
`uploaded: true` + md5 `sourceFileChecksum`. Check for a carried-forward set with
stale images first (see above) before adding new ones — it silently fills to the
10-screenshot cap and mixes old with new.

## Phase 2b — release notes & promotional text for 1.2

`reconcile.py`/`verify.py`/`push_whatsnew.py`/`push.py`/`push_support_url.py` all still
pointed `VERSION_ID` at **1.1**, which shipped and is now `READY_FOR_SALE` (no longer
editable except promotional text) — 1.1 became live between the screenshot work above and
this pass. Updated all five scripts' `VERSION_ID` to **1.2**
(`fdeb596c-9821-4b3a-aca7-3eaf2cbee43a`), the actual `PREPARE_FOR_SUBMISSION` draft.

This version's changes (refreshed screenshots, an onboarding step that lets you try a real
push-up set and feel it unlock your apps, PostHog analytics, and an App Store rating
prompt) are user-facing only for the onboarding demo and the rating prompt — screenshots
and analytics aren't things the app tells the user about, so the release notes cover the
demo and the rating ask and fold the rest into a generic "under the hood" line rather than
mentioning analytics by name.

- **Release notes** (`aso/whatsnew.py`) rewritten for all 16 locales, describing the new
  onboarding push-up demo and the App Store rating prompt. Pushed with
  `python3 aso/push_whatsnew.py --write` (targeted PATCH of `whatsNew` only, same pattern
  as before).
- **Promotional text** — the evergreen "three ways to earn" pitch replaced with a line
  about the new onboarding demo, edited at the source (`promo=` in `gen_part1/2/3.py`) so
  a future full `aso/build.py --write` + `aso/reconcile.py` won't regress it. Regenerated
  with `aso/build.py --write`, pushed with the new `aso/push_promo.py --write` (targeted
  PATCH of `promotionalText` only — name/subtitle/keywords/description weren't touched).
- Both verified live via `python3 aso/verify.py`: all 16 locales read back clean, no
  fallback-to-English, no stale text.
- **Not done**: submission. The user asked to prepare the metadata only, not send 1.2 to
  review — and it couldn't be submitted yet regardless, since no build is attached to 1.2.

## Phase 2 — what is live

App Store Connect version **1.1** (`PREPARE_FOR_SUBMISSION`, needs a build before
it can be submitted) carries new name / subtitle / keywords / description /
promotional text / release notes in **16 locales**, all confirmed by reading them
back from the API. Twelve of those locales did not exist on the listing before.

**Every localization needs a support URL** or the version cannot be submitted — the
submit dialog reports it as "Support URL - This field is required" and names only a few
of the offending locales at a time, so fixing the ones it lists just moves the error.
The field was missing from the pipeline entirely, so the twelve locales the ASO pass
created were born without one; `aso/push_support_url.py` backfills every locale from
en-US, and `build.py`/`reconcile.py`/`verify.py` now carry `support_url` so a newly
created locale gets it from the start.

Source of truth for the copy is `fastlane/metadata/<locale>/*.txt`.
Regenerate and re-validate with `python3 aso/build.py --write`,
re-push with `python3 aso/reconcile.py`, and verify with `python3 aso/verify.py`.

## Phase 4 — territory pricing

`aso/pricing.py` bands both subscriptions by purchasing power. **There is no "Netflix
index"** — Netflix publishes no formula, and its per-country prices move constantly and
are partly competitive rather than income-driven. What is reproducible is the *shape* of
what Netflix does, so the source here is World Bank GNI per capita, Atlas method
(`aso/gni-worldbank.json`, `NY.GNP.PCAP.CD`, refreshed from the World Bank API), with the
spread calibrated to Netflix's observed one: poorest band at 20% of the US price, richest
at 100%.

| GNI per capita | monthly | yearly | vs US |
|---|---|---|---|
| < $2,000 | $0.99 | $7.99 | 20% |
| $2,000–6,000 | $1.99 | $15.99 | 40% |
| $6,000–15,000 | $2.99 | $23.99 | 60% |
| $15,000–30,000 | $3.99 | $31.99 | 80% |
| > $30,000 | $4.99 | $39.99 | 100% (unchanged) |

Prices are never computed from an exchange rate. For each band the US anchor price point
is resolved, and Apple's `equalizations` endpoint supplies that anchor's counterpart in
every other territory — so every value written is one Apple already offers there, in local
currency, with VAT handled. Five territories have no World Bank GNI (`AIA`, `MSR`, `TWN`,
`VGB`, plus `XKS`, which is set manually); anything unclassified keeps the top band, so a
market we cannot place is never silently discounted.

Two things the API forces:

- **A price change needs a `startDate`.** A POST to `/v1/subscriptionPrices` without one
  asks to create the subscription's *initial* price, which an approved subscription
  already has — Apple answers `409 STATE_ERROR, "Initial price cannot be created again
  after subscription is approved"`. The script schedules for tomorrow.
- **`preserveCurrentPrice: false`** passes the new price to existing subscribers too.
  Every change here is a reduction, so they get the cut rather than being grandfathered
  onto the higher price.

Re-run with `python3 aso/pricing.py` for the dry-run table, `--write` to apply. GETs are
cached under the scratchpad; delete the cache to re-read live prices.

## Phase 5 — in-app translation, 5 of 12 locales

The cascade translates 770 strings across `Localizable`, `Study` and `Pushups`,
plus 51 in `Shield`, `LiveActivity` and `InfoPlist`.

**Merged and shipping:** `de`, `fr`, `it`, `ja`, `pt-BR` — all five complete
across every catalog *and* the extensions, and all five clean under
`aso/l10n/detect.py`. Each has an `App/Resources/<locale>.lproj/InfoPlist.strings`,
which is what registers the region with XcodeGen and localizes the permission
prompts; `knownRegions` now reads `de, en, es, fr, it, ja, pt-BR`.

**Not done:** `nl`, `pl`, `tr`, `ru`, `ko`, `zh-Hans`, `ar` — their agents hit a
session rate limit mid-run and `aso/l10n/out/<locale>.json` was never written.
The store listing already exists in those locales, so the ficha is translated
while the app is not. To finish, re-run them with the same brief
(`l10n/BRIEF.md`), which carries the sense glossary that keeps "earn",
"balance", "shield", "plan" and "rate" on their in-app meanings.

**Workflow for a new locale:** run `python3 aso/l10n/detect.py` until the locale
reports clean, `python3 aso/l10n/merge.py` for a dry run, then `--write`. The
merge is additive-only and refuses to write if it would touch `en`/`es` or
change any key set. Then add the `.lproj/InfoPlist.strings`, add a case to
`AppLanguage` in `Shared/AppGroup.swift`, and run `make gen`.

**When in-app strings change:** `aso/l10n/work.json` is the detector's source of
truth and has to be updated alongside the catalog, or new keys ship untranslated
without the detector noticing.

## Blockers found in the app itself (not ASO problems)

1. **Three broken keys in `App/Resources/Localizable.xcstrings`** —
   `pushups.active.progress %lld %lld`, `pushups.active.rep_announcement %lld %lld`
   and `pushups.challenge.accessibility %lld %lld` have the *key id itself* as
   their English value. The correct English lives in `PushupsLocalizable.xcstrings`
   under the same keys, and the Pushups UI reads that table, so these are dead
   duplicates — but they should be deleted rather than left to rot.
2. ~~**The language picker only offers English and Spanish.**~~ **Fixed.**
   `AppLanguage` now carries a `localeIdentifier` and one case per shipped
   language, and `SettingsView` builds the picker from `allCases`, labelling
   each language with its own endonym. Add a case whenever a locale merges.
3. ~~**`NSCameraUsageDescription` and `NSHealthUpdateUsageDescription` are not in
   `InfoPlist.strings`.**~~ **Fixed** — both are now in all seven `.lproj`
   files, `en` and `es` included.
4. **90-day vs 30-day copy inconsistency** — `onboarding.plan.title` and the
   projection screens say 90 days while the rest of the app says a 30-day
   journey. Flagged independently by four translators. Product call, not a
   translation bug.
5. **`Yearly` carries a copy-pasted comment** describing a monthly charge.
6. **`Today` renders as "Ahora" ("Now") in the shipped Spanish** but "Today" in
   English — worth confirming which is intended.

## Note on how locales register with Xcode

XcodeGen derives `knownRegions` from `.lproj` directories only — it ignores a
`knownRegions:` key in `project.yml` (tested, both at top level and under
`options`). Adding a language therefore requires creating
`App/Resources/<locale>.lproj/InfoPlist.strings`, which conveniently is also
where the permission prompts get localized.
