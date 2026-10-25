"""Five screenshots side by side, one contact sheet per rendered language."""
from PIL import Image, ImageDraw
from make_l10n import ROOT, LANGUAGES, PAGES, STORE_LOCALES
from html import escape

out = ROOT / 'previews'
out.mkdir(exist_ok=True)
for lang in LANGUAGES:
    canvas = Image.new('RGB', (5 * 300, 700), '#F5F0E3')
    draw = ImageDraw.Draw(canvas)
    stores = ', '.join(locale for locale, value in STORE_LOCALES.items() if value == lang)
    draw.text((16, 10), f'{lang} | {stores}', fill='#0B1F45', font_size=18)
    for i, name in enumerate(PAGES):
        with Image.open(ROOT / '6.9-inch' / lang / f'{name}.png') as image:
            canvas.paste(image.convert('RGB').resize((300, 650), Image.Resampling.LANCZOS), (i * 300, 40))
    canvas.save(out / f'{lang}.png')
    print(f'previews/{lang}.png')

names = {'en-US': 'English', 'es': 'Español', 'de': 'Deutsch', 'fr': 'Français',
         'it': 'Italiano', 'ja': '日本語', 'ko': '한국어', 'nl': 'Nederlands',
         'pl': 'Polski', 'pt-BR': 'Português (Brasil)', 'ru': 'Русский',
         'tr': 'Türkçe', 'zh-Hans': '简体中文', 'ar': 'العربية'}
cards = []
for lang in LANGUAGES:
    stores = ', '.join(k for k, v in STORE_LOCALES.items() if v == lang)
    links = ' '.join(f'<a href="../6.9-inch/{lang}/{page}.png" target="_blank">{i:02}</a>' for i, page in enumerate(PAGES, 1))
    cards.append(f'<section id="{lang}"><header><h2>{escape(names[lang])}</h2><span>{stores}</span>'
                 f'<nav aria-label="Full-size screenshots">{links}</nav></header>'
                 f'<a href="{lang}.png" target="_blank"><img loading="lazy" src="{lang}.png" '
                 f'width="1500" height="700" alt="Five {escape(names[lang])} App Store screenshots"></a></section>')
document = '''<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Earnit — Screenshot review</title>
<style>
@font-face{font-family:Instrument;src:url('../../../App/Resources/Fonts/InstrumentSerif-Regular.ttf')}
@font-face{font-family:Figtree;src:url('../../../App/Resources/Fonts/Figtree-Regular.ttf')}
*{box-sizing:border-box}body{margin:0;background:#F5F0E3;color:#0B1F45;font-family:Figtree,sans-serif}
main{max-width:1564px;margin:auto;padding:48px 32px}h1{font:clamp(40px,5vw,76px)/1.02 Instrument,serif;margin:16px 0}
.intro{max-width:720px;line-height:1.6}.status{font-size:13px;text-transform:uppercase;letter-spacing:.12em;color:#2E5CE6}
.jump{display:flex;flex-wrap:wrap;gap:8px;margin:28px 0 48px}.jump a{padding:10px 14px;border:1px solid #ccd0d8;border-radius:24px}
a{color:inherit;text-decoration:none}a:hover{color:#2E5CE6}a:focus-visible{outline:3px solid #2E5CE6;outline-offset:4px}
section{margin:0 0 48px;scroll-margin-top:20px}header{display:flex;align-items:baseline;gap:20px;border-top:1px solid #cdd0d5;padding:16px 0}
h2{font-size:22px;margin:0}header span{color:#3B4A68;font-size:14px}nav{margin-left:auto;display:flex;gap:14px;font-variant-numeric:tabular-nums}
img{width:100%;height:auto;display:block}footer{color:#3B4A68;font-size:14px;margin-top:48px;line-height:1.6}
@media(max-width:650px){main{padding:24px 12px}header{gap:10px;flex-wrap:wrap}header span{font-size:12px}h2{font-size:18px}nav{margin-left:0}}
</style><main><div class="status">Ready for review · Upload pending</div>
<h1>Five ideas.<br>Every store language.</h1>
<p class="intro">Review all five shots side by side. Open a sheet to zoom in, or choose 01–05 for the original 1290 × 2796 image.
English serves en-US and en-GB; Spanish serves es-ES and es-MX. Nothing has been uploaded in this pass.</p>
<div class="jump">'''
document += ''.join(f'<a href="#{lang}">{escape(names[lang])}</a>' for lang in LANGUAGES)
document += '</div>' + ''.join(cards) + '<footer>14 language sets · 16 store locales · 5 screenshots per set · 3 sizes<br>App Store Connect uploads wait for your approval.</footer></main></html>\n'
(out / 'index.html').write_text(document)
