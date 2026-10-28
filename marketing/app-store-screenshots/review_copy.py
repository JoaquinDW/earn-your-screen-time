"""Write a native-review index of every screenshot-only string, from the swap provenance."""
import json
from pathlib import Path
from make_l10n import ROOT, LANGUAGES

out = ['# Screenshot translation review', '',
       'Every string below is screenshot copy, a composition, or a locale-formatted fixture outside the app catalogs. '
       'This includes copy adapted from the earlier five-frame drafts. Catalog values (including formatted values) '
       'are identified in `l10n/<language>.json` and omitted here. Names and punctuation are fixture data; Arabic standalone counters and clock numerals are formatting-only swaps in its table. '
       'These are screenshot translations, not new app localizations; native-speaker review is still recommended.', '',
       'English and Spanish retain the approved copy documented in [COPY_NOTES.md](COPY_NOTES.md).', '']
for lang in LANGUAGES[2:]:
    data = json.loads((ROOT / 'l10n' / f'{lang}.json').read_text())
    out += [f'## {lang}', '', '| English reference | Screenshot translation | Provenance |', '| --- | --- | --- |']
    for english, item in data['provenance'].items():
        if item['source'].startswith('xcstrings') or item['source'] in ('fixture name', 'fixture / symbol'):
            continue
        cells = [english, item['translation'], item['source']]
        out.append('| ' + ' | '.join(cell.replace('|', '\\|').replace('\n', '<br>') for cell in cells) + ' |')
    out.append('')
(ROOT / 'TRANSLATION_REVIEW.md').write_text('\n'.join(out))
