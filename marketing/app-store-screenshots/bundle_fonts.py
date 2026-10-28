"""Optional maintenance: regenerate bundled subsets after copy changes.

Requires fonttools[woff]. Downloads pinned upstream TTFs once into ignored .build/fonts;
normal screenshot generation uses only the bundled WOFF2 files, without network access.
"""
import hashlib
import json
from pathlib import Path
from urllib.request import urlretrieve
from fontTools import subset
from fontTools.ttLib import TTFont
from make_l10n import ROOT

fonts = ROOT / 'src/fonts'
cache = ROOT / '.build/fonts'
cache.mkdir(parents=True, exist_ok=True)
for item in json.loads((fonts / 'sources.json').read_text()):
    source = cache / (item['family'] + '.ttf')
    if not source.exists():
        urlretrieve(item['url'], source)
    assert hashlib.sha256(source.read_bytes()).hexdigest() == item['sha256'], source
    data = json.loads((ROOT / 'l10n' / (item['locale'] + '.json')).read_text())
    text = ''.join(b for pairs in data['swaps'].values() for _, b in pairs) + '0123456789: /+.,–−'
    font = TTFont(source)
    options = subset.Options()
    options.layout_features = ['*']
    options.name_IDs = ['*']
    options.name_legacy = True
    sub = subset.Subsetter(options=options)
    sub.populate(text=text)
    sub.subset(font)
    font.flavor = 'woff2'
    font.save(fonts / (item['family'] + '.woff2'))
    print(item['family'])
