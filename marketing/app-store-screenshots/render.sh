#!/bin/sh
# Needs Python 3 with Pillow and Node with Playwright and Chromium.
set -eu
cd "$(dirname "$0")"
# Generated translations are temporary, even when rendering fails.
trap 'rm -f src/*.es.html' EXIT
python3 make_es.py
node render.js
python3 resize.py
