#!/bin/sh
# Rebuilds every App Store screenshot. Needs Node with Playwright and Chromium, and Python 3 with Pillow.
set -e
cd "$(dirname "$0")"
# CoreText and FreeType rasterize fonts differently. Use the pinned Linux x86
# renderer on macOS so the approved Spanish images remain pixel-identical.
if [ "$(uname -s)" = Darwin ] && [ "${SCREENSHOT_NATIVE:-0}" != 1 ]; then
  image=earnit-store-screenshots:1.62.1
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    docker build --platform linux/amd64 -t "$image" .
  fi
  repo_root=$(cd ../.. && pwd)
  exec docker run --rm --platform linux/amd64 --network none \
    -v "$repo_root:/work" -w /work/marketing/app-store-screenshots "$image" ./render.sh
fi
python3 make_l10n.py
node render.js
python3 resize.py
python3 previews.py
python3 verify.py
