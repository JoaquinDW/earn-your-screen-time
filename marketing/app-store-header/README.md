# Earnit — App Store header + search creative (Universal)

**Asset:** `earnit-universal-5244x2950.png` — 5244 × 2950 (16:9), opaque PNG, no text.
**Placements:** product page header and search results (App Store Connect › Encabezado y resultados de la búsqueda), iOS/iPadOS 27+.
**Concept C:** a twilight landscape in the style of the in-app Scenes. Blue step lights along a path lead a walker toward the app's unlock/hourglass mark rising over the horizon: movement earns the time. Because it has no copy, one asset serves every locale.

- The mark sits centered and above the middle, inside Apple's art safe area. It survives both the 21:9 header crop and the 3:2 search crop.
- Edit `generate.py`, then run `./render.sh`. That rebuilds `universal.svg`, the final PNG and a small `preview.png` (needs Google Chrome and Pillow).
- Before submitting, check the in-console **Vista previa**. Apple overlays the icon and title on the header and doesn't publish exact overlay bounds.
