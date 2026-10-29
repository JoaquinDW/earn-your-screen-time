# App-list asset slots

Supply authentic app icons/screenshots yourself. The committed `*.placeholder.svg`
files are labeled empty slots, **not** recreations of any third-party artwork.
The renderer automatically prefers `.png`, then `.jpg`, then `.webp`; leave the
placeholder files in place as the fallback. No asset scraping or publishing runs.

| Directory | Files to add |
| --- | --- |
| `tiktok/`, `instagram/`, `x/` | `icon.png` |
| `duolingo/`, `nyt-games/`, `nike-run-club/` | `icon.png`, `01.png`, `02.png`, `03.png` |

Icons: square, at least 256 px. Screens: preferably 393 × 858 (or the same ratio),
with the **screen content only**, no surrounding device frame or marketing text.
The renderer adds the phone frame. All screenshots use `object-fit: cover`;
check the contact sheet after replacing them. There are three phones per app.
Avoid names, accounts or personal statistics you do not want in the output.

Earnit uses its real repository app icon and three reused phone screens:
shield, push-up counter and session picker. No third-party assets are needed
for Earnit. The other apps are language, puzzle and running alternatives;
none is a screen-time blocker. Source URLs are recorded in the f6 post JSONs.

F6 starters are drafts. After supplying every asset, change the post's `status`
to `ready` and run `node render.js <id> --ready`. This fails if a slot is missing.
