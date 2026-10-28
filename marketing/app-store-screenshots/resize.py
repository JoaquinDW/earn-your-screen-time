"""Produce smaller exports and one ten-frame contact sheet per language; verify all 60 PNGs."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
NAMES = [frame['name'] for frame in json.loads((ROOT / 'frames.json').read_text())]
SIZES = {'6.9-inch': (1290, 2796), '6.3-inch': (1206, 2622), '6.1-inch': (1179, 2556)}

for folder, size in SIZES.items():
    for lang in ('en-US', 'es'):
        target = ROOT / folder / lang
        target.mkdir(parents=True, exist_ok=True)
        if folder != '6.9-inch':
            for stale in target.glob('*.png'):
                stale.unlink()
            for name in NAMES:
                with Image.open(ROOT / '6.9-inch' / lang / f'{name}.png') as image:
                    image.convert('RGB').resize(size, Image.Resampling.LANCZOS).save(target / f'{name}.png')
        assert {image.stem for image in target.glob('*.png')} == set(NAMES), target
        for name in NAMES:
            with Image.open(target / f'{name}.png') as image:
                assert image.size == size, (image.filename, image.size)
        print(f'{folder}/{lang}: {len(NAMES)} PNGs verified at {size[0]} × {size[1]}')

previews = ROOT / 'previews'
previews.mkdir(exist_ok=True)
for lang in ('en-US', 'es'):
    width, height, gap, label = 258, 559, 12, 28
    sheet = Image.new('RGB', (len(NAMES) * (width + gap) + gap, height + label + gap * 2), '#F5F0E3')
    draw = ImageDraw.Draw(sheet)
    for index, name in enumerate(NAMES):
        x = gap + index * (width + gap)
        with Image.open(ROOT / '6.9-inch' / lang / f'{name}.png') as image:
            sheet.paste(image.convert('RGB').resize((width, height), Image.Resampling.LANCZOS), (x, gap + label))
        draw.text((x + 4, gap), name, fill='#0B1F45')
    sheet.save(previews / f'contact-sheet-{lang}.png')
    print(f'previews/contact-sheet-{lang}.png')
