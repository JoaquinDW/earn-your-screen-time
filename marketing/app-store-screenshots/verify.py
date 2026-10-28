"""Check the deliverables; optionally compare approved pixels and audit font coverage."""
import argparse
import io
import json
import subprocess
import unicodedata
from pathlib import Path
from PIL import Image, ImageChops
from make_l10n import ROOT, LANGUAGES

parser = argparse.ArgumentParser()
parser.add_argument('--baseline', help='Git revision containing the approved EN/ES exports')
parser.add_argument('--fonts', action='store_true', help='Audit bundled glyph coverage (requires FontTools)')
args = parser.parse_args()
frames = json.loads((ROOT / 'frames.json').read_text())
names = {f['name'] + '.png' for f in frames}
exports = ROOT / '6.3-inch'
assert {p.name for p in exports.iterdir() if p.is_dir()} == set(LANGUAGES)
assert not (ROOT / '6.9-inch').exists() and not (ROOT / '6.1-inch').exists()
for lang in LANGUAGES:
    assert {p.name for p in (exports / lang).glob('*.png')} == names, lang
    for name in names:
        with Image.open(exports / lang / name) as image:
            assert image.size == (1206, 2622), (lang, name, image.size)
    assert (ROOT / 'previews' / f'contact-sheet-{lang}.png').exists()
print('140 exports verified: 14 languages × 10 frames, all 1206 × 2622; 14 previews')

if args.baseline:
    repo = Path(subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', '--show-toplevel'], text=True).strip())
    for lang in ['en-US', 'es']:
        for name in sorted(names):
            file = exports / lang / name
            old_bytes = subprocess.check_output(['git', '-C', str(repo), 'show', f'{args.baseline}:{file.relative_to(repo)}'])
            with Image.open(io.BytesIO(old_bytes)) as old, Image.open(file) as new:
                assert ImageChops.difference(old.convert('RGB'), new.convert('RGB')).getbbox() is None, file
    print(f'EN/ES: 20 exports pixel-identical to {args.baseline}')

if args.fonts:
    from fontTools.ttLib import TTFont
    mapping = {'ja': ('NotoSansJP', 'NotoSerifJP'), 'ko': ('NotoSansKR', 'NotoSerifKR'),
               'zh-Hans': ('NotoSansSC', 'NotoSerifSC'), 'ru': ('NotoSans', 'NotoSerif'),
               'ar': ('NotoSansArabic', 'NotoNaskhArabic')}
    for lang in LANGUAGES[2:]:
        data = json.loads((ROOT / 'l10n' / f'{lang}.json').read_text())
        text = ''.join(item['translation'] for item in data['provenance'].values())
        if lang in mapping:
            files = [ROOT / 'src/fonts' / (f + '.woff2') for f in mapping[lang]]
        else:
            files = [ROOT.parents[1] / 'App/Resources/Fonts' / (f + '.ttf') for f in
                     ['InstrumentSerif-Regular', 'InstrumentSerif-Italic', 'Figtree-Regular', 'Figtree-SemiBold', 'Figtree-Bold']]
        for file in files:
            cmap = TTFont(file).getBestCmap()
            missing = {c for c in text if ord(c) not in cmap and unicodedata.category(c)[0] in 'LMN'}
            assert not missing, (lang, file, missing)
    print('Every translated letter, combining mark and digit is covered in both font families')
