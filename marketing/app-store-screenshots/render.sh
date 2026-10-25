#!/bin/sh
# Rebuilds every App Store screenshot. Needs Node with Playwright and Chromium, and Python 3.
set -e
cd "$(dirname "$0")"
python3 make_es.py
node render.js
rm -f src/*.es.html
