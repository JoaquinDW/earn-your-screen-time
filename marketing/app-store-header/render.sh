#!/bin/sh
# Renders universal.svg to an opaque 5244x2950 PNG (App Store rejects alpha).
set -e
cd "$(dirname "$0")"
python3 generate.py
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=5244,2950 --screenshot="$PWD/universal-raw.png" "file://$PWD/universal.svg" 2>/dev/null
python3 - <<'EOF'
from PIL import Image
im = Image.open("universal-raw.png").convert("RGB")
assert im.size == (5244, 2950), im.size
im.save("earnit-universal-5244x2950.png", optimize=True)
im.resize((1311, 738), Image.LANCZOS).save("preview.png")
print("ok", im.size, im.mode)
EOF
rm universal-raw.png
