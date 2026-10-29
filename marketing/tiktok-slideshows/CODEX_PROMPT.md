You're working in the repo `earn-your-screen-time` (iOS app "Earn Screen Time", called Earnit on the device). Goal: build a small local tool that produces TikTok photo-mode slideshows for Earnit in volume, from a fixed set of formats. Work on a new branch and open a PR. Don't post anything anywhere.

## Context

We want to test TikTok slideshows (carousel posts of 5–7 vertical images) as an organic acquisition channel. The strategy: pick formats that already work in the screen-time niche, then produce many variations of each (different hooks and topics) and see which ones travel. The tool's job is to make each variation cheap: format + topic in, a ready-to-upload slideshow out.

## What already exists (read these first)

- `.agents/product-marketing.md`: product context, positioning, objections. **Study to Earn is hidden in the app now**: never mention study, books or scanning.
- `marketing/app-store-screenshots/`: the visual system (`base.css`, `light.css`, bundled Instrument Serif + Figtree fonts), the HTML → Playwright → PNG render pipeline, and the rendered screenshots in `6.3-inch/<lang>/` (01-hook, 02-pushups, 03-walk, 04-exercises, 05-lock, 06-sessions, 07-schedule, 08-outcome, 09-friends, 10-privacy). Reuse the pipeline approach and the fonts. Use the in-phone screens from these screenshots as the "product" slides (crop the phone or reuse the HTML screens).
- `marketing/tiktok-static-ads/`: earlier static ads, for tone.
- `marketing/tiktok-slideshows/research/`: **real TikTok slideshows that are working in this niche** (screenshots + `notes.md`). Read the notes and look at every image before designing anything. They're the reference for structure *and* visual style. Copy the structure and look, never the images or text.

## Visual direction (from the research)

What works in this niche looks **native to TikTok**, not like an ad. Build two style families:

- **Native** (default for f1, f2, f3, f5): a full-bleed, real-looking, dim, cozy photo (desk at night, bed, candle, journal) with text in TikTok's own in-app styles. That means lowercase, casual copy, a TikTok-like sans font (bundle a free one similar to TikTok Sans / Proxima), white text with a soft shadow or a black outline, and an optional colored outlined body text (for example yellow fill with a blue outline). No brand colors, no logos except on the product slide.
- **Clean list** (for f6): a light-gray background, bold black sans headings, real app icons, and 3 phone mockups per app slide.

The App Store ivory/navy/serif system is only for the Earnit product screens inside the phone mockups.

## What to build: `marketing/tiktok-slideshows/`

1. **`formats/*.json`**: one file per format. Each defines the slide sequence: for every slide its role (hook, value, product, cta…), a layout name, and copy slots with max character counts. Start with these six formats (full intent below): `f1-listicle`, `f2-pov-pushups`, `f3-limits-dont-work`, `f4-seven-days` (template only, filled with real data later), `f5-evening-before-after`, `f6-app-list`.
2. **`posts/<id>.json`**: one file per slideshow: the format id, the language (`en` or `es`), the filled copy for each slide, which image each slide uses, plus the TikTok caption (≤ 150 characters) and 3–5 hashtags.
3. **`layouts/`**: 4–5 HTML slide layouts at 1080×1920:
   - `text-hook`: very large serif headline on a solid or photo background. It has to be readable as a thumbnail.
   - `text-body`: a short title plus 1–3 lines.
   - `photo-caption`: a full-bleed photo with a caption band.
   - `product`: an app screen inside a phone frame, with one line above it.
   - `cta`: the app icon, "Earnit" and one line, for example "Search Earnit on the App Store".
   - Keep all text inside TikTok's safe zone: nothing in the top ~150 px or the bottom ~400 px, and keep the right ~120 px clear of key text.
4. **`render.js`** plus a `Makefile` target or npm script: `render <post-id>` or `render --all` writes `out/<post-id>/01.png … 0N.png` and `out/<post-id>/caption.txt`. Use Playwright with the preinstalled Chromium, like the screenshot pipeline.
5. **`images/`**: background photos. The tool must work without them: fall back to the ivory/navy/cobalt solid backgrounds. Add `IMAGE_PROMPTS.md` with one image-generation prompt per photo slot the formats need: candid phone-in-bed at night, a person walking at dusk, push-ups on a living-room floor, a phone face-down on a table. Make them photorealistic, vertical and text-free, and keep phones in the photos generic, with no real app UI. I'll generate the images myself and drop them in. They should look like real, slightly imperfect phone photos (warm, dim, cozy) like the research examples, not glossy stock.
6. **`new-post`** helper (a script or a README recipe): copies a format into a new `posts/<id>.json` with the slots empty, so that I or an AI can fill them in.
7. **24 starter posts**: 4 per format (24 in total), 18 in English and 6 in Spanish. Write the copy yourself, following the rules below. Render them all, then make one contact sheet per post in `previews/`.

## The six formats

- **f1-listicle**: "5 things that actually stopped my doomscrolling". Slides 1–4 are genuine non-product tips (grayscale, charging the phone outside the bedroom, turning notifications off, and so on). The product appears as one tip, in slide 4 or 5. The last slide holds the best tip plus "save this".
- **f2-pov-pushups**: "POV: your phone makes you do push-ups before TikTok". The slides go: shield screen → camera counting push-ups → minutes earned → a 10-minute session running → "then it locks again".
- **f3-limits-dont-work**: "Screen Time limits don't work. Here's why." The slides cover the "Ignore limit" button and deciding in the moment of temptation, then earning the time beforehand, then Earnit.
- **f4-seven-days**: "I used Earnit for 7 days": one slide per day, or a summary. Build the template only, with obvious `{{placeholders}}` for real numbers. Don't fill it with invented data.
- **f6-app-list**: "Apps to use instead of doomscrolling", modeled on research example B. Slide 1 shows the bad app icons, an arrow, then the good app icons. Each slide after that covers one app: its icon, name and one-line description, plus 3 phone screenshots. Earnit is one of the good apps, with its 3 screens being the shield, the push-up counter and the sessions picker. The other apps are genuine non-competing alternatives (language, reading, puzzle or running apps). Never include screen-time blockers. Put the third-party icons and screenshots in `images/third-party/` as placeholders; I'll supply the real ones.
- **f5-evening-before-after**: "Your evening at 11pm vs. your evening when Instagram is locked". Alternating before/after slides, ending on the "Your day" report screen.

## Copy rules

1. **No invented proof.** No testimonials, ratings, download counts or made-up personal results ("my screen time went from 7h to 2h"). Write in the second person, or as the app's founder describing why they built it. Leave statistics out unless you cite a real source in `posts/<id>.json` under `sources`.
2. Only describe features that exist: blocked apps stay locked; you earn minutes by walking (Apple Health steps) or by camera-counted exercises (push-ups, squats, lunges, jumping jacks); you spend them in 5-, 10- or 15-minute sessions, then the apps lock again; blocking schedules and strict mode; friends and streaks; on-device counting with no video saved.
3. The hook slide has 12 words at most. The other slides have 25 words at most. Write casually, like a normal TikTok post, not like an ad.
4. Spanish uses neutral *tú*, as in the App Store screenshots.
5. Don't mention or show screen-time competitors (Opal, One Sec, ScreenZen, Unrot, etc.). Non-competing apps are fine in f6.

## Finish

1. Look at every contact sheet yourself. Check for text outside the safe zone, clipped or overflowing text, unreadable hooks at thumbnail size, and any trace of Study. Fix the problems and re-render.
2. Write a `README.md` that covers how to add a format, how to create and render a post, and where the output goes.
3. Commit the sources, the starter posts and the previews. Don't commit `out/`; add it to `.gitignore`.
4. Open the PR and attach 3–4 contact sheets to its description.
