"""Refresh bundled Noto subsets (maintenance only; normal builds stay offline).
Requires fonttools and brotli. Generate localized HTML before running this script.
Fonts and OFL licenses come from google/fonts; sources.json records blob hashes.
"""
import urllib.request,json,concurrent.futures,sys
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont
root=Path(__file__).resolve().parent/'src'
out=root/'fonts'; out.mkdir(exist_ok=True)
families={'notoserifjp':('ja','NotoSerifJP'),'notosansjp':('ja','NotoSansJP'),'notoserifkr':('ko','NotoSerifKR'),'notosanskr':('ko','NotoSansKR'),'notoserifsc':('zh-Hans','NotoSerifSC'),'notosanssc':('zh-Hans','NotoSansSC'),'notonaskharabic':('ar','NotoNaskhArabic'),'notosansarabic':('ar','NotoSansArabic'),'notoserif':('ru','NotoSerif'),'notosans':('ru','NotoSans')}
def run(item):
 family,(lang,name)=item
 listing=json.load(urllib.request.urlopen('https://api.github.com/repos/google/fonts/contents/ofl/'+family))
 asset=next(v for v in listing if v['name'].endswith('.ttf') and 'Italic' not in v['name'])
 download=Path('/tmp')/(name+'.ttf')
 if not download.exists(): download.write_bytes(urllib.request.urlopen(asset['download_url']).read())
 font=TTFont(download, recalcTimestamp=False)
 text=''.join(p.read_text() for p in root.glob('*.'+lang+'.html'))
 opts=subset.Options(); opts.flavor='woff2'; opts.layout_features=['*']; opts.name_IDs=['*']; opts.name_legacy=True; opts.name_languages=['*']
 sub=subset.Subsetter(options=opts); sub.populate(text=text); sub.subset(font)
 font.flavor='woff2'; font.save(out/(name+'.woff2'))
 license=urllib.request.urlopen('https://raw.githubusercontent.com/google/fonts/main/ofl/'+family+'/OFL.txt').read()
 (out/(name+'-OFL.txt')).write_bytes(license)
 return name,str(asset['sha']),asset['download_url'],(out/(name+'.woff2')).stat().st_size
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
 results=list(pool.map(run,families.items()))
for r in results: print(r)
(out/'sources.json').write_text(json.dumps(results,indent=2)+'\n')
