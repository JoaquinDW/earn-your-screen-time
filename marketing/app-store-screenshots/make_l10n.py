"""Generate temporary pages from one exact, once-only swap table per language."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / 'src'
LANGUAGES = ['en-US', 'es', 'de', 'fr', 'it', 'pt-BR', 'nl', 'pl', 'tr', 'ru', 'ja', 'ko', 'zh-Hans', 'ar']


def generate():
    frames = json.loads((ROOT / 'frames.json').read_text())
    names = {frame['name'] for frame in frames}
    for lang in LANGUAGES[1:]:
        table = json.loads((ROOT / 'l10n' / f'{lang}.json').read_text())['swaps']
        assert set(table) == names, (lang, 'Frame set differs from manifest')
        for name, pairs in table.items():
            source = (SRC / f'{name}.html').read_text()
            for english, localized in pairs:
                assert source.count(english) == 1, (lang, name, english, source.count(english))
                source = source.replace(english, localized)
            attrs = f'lang="{lang}"' + (' dir="rtl"' if lang == 'ar' else '')
            source = source.replace('<html>', f'<html {attrs}>').replace('<html lang="en">', f'<html {attrs}>')
            if lang != 'es':
                source = source.replace('</head>', '<link rel="stylesheet" href="l10n.css"></head>')
            (SRC / f'{name}.{lang}.html').write_text(source)


def cleanup():
    for frame in json.loads((ROOT / 'frames.json').read_text()):
        for lang in LANGUAGES[1:]:
            (SRC / f'{frame["name"]}.{lang}.html').unlink(missing_ok=True)


if __name__ == '__main__':
    cleanup() if '--clean' in sys.argv else generate()
