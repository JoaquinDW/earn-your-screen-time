# ASO working directory

Everything produced by the App Store Optimization pass. **Phases 1–2 are done and
live in App Store Connect; phase 5 is partially done.** Read the status table
before continuing.

## Status

| Phase | State |
|---|---|
| 1 Keyword research | **Done** — `01-keyword-research.md` |
| 2 Store metadata (16 locales) | **Done and verified live** on App Store Connect version 1.1 |
| 3 Screenshots | **Skipped** by choice — only en-US has a set; other locales fall back to English |
| 4 Territory pricing (GNI bands) | **Not applied** — planner written, never completed a run |
| 5 In-app strings | **5 of 12 locales translated, none merged into the app yet** |
| 6 Submission | **Not started** |

## Phase 2 — what is live

App Store Connect version **1.1** (`PREPARE_FOR_SUBMISSION`, needs a build before
it can be submitted) carries new name / subtitle / keywords / description /
promotional text / release notes in **16 locales**, all confirmed by reading them
back from the API. Twelve of those locales did not exist on the listing before.

Source of truth for the copy is `fastlane/metadata/<locale>/*.txt`.
Regenerate and re-validate with `python3 aso/build.py --write`,
re-push with `python3 aso/reconcile.py`, and verify with `python3 aso/verify.py`.

## Phase 5 — in-app translation, incomplete

The cascade translates 770 strings across `Localizable`, `Study` and `Pushups`.

**Complete and detector-clean:** `de`, `fr`, `it`, `ja`, `pt-BR` (`l10n/out/`).
**Not done:** `nl`, `pl`, `tr`, `ru`, `ko`, `zh-Hans`, `ar` — their agents hit a
session rate limit mid-run.
**Extensions + permission prompts** (`l10n/out_ext/`, 51 strings covering the
Shield block screen, Live Activity and the iOS permission dialogs): only
`de`, `fr`, `it` exist.

**Nothing has been merged into the `.xcstrings` catalogs yet.** `l10n/merge.py`
is additive-only and refuses to write if it would touch `en`/`es` or change any
key set; run `python3 aso/l10n/merge.py` for a dry run, `--write` to apply.
Run `python3 aso/l10n/detect.py` first — it must be clean.

To finish, re-run the remaining locales with the same brief (`l10n/BRIEF.md`),
which carries the sense glossary that keeps "earn", "balance", "shield", "plan"
and "rate" on their in-app meanings rather than their common ones.

## Blockers found in the app itself (not ASO problems)

1. **Three broken keys in `App/Resources/Localizable.xcstrings`** —
   `pushups.active.progress %lld %lld`, `pushups.active.rep_announcement %lld %lld`
   and `pushups.challenge.accessibility %lld %lld` have the *key id itself* as
   their English value. The correct English lives in `PushupsLocalizable.xcstrings`
   under the same keys, and the Pushups UI reads that table, so these are dead
   duplicates — but they should be deleted rather than left to rot.
2. **The language picker only offers English and Spanish.** `AppLanguage` in
   `Shared/AppGroup.swift` has three cases (`system`, `english`, `spanish`) and
   `SettingsView.swift` hardcodes three rows. Shipping 12 languages without
   extending these means users cannot pick their own language in-app (iOS
   per-app language settings still work).
3. **`NSCameraUsageDescription` and `NSHealthUpdateUsageDescription` are not in
   `InfoPlist.strings`**, so those two permission prompts show English in every
   language regardless of what else is translated.
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
