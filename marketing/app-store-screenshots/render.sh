#!/bin/sh
# Needs Python 3 with Pillow, Node with Playwright, and Playwright Chromium.
set -eu
cd "$(dirname "$0")"
# Remove only generated manifest pages, including after a failed render.
trap 'python3 make_l10n.py --clean' EXIT
python3 make_l10n.py
FIRST_PASS='' LANGUAGES='' node render.js
python3 resize.py
