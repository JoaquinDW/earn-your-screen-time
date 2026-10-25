"""Verify dimensions/completeness and compare Spanish pixels to committed HEAD."""
import io
import json
import subprocess
from PIL import Image, ImageChops
from make_l10n import ROOT, LANGUAGES, PAGES

sizes = {'6.9-inch': (1290, 2796), '6.3-inch': (1206, 2622), '6.1-inch': (1179, 2556)}
count = 0
for folder, size in sizes.items():
    for lang in LANGUAGES:
        target = ROOT / folder / lang
        assert {f.name for f in target.glob('*.png')} == {f'{name}.png' for name in PAGES}, target
        for name in PAGES:
            with Image.open(target / f'{name}.png') as image:
                assert image.size == size, (target, name, image.size)
                count += 1
for lang in LANGUAGES:
    with Image.open(ROOT / 'previews' / f'{lang}.png') as image:
        assert image.size == (1500, 700), (lang, image.size)

# Explicit revision keeps the original reference after this work is committed.
baseline = (ROOT / 'l10n/spanish-baseline.txt').read_text().strip()
diffs = []
for folder in sizes:
    for name in PAGES:
        relative = f'marketing/app-store-screenshots/{folder}/es/{name}.png'
        original = subprocess.check_output(['git', 'show', f'{baseline}:{relative}'], cwd=ROOT)
        with Image.open(io.BytesIO(original)) as before, Image.open(ROOT / folder / 'es' / f'{name}.png') as after:
            difference = ImageChops.difference(before.convert('RGB'), after.convert('RGB'))
            assert difference.getbbox() is None, f'Spanish pixel regression: {relative}'
        diffs.append({'file': relative, 'changedPixels': 0})
report = {'images': count, 'languages': len(LANGUAGES), 'sizes': sizes,
          'spanishBaseline': baseline, 'spanishPixelDiffs': diffs}
(ROOT / 'previews/verification.json').write_text(json.dumps(report, indent=2) + '\n')
print(f'PASS: {count} PNGs, 14 contact sheets, 15 Spanish images pixel-identical to {baseline}.')
