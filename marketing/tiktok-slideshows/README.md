# Earnit TikTok photo-mode slideshows

A local, offline HTML → Playwright → PNG tool. Six fixed formats, 24 starter
posts (three English + one Spanish per format), five reusable layouts. It has
no publishing, upload, scheduling, analytics or TikTok API integration.

## Render

From this directory, with Node 20+ and Playwright Chromium available:

```sh
node render.js f1-01-autopilot
node render.js --all
```

Equivalent npm commands: `npm run render -- f1-01-autopilot` or
`npm run render -- --all`. Commands work from any current directory when you
give the full path to `render.js`. The Codex desktop's bundled Playwright and
preinstalled Chromium are detected automatically. On another machine:

```sh
npm ci
npx playwright install chromium
```

To use another preinstalled Chromium, set `CHROMIUM_PATH` to its executable.
Rendering itself never downloads anything and rejects network requests.
Fonts, photos and app scenes are loaded locally. Keep this folder in the repo;
the phone renderer intentionally reuses `../app-store-screenshots/src/`, its
Spanish translation table, app resources and the bundled Instrument Serif /
Figtree fonts. The native overlays use bundled, OFL-licensed **TikTok Sans**.

Each render writes:

```text
out/<post-id>/01.png … 0N.png  # ordered 1080 × 1920 slides
out/<post-id>/caption.txt      # caption + 3–5 hashtags; draft warning if needed
out/<post-id>/qa.json          # bounds audits and missing-photo/asset notes
previews/<post-id>.png         # one contact sheet for visual review
```

`out/` is ignored. Sources, JSON posts and contact sheets are committed.
Screens cached in `out/.screens/` are regenerated on every render, so changes
to the source UI are picked up. The contact sheets show the exported slides;
their headers describe readiness and whether solid backgrounds were used.

## Create a post

```sh
node new-post.js f1-listicle f1-your-topic en
# or: npm run new-post -- f1-listicle f1-tu-tema es
```

This creates `posts/<id>.json` with **empty** copy slots, the format's ordered
slide IDs, its background photo slots and product screen choices. It refuses
to overwrite an existing post. Fill the copy, topic, caption and hashtags.
Use lowercase, conversational copy; Spanish uses neutral **tú**.

- Hook: at most 12 words. Other slides: at most 25 words across all copy slots
  (including the fixed Earnit name on CTA slides). Slot-specific character
  limits are in the format. Product UI and draft labels are separate from
  editorial copy.
- Caption: at most 150 Unicode characters, with 3–5 hashtags in the separate
  `hashtags` array. No invented results, testimonials or popularity claims.
- `sources`: `{ "claim": "…", "url": "https://…" }` for sourced claims;
  `repo:…` links identify product mechanics. Real seven-day measurements must
  have a source beyond the product code (for example a real log).
- `image`: path under `images/`, or `null`. PNG, JPEG and WebP are supported.
  Missing photos use the chosen `fallback`: `ivory`, `navy` or `cobalt`.
- `screen`: `shield`, `pushups`, `earned`, `running`, `sessions` or `report`.
  Earning does not unlock apps by itself; the session does. `running` reuses
  the home artwork and the actual active-session band's labels/structure from
  `DashboardHome.swift` and `Localizable.xcstrings`.
- F6 `app`: `duolingo`, `nyt-games`, `nike-run-club` or `earnit`. Three phones
  are rendered per app. The hook's `fromApps` / `toApps` control the icon swap.

Then validate, mark complete copy/assets `"status": "ready"`, and render:

```sh
node render.js f1-your-topic --validate
node render.js f1-your-topic --ready
```

`--ready` refuses drafts, unfilled `{{placeholders}}` and missing third-party
assets. It still allows the explicitly supported solid photo fallbacks.
Default rendering accepts drafts so templates can be previewed. Draft captions
contain a warning; missing data/assets also have visible labels on their slides.
Neither command posts anything.

## Starter formats

| Format | Slides | Structure |
| --- | ---: | --- |
| `f1-listicle` | 6 | Hook → three non-product tips → Earnit as tip four → best tip + save |
| `f2-pov-pushups` | 6 | Shield hook → counter → banked minutes → running 10-minute session → relock → find |
| `f3-limits-dont-work` | 6 | Override loop → temptation → earn beforehand → Earnit → find |
| `f4-seven-days` | 7 | Hook → paired days 1–6 → day 7 → totals → observation |
| `f5-evening-before-after` | 7 | Three alternating hypothetical before/after pairs → Your day |
| `f6-app-list` | 6 | Icon swap → language → puzzle → running → Earnit → save/find |

F4's **four starters are templates**, with obvious placeholders for every
measurement and observation. Replace these with your real log and source;
there are no fictional diaries. F5 describes possible choices, not personal
before/after results. Its report is the existing Your day screen with numbers
replaced by dashes. All exported product screens are labeled examples, and
sample streak/outcome badges from the App Store artwork are excluded.

F6's **four starters are asset drafts** until you supply genuine third-party
icons and screenshots. See [the asset manifest](images/third-party/README.md).
The committed placeholders are deliberately blank and labeled. The descriptions
are sourced in each post; none of the featured alternatives is a competing
screen-time blocker. Earnit's icon and three screens are available now.

## Add photos

See [IMAGE_PROMPTS.md](IMAGE_PROMPTS.md) for six text-free, photorealistic photo
briefs and exact filenames. Drop the photos into `images/` and render again.
Native formats put white/outlined TikTok-style text over the full-bleed photo;
body slides use optional yellow/blue outline text as in research A. Without
photos, the explicit solid fallbacks keep all formats usable. Clean-list slides
always use light gray, black sans headings, icons and three phones as in research B.

The current brief's native sans direction takes precedence over the earlier
serif-hook bullet. The App Store's brand typography stays inside the phones.
Research images are references only and are never read by the renderer.

## Add a format

1. Copy a JSON file in `formats/`, give it a unique lowercase hyphenated `id`,
   set `family` to `native` or `clean-list`, and define 5–7 slides.
2. Each slide has a unique ordered `id`, a descriptive `role`, `layout`,
   `slots` mapping (`title` / optional `body`, each with `maxChars`), `image`
   and `fallback`. Product slides use `screen` or `app`; icon hooks use
   `iconSwap: true`. Set `requiresEvidence: true` for real-result formats.
3. Choose an HTML fragment from `layouts/`: `text-hook`, `text-body`,
   `photo-caption`, `product` or `cta`. Values are escaped before interpolation;
   JSON copy is text, never HTML. If adding a layout, register it in
   `lib/model.js`, supply its fragment and style it in `layouts/base.css`.
4. Run `new-post`, fill the slots, validate and render. Review the contact sheet
   again after any copy, asset or layout change.

The canvas is 1080 × 1920. Key content must stay in **x=60…960, y=150…1520**;
normal copy is inset farther to x=80…928. Every render checks safe bounds,
overflow, phone/heading collisions, missing images, failed fonts/resources and
network requests. It fails instead of exporting a clipped slide. Native hooks
stay large enough to read in a contact sheet. The renderer rejects hidden
feature and competitor words in editorial copy and checks reused phone UI too.

## Checks and visual review

```sh
npm run validate
npm test
node render.js --all
```

The tests cover copy limits, batch counts/languages, forbidden copy, evidence,
asset readiness, path validation and safe post creation. The complete render is
the layout check. Open **every** `previews/*.png`: check hooks at thumbnail size,
safe-zone spacing, legibility, clips, photo composition and replacement assets.
Automated checks cannot establish that a claim or personal log is true; the
editor remains responsible for the source. No app code or state is modified.
