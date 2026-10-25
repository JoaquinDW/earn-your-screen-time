# Earn Screen Time — App Store screenshots

Five shots in **14 languages**, covering all **16 store locales**. The English
and neutral *tú* Spanish sets are the approved references; the other twelve sets
are localized for review. **Upload is pending the user's approval of the contact
sheets. No screenshots have been uploaded or deleted in this pass.**

| Folder | PNG dimensions | Planned App Store Connect display type |
| --- | --- | --- |
| `6.9-inch/` | 1290 × 2796 | `APP_IPHONE_67` |
| `6.3-inch/` | 1206 × 2622 | `APP_IPHONE_61` |
| `6.1-inch/` | 1179 × 2556 | Additional local export; not planned for upload |

These are the requested upload targets. Confirm accepted sizes using the API
before uploading; do not infer acceptance from the folder names.

| Store locale | Render language | Contact sheet |
| --- | --- | --- |
| ar-SA | ar | [Arabic](previews/ar.png) |
| de-DE | de | [German](previews/de.png) |
| en-GB, en-US | en-US | [English](previews/en-US.png) |
| es-ES, es-MX | es | [Spanish](previews/es.png) |
| fr-FR | fr | [French](previews/fr.png) |
| it | it | [Italian](previews/it.png) |
| ja | ja | [Japanese](previews/ja.png) |
| ko | ko | [Korean](previews/ko.png) |
| nl-NL | nl | [Dutch](previews/nl.png) |
| pl | pl | [Polish](previews/pl.png) |
| pt-BR | pt-BR | [Brazilian Portuguese](previews/pt-BR.png) |
| ru | ru | [Russian](previews/ru.png) |
| tr | tr | [Turkish](previews/tr.png) |
| zh-Hans | zh-Hans | [Simplified Chinese](previews/zh-Hans.png) |

[Review all contact sheets](previews/index.html). Each sheet is 1500 × 700 and
shows 01→05 side by side; the gallery links each full-size shot separately.

| # | Idea | Shows |
| --- | --- | --- |
| 01 | More screen time? Do 10 push-ups. | Push-up camera mid-set (7 / 10), with factual privacy badges |
| 02 | Win back your evenings. | Your day report and a 12-day streak |
| 03 | Every walk earns time. | Available balance and steps |
| 04 | Out of time? Apps lock again. | Shield, 320 steps from the next reward |
| 05 | Spend it on your terms. | 5 / 10 / 15-minute session picker |

**Look:** the icon's ivory and navy with cobalt as the only accent. Instrument
Serif headlines and Figtree text remain the Latin system. Headlines keep exactly
two lines: navy, then cobalt italic. Localized lines shrink together to fit.
The store name and icon remain in every shot. Push-ups lead because the camera
sets the app apart, and only the first three shots show in search.

**In-phone screens** redraw the SwiftUI screens with the app's copy from
`Localizable.xcstrings` and `PushupsLocalizable.xcstrings`, and illustrated scenes
from `Assets.xcassets/Scenes`. English-value lookup resolves catalog keys at build
time, including parameterized values; duplicate English values use the relevant
screen's key when needed. Missing UI translations are authored in `l10n/copy.json`.
Marketing headlines/subtitles are written separately. Arabic text uses RTL and
Arabic-Indic digits; phone geometry, photography and tilt remain unchanged.

The sample day agrees across languages: 6,240 steps, 40 min earned (30 from steps
and 10 from push-ups), 14 skipped opens and a 12-day streak. There are 25 minutes
available, leaving 15 after the selected 10-minute session. Counts and durations
are formatted per language. `src/pushup.png` is the supplied AI-generated photo.

**Badges** translate only the original product facts: repetitions are counted on
the device and video is never saved. No ratings, download counts or testimonials
are added.

## Build and verify

Run from this directory:

```sh
./render.sh
```

On macOS this builds the pinned Linux x86 Docker image once, then runs the build
with networking disabled. Setup needs Docker and network access to install the
pinned dependencies. Normal renders are offline. The Linux image, Playwright
1.62.1 / Chromium 151.0.7922.34, Pillow 11.3.0 and Chromium's
`--font-render-hinting=none --disable-lcd-text` settings plus DejaVu symbol fallbacks reproduce the committed
Spanish PNGs. Native macOS CoreText rendering changes antialiasing; use the
container for canonical exports. The image is `earnit-store-screenshots:1.62.1`;
rebuild it with `docker build --platform linux/amd64 -t earnit-store-screenshots:1.62.1 .`
if its dependency files change.

On a Linux host, install `npm ci`, `npx playwright install --with-deps chromium`
and `python3 -m pip install -r requirements.txt` first. Canonical pixel comparisons
use the pinned Docker image with `--platform linux/amd64`. `SCREENSHOT_NATIVE=1`
bypasses Docker on macOS for exploratory rendering; strict pixel verification
will fail if the rasterizer differs.

The pipeline:

1. `make_l10n.py` writes `src/<name>.<lang>.html`, asserting each English source
   swap appears **exactly once**. `l10n/es.json` retains the original Spanish table
   and its 176px headline rule exactly. Generated HTML is ignored by Git.
2. `render.js` writes five 1290×2796 PNGs per language. It loads bundled resources
   only, fits headlines/labels, checks clipping and verifies through Chromium's
   font API that native script letters use custom bundled faces. Decorative symbols and emoji
   are excluded from the native-script font assertion.
3. `resize.py` exports both smaller sizes with Lanczos resampling.
4. `previews.py` builds all contact sheets and the review gallery.
5. `verify.py` checks all **210 PNG dimensions**, all 14 sheets, and pixel-compares
   every Spanish image in all three sizes against the committed baseline in
   `l10n/spanish-baseline.txt`. Any changed Spanish pixel fails the build.

`previews/layout.json` records headline sizes, line bounds and script font names;
`previews/verification.json` records dimensions and the 15 Spanish pixel diffs.
For first-page font inspection, run `python3 make_l10n.py` then
`node render.js --first` inside the pinned container. `--lang=ja` restricts rendering
to one language. Inspect the output before a full batch when changing fonts/copy.

## Fonts

`src/fonts/` bundles OFL-licensed Noto Serif/Sans JP, KR and SC, Noto Serif/Sans for
Cyrillic, and Noto Naskh/Sans Arabic. Each face is subset to the localized pages;
variable weights, shaping tables and license/name records are retained. The
original Latin faces remain under `App/Resources/Fonts`.

Each Noto family has its own OFL license beside the WOFF2; `sources.json` records
its upstream Google Fonts URL and Git blob hash. To refresh subsets after adding
characters, generate the HTML, install `fonttools` and `brotli`, then run
`python3 bundle_fonts.py`. This maintenance command fetches upstream fonts;
`render.sh` never fetches font resources.

## App Store Connect handoff

A read-only API request on 2026-10-24 found draft **1.3.3** in
`PREPARE_FOR_SUBMISSION`. Discover the editable version again at upload time.
After contact-sheet approval, follow the screenshot upload/verification steps in
[ASO Phase 3](../../aso/README.md#phase-3--screenshots), record the actual accepted
display types and final 32-set readback there, and update this status. Do not
submit for review or change metadata, prices or builds.
