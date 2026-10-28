"""Export only the 6.3-inch slot, and build previews from those deliverables."""
import json
from pathlib import Path
from PIL import Image, ImageDraw
from make_l10n import LANGUAGES

ROOT = Path(__file__).resolve().parent
NAMES = [frame['name'] for frame in json.loads((ROOT / 'frames.json').read_text())]
SIZE = (1206, 2622)

for lang in LANGUAGES:
    target = ROOT / '6.3-inch' / lang
    target.mkdir(parents=True, exist_ok=True)
    for stale in target.glob('*.png'):
        stale.unlink()
    for name in NAMES:
        with Image.open(ROOT / '.build' / lang / f'{name}.png') as image:
            assert image.size == (1290, 2796), (image.filename, image.size)
            image.convert('RGB').resize(SIZE, Image.Resampling.LANCZOS).save(target / f'{name}.png')
    assert {image.stem for image in target.glob('*.png')} == set(NAMES), target
    for name in NAMES:
        with Image.open(target / f'{name}.png') as image:
            assert image.size == SIZE, (image.filename, image.size)
    print(f'6.3-inch/{lang}: {len(NAMES)} PNGs verified at 1206 × 2622')

previews = ROOT / 'previews'
previews.mkdir(exist_ok=True)
for lang in LANGUAGES:
    width, height, gap, label = 258, 561, 12, 28
    sheet = Image.new('RGB', (len(NAMES) * (width + gap) + gap, height + label + gap * 2), '#F5F0E3')
    draw = ImageDraw.Draw(sheet)
    for index, name in enumerate(NAMES):
        x = gap + index * (width + gap)
        with Image.open(ROOT / '6.3-inch' / lang / f'{name}.png') as image:
            sheet.paste(image.convert('RGB').resize((width, height), Image.Resampling.LANCZOS), (x, gap + label))
        draw.text((x + 4, gap), name, fill='#0B1F45')
    sheet.save(previews / f'contact-sheet-{lang}.png')
    print(f'previews/contact-sheet-{lang}.png')
