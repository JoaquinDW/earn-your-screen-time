# Phase 1 — Keyword research (Earnit, app id 6804905841)

Status: live (READY_FOR_SALE, v1.0.2), few installs → low-difficulty strategy.
Evidence: iTunes Search API rank scans, US + 13 storefronts, 2026-09-15.
Apple's autosuggest hints endpoint now returns empty, so candidate discovery
came from who actually ranks per term plus competitor name convergence (Rule 6).

## What the live listing does today

| Surface | Current | Problem |
|---|---|---|
| Name | `Earnit: Walk to Limit Screen` | Brand-first (Rule 1). "Walk to Limit Screen" is not a phrase anyone types. |
| Subtitle | `Focus Timer, Habit & Step Lock` | Three half-terms, none complete. "Step Lock" has no search volume. |
| Keywords en-US | `blocker,tracker,goals,counter,pedometer,detox,quit,downtime,phone,fitness,health,control,daily` | Single-word soup, not phrases. `pedometer`/`fitness`/`health`/`counter` are adjacent-but-wrong-intent (Rule 3). |

## The central finding: "earn screen time" is a real category

| Ranking app for "earn screen time" | Ratings |
|---|---|
| Unrot: Earn your Screen Time | 56,810 |
| Blocus: Earn Screen Time | 226 |
| Piggy / Koia / DoomIt / Peep — all "Earn Screen Time" in the name | 0–29 |

Six-plus apps bet their *name* on this phrase. Devs converge on what works
(Rule 6), and one of them built 56k ratings on it. It is also exactly what
Earnit does — walk, study, or do push-ups, get minutes — so intent-match is
total (Rule 3). Crucially it is a **narrower** term than "screen time control",
where Opal (87k), BePresent (63k) and ScreenZen (49k) are entrenched and a
few-install app cannot win (Rule 5).

The brand name "Earnit" reinforces the keyword instead of competing with it.

## Terms deliberately cut

- `pedometer`, `step counter`, `fitness`, `health`, `podómetro` — searchers want a
  step tracker, not an app blocker. Wrong intent, currently wasting budget.
- `walk to earn` — that SERP is Sweatcoin (397k), WeWard (118k), CashWalk:
  **cash-for-steps** apps. Same words, completely different intent.
- `tracker`, `goals`, `daily`, `control` as bare words — too generic (Rule 3).
- `screen time control` in the name — relevant but unwinnable right now (Rule 5).

## Per-market findings (Rule 7 — research, not translation)

| Market | Core local term | Note |
|---|---|---|
| es-ES / es-MX | `tiempo de pantalla`, `bloquear apps` | **Gap:** "ganar tiempo de pantalla" returns only 0–1-rating apps. Genuinely open. |
| de-DE | `bildschirmzeit`, `apps sperren`, `handysucht` | Unrot already runs "Verdien Bildschirmzeit" (4,858) — concept proven, still thin. |
| fr-FR | `temps d'écran`, `bloquer applications` | Opal (13k) dominant; go long-tail. |
| it-IT | `tempo di utilizzo` (Apple's own wording), `bloccare app` | Weak field overall. |
| pt-BR | `tempo de tela`, `bloquear aplicativos` | Opal (11k) leads. |
| ja-JP | `スマホ依存`, `アプリ制限`, **`勉強`/集中** | Every top app pairs blocking with **study**. Earnit's study-to-earn is the wedge. |
| ko-KR | `앱 차단`, `스크린타임`, **`공부 타이머`** | Same: every ranking app is "app block + study timer". |
| zh-Hans | `屏幕使用时间`, `自律`, `专注` | Framed as self-discipline, not blocking. |
| nl-NL | `schermtijd` | Blocus already uses "Verdien schermtijd". |
| pl-PL, tr-TR | `czas przed ekranem`, `ekran süresi` | Top results are **English-named** apps → these storefronts search partly in English; local-language competition is near zero. |
| ru-RU | `экранное время` | Scan rate-limited; treat as unverified. |
| ar-SA | (already live) | Keep — never drop a live locale. |

**Study is a bigger lever than walking in JP/KR**, and walking is the lever in
ES/LatAm. The per-locale keyword fields should reflect that, not translate en-US.

## Proposed assignment (needs your sign-off)

| Surface | Proposal | Chars |
|---|---|---|
| Name | `Earn Screen Time: Earnit` | 24/30 |
| Subtitle | `App Blocker & Digital Detox` | 27/30 |
| Keywords | `phone addiction,stop scrolling,self control,focus study timer,social media limit,brainrot,habit` | 95/100 |

Name is keyword-led with brand trailing (Rule 1). Subtitle spends its 30
characters on *new* words — app, blocker, digital, detox — rather than
repeating "screen time" (Rule 2); "digital detox" has real volume and the
strongest app on that SERP has only 452 ratings. The keyword field then adds
only words no other surface carries.

## To verify in ASO Scout

Look up **popularity** and **difficulty** for these, US storefront:

```
earn screen time        app blocker             digital detox
screen time             block apps              phone addiction
screen time limit       stop scrolling          self control
limit screen time       doomscrolling           brainrot
screen time control     social media blocker    study timer
```

Decision rules: the main keyword and subtitle keyword must be **clearly above
the popularity floor** (Rule 4) and **under ~50 difficulty** for an app with
few installs (Rule 5). If "earn screen time" comes back at floor popularity,
the fallback main keyword is `app blocker`, which has unambiguous volume but
higher difficulty — a bet on the future rather than on the next 90 days.
