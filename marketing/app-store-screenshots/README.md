# Earn Screen Time — App Store screenshots

Five PNGs in English (`en-US/`) and Spanish (`es/`, written in neutral *tú* Spanish so it works for es-MX and es-ES), in each size App Store Connect asks for:

| Folder | Size | App Store Connect slot |
| --- | --- | --- |
| `6.9-inch/` | 1290 × 2796 | iPhone 6.9" |
| `6.3-inch/` | 1206 × 2622 | iPhone 6.1" / 6.3" |
| `6.1-inch/` | 1179 × 2556 | iPhone 6.1" / 6.3" (older size) |

| # | Headline (EN) | Headline (ES) | Shows |
| --- | --- | --- | --- |
| 01 | Screen time? *Do 10 push-ups.* | ¿Más pantalla? *Haz 10 flexiones.* | The push-up camera mid-set (7 / 10) |
| 02 | Win back *your evenings.* | Recupera *tus noches.* | The "Your day" impact report and a 12-day streak |
| 03 | Every walk *earns you time.* | Cada paso *suma minutos.* | Home with the available balance and steps |
| 04 | Out of time? *Apps lock again.* | ¿Sin tiempo? *Todo se bloquea.* | The shield, 320 steps from the next reward |
| 05 | Spend it *on your terms.* | Úsalo *a tu manera.* | The 5 / 10 / 15 minute session picker |

**Look:** the icon's ivory and navy with cobalt as the only accent, Instrument Serif headlines and Figtree text (both bundled in `App/Resources/Fonts`), the store name and icon in the top-left of every shot. Push-ups lead because the camera is what sets the app apart, and only the first three shots show in search.

**In-phone screens** are HTML redraws of the real SwiftUI screens, with the app's own copy from `Localizable.xcstrings` and `PushupsLocalizable.xcstrings` and the illustrated scenes from `Assets.xcassets/Scenes`. The numbers are a sample day and agree across shots: 6,240 steps, 40 min earned, 14 skipped opens, a 12-day streak. `src/pushup.png` is an AI-generated photo supplied for shot 01.

**Badges** state product facts only (counting happens on device, no video is saved). Don't add download counts, ratings or quotes unless they're real.

## Editing

Edit the pages in `src/` (shared styles in `base.css` and `light.css`, the status bar and tick meters in `common.js`). Spanish copy is a list of exact string swaps in `make_es.py`; it fails loudly if an English string it expects has changed. Then run `./render.sh`, which needs Python 3 with Pillow and Node with Playwright and Chromium. It renders the 6.9" set and `resize.py` scales it down to the smaller sizes.

Nothing here uploads to App Store Connect.
