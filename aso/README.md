# ASO working directory

Everything produced by the App Store Optimization pass. **Phases 1–2 are done and
live in App Store Connect; phase 5 is merged for the five finished locales.** Read
the status table before continuing.

## Status

| Phase | State |
|---|---|
| 1 Keyword research | **Done** — `01-keyword-research.md` |
| 2 Store metadata (16 locales) | **Done and verified live** on App Store Connect version 1.1 |
| 3 Screenshots | **Skipped** by choice — only en-US has a set; other locales fall back to English |
| 4 Territory pricing (GNI bands) | **Applied** — `aso/pricing.py`, 130 of 175 territories cut on both subscriptions |
| 5 In-app strings | **5 of 12 locales translated and merged into the app** (de, fr, it, ja, pt-BR) |
| 6 Submission | **Not started** |

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
