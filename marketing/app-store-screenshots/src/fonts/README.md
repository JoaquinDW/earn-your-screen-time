# Bundled screenshot fonts

These WOFF2 files are variable-font subsets of Noto fonts distributed by [Google Fonts](https://github.com/google/fonts). [Noto's usage guide](https://notofonts.github.io/noto-docs/website/use/) describes script-specific families and pairing Naskh Arabic with other serif faces.

`sources.json` records the pinned upstream URLs, SHA-256 checksums, locale and corresponding SIL Open Font License file for every font. All copyright and license notices are retained alongside the binaries and in their name tables. Subsets contain the screenshot text, ASCII numerals and punctuation; Latin pages retain the app's existing Instrument Serif and Figtree fonts. Italic display text uses browser-synthesized italics where the Noto family has no italic face.

To update after copy changes, install `fonttools[woff]` in a local environment and run `python3 bundle_fonts.py` from the screenshot directory, then `python3 verify.py --fonts`. Upstream files are cached under ignored `.build/fonts/`. Regular screenshot renders never fetch fonts.
