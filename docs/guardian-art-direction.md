# Guardian Ethereal — art direction

The Guardian is the product's main emotional symbol. It is the visual representation of earning
control over your attention: **Move → Earn → Enjoy**. It replaces the retired landscape/trail
illustration entirely; nothing else may stand in for it.

## Style

- 2D watercolour / ink illustration, editorial illustration style
- human figure inspired by classical art — calm, introspective, elegant
- expressive but imperfect brush strokes; watercolour wash and ink texture
- **cobalt `#1E4DF7`** is earned energy, and the only accent
- **warm ivory / stone** ground: `#F6F3ED` at rest lifting to `#F9F6F1` at a fully earned day
- subtle orbital lines and abstract traces leaving the figure
- transparent background — the app paints the ivory ground and the atmosphere behind the artwork

## Avoid

3D renders · realistic CGI · fantasy-creature style · generic mascots · flat vector illustration ·
landscapes · paths, mountains, flags, checkpoints.

## The five states

The figure is the progress bar. There is no ring and no percentage anywhere in the product: how far
the day has come is read off the figure itself — how much of the frame it takes, how far the wings
reach, and how much cobalt has escaped into the air around it.

| Asset | Anchor | Pose |
|---|---|---|
| `guardian-resting` | 0.00 | Closed wings, introspective posture, almost no cobalt |
| `guardian-awakening` | 0.24 | Beginning movement, subtle blue strokes |
| `guardian-rising` | 0.55 | Wings opening, more energy |
| `guardian-strong` | 0.86 | Confident posture, wider composition |
| `guardian-free` | 1.00 | Fully opened wings, expressive cobalt movement |

Anchors are `GuardianState.anchor` in `App/DesignSystem/GuardianPortrait.swift`. The app reads
progress *between* two adjacent artboards and cross-fades them, so the screen wakes gradually
through the day instead of snapping between five poses.

## Export contract

- **Format:** PNG with a real alpha channel (no matte, no white box), sRGB, trimmed to the figure.
- **Height is the driver.** The app scales each artboard to the height `GuardianScale` gives that
  state — 202 pt at `resting` up to 470 pt at `free` — and the width follows the painting's own
  proportions. So an artboard may be portrait or landscape; compose it freely. Export at `@2x`, at
  least twice the point height (≈ 900 px for `resting`, ≈ 940 px for `free`); more is fine.
- **Registration:** every state must share the **same baseline** — the figure's feet, or wherever it
  meets the ground — and the same centre axis. The app anchors the figure to the floor of its stage
  and cross-fades adjacent states; a shifted baseline makes the dissolve slide.
- **Bleed:** at `free` the composition is meant to be wider than the phone and crop at both edges.
  Let wingtips and traces run to the canvas edge; do not inset them to "fit".
- **No baked background, no baked glow.** The floor weight, the washes, the orbits and the grain are
  drawn by `GuardianAtmosphere` underneath, and a baked-in version will double up.

### If the painting comes on a dark plate

Most generated art arrives with a black or vignetted ground. Do not key it out by luminance — that
eats the ink and the dark half of the wings. Use the repo's tool, which lifts the figure with the
system's foreground-instance mask and crops to it:

```sh
swift scripts/guardian-cutout.swift ~/painting.png \
  App/Resources/Assets.xcassets/Guardian/guardian-resting.imageset/guardian-resting@2x.png
```

## Dropping the artwork in

Put the files in `App/Resources/Assets.xcassets/Guardian/guardian-<state>.imageset/` and add their
`filename` to that imageset's `Contents.json` (`guardian-free@2x.png`, …). No Swift changes are
needed: `GuardianPortrait` checks which artboards ship and keeps the nearest painted state visible
until the next one lands, so the states can be added one at a time.

**Painted so far:** `resting`. The other four currently reuse that painting.
