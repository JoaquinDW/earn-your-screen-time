"""Build localized HTML with exact-once swaps; catalogs win over manual UI copy.

Spanish's original swap table and CSS are preserved verbatim as the pixel baseline.
No fonts, translations, or other resources are fetched during a screenshot build.
"""
import argparse
import html
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / 'src'
LANGUAGES = ('en-US', 'es', 'de', 'fr', 'it', 'ja', 'ko', 'nl', 'pl', 'pt-BR', 'ru', 'tr', 'zh-Hans', 'ar')
STORE_LOCALES = {
    'ar-SA': 'ar', 'de-DE': 'de', 'en-GB': 'en-US', 'en-US': 'en-US',
    'es-ES': 'es', 'es-MX': 'es', 'fr-FR': 'fr', 'it': 'it', 'ja': 'ja',
    'ko': 'ko', 'nl-NL': 'nl', 'pl': 'pl', 'pt-BR': 'pt-BR', 'ru': 'ru',
    'tr': 'tr', 'zh-Hans': 'zh-Hans',
}
SPANISH = json.loads((ROOT / 'l10n/es.json').read_text())
PAGES = tuple(SPANISH)
COPY = json.loads((ROOT / 'l10n/copy.json').read_text())

# Locate catalog entries by English VALUE, including keys whose English is implicit.
CATALOGS = []
for name in ('Localizable', 'PushupsLocalizable'):
    entries = json.loads((ROOT.parents[1] / f'App/Resources/{name}.xcstrings').read_text())['strings']
    CATALOGS.extend((name, key, entry) for key, entry in entries.items())


def app(english, lang, fallback, *args):
    matches = []
    for table, key, entry in CATALOGS:
        loc = entry.get('localizations', {})
        value = loc.get('en', {}).get('stringUnit', {}).get('value', key)
        if value == english:
            translated = loc.get(lang, {}).get('stringUnit', {}).get('value')
            if translated:
                matches.append((table, key, translated))
    if matches:
        preferred = {'%lld-day streak': 'dashboard.streak %lld', 'Today': 'impact.period.today',
                     '%@ steps today': 'earn.stepsToday %@', 'Use my minutes': 'pushups.success.use',
                     '%@ steps': '%@ steps', 'Available': 'session.available'}
        selected = [m for m in matches if m[1] == preferred.get(english)]
        if selected:
            matches = selected
        # Equal English values in different keys must agree, rather than silently
        # choosing an unrelated translation when a new catalog entry is introduced.
        values = {m[2] for m in matches}
        assert len(values) == 1, (english, lang, matches)
        value = matches[0][2]
    else:
        assert fallback is not None, ('Missing translation', english, lang)
        value = fallback
    position = 0

    def substitute(match):
        nonlocal position
        index = int(match[1]) - 1 if match[1] else position
        if not match[1]:
            position += 1
        return str(args[index])

    value = re.sub(r'%(?:(\d+)\$)?(?:lld|@)', substitute, value)
    assert not re.search(r'%(?:\d+\$)?(?:lld|@)', value), value
    return html.escape(value, quote=False)


def swaps(lang):
    if lang == 'es':
        return SPANISH
    c = COPY[lang]
    ui = c['ui']

    def t(key, english, *args):
        return app(english, lang, ui.get(key), *args)

    def headline(index):
        a, b = c['headlines'][index]
        return html.escape(a) + '<br><em>' + html.escape(b) + '</em>'

    def card(a, b):
        return f'<b>{a}</b><span>{b}</span>'

    def earned(n):
        return t('earned', '+%lld min earned', n)

    def streak():
        return t('streak', '%lld-day streak', 12)

    step_count = c['steps']
    minutes = c['minute']
    result = {}
    values = [
        [headline(0), html.escape(c['subtitles'][0]), card(*map(html.escape, c['badges'][0])),
         card(*map(html.escape, c['badges'][1])), t('reps', '/ %lld push-ups', 10),
         t('form', 'Great form — keep going'), card(t('unlocked', 'Apps unlocked'), earned(10))],
        [headline(1), html.escape(c['subtitles'][1]), '<div class="eyebrow">' + t('today', 'Today') + '</div>',
         '<h1>' + t('day', 'Your day') + '</h1>',
         html.escape(c['duration']) + '</b><span>' + t('reclaimed', 'less than you used to scroll'),
         t('skipped', 'times you stayed out of a blocked app'),
         '<b>' + html.escape(minutes.format(40)) + '</b><span>' + t('moving', 'screen time earned by moving'),
         '<b>' + step_count + '</b><span>' + t('steps', 'steps'),
         t('estimate', 'An estimate: the low end of the daily scrolling you told us about when you started, minus the time you unlocked in Earnit.'),
         t('share', 'Share my progress'), t('challenge', 'Challenge a friend'), '>' + t('done', 'Done') + '<',
         card(streak(), html.escape(ui['keep']))],
        [headline(2), html.escape(c['subtitles'][2]), '>' + html.escape(ui['saturday']) + '<',
         '🔥 ' + streak(), '>' + t('availableTime', 'Available time') + '<',
         t('spend', 'to spend on your apps'), t('use', 'Use my minutes'),
         t('stepsToday', '%@ steps today', step_count) + ' · <em>' + t('earnedToday', '+%lld min earned today', 40) + '</em>',
         '✋ ' + t('skippedToday', 'Apps skipped today: %lld · See your day', 14) + ' ›',
         t('next', '%1$lld steps until your next %2$lld minutes', 760, 5),
         card(t('stepsCount', '%@ steps', step_count), earned(30))],
        [headline(3), html.escape(c['subtitles'][3]), '>' + t('almost', 'ALMOST THERE') + '<',
         t('left', 'Just %lld steps left.', 320),
         t('finish', 'Finish the walk and earn %lld min. Your apps can wait.', 5),
         t('progress', '%1$@ / %2$@ steps', '680', c['thousand']),
         t('walkLeft', '%1$lld steps left · ~%2$lld min walk', 320, 3),
         t('exercise', 'Earn time with push-ups or squats'), t('update', 'Update my steps'),
         card(t('locked', 'Apps locked'), html.escape(ui['until']))],
        [headline(4), html.escape(c['subtitles'][4]), '>' + t('choose', 'Choose a session') + '<',
         '<h1>' + t('use', 'Use my minutes') + '</h1>', '<span>' + t('available', 'Available') + '</span>',
         '<span>' + t('after', 'After session') + '</span>', t('custom', 'Custom amount'),
         '▦ ' + t('apps', '%lld selected', 3),
         t('clock', 'Time starts now and keeps running when you switch apps. Return to Earnit to end the session and save the rest.'),
         t('start', 'Use blocked apps for %lld min', 10), card(html.escape(ui['session']), html.escape(ui['again']))],
    ]
    for (name, original), translated in zip(SPANISH.items(), values):
        assert len(original) == len(translated), (lang, name)
        result[name] = [(a, b) for (a, _), b in zip(original, translated)]
    return result


def generate(languages):
    for lang in languages:
        if lang == 'en-US':
            continue
        for name, pairs in swaps(lang).items():
            source = (SRC / f'{name}.html').read_text()
            for english, translated in pairs:
                assert source.count(english) == 1, (lang, name, english, source.count(english))
                source = source.replace(english, translated)
            if lang == 'es':
                source = source.replace('</style>', '  .headline { font-size: 176px; }\n</style>', 1)
            else:
                # Unit-only text nodes are separate from the exact swaps above.
                for n in (5, 10, 15, 25):
                    source = source.replace(f'>{n} min<', f'>{COPY[lang]["minute"].format(n)}<')
                source = source.replace('>min<', f'>{COPY[lang]["minute"].format(0).replace("0", "").strip()}<')
                source = source.replace('+5 MIN', '+' + COPY[lang]['minute'].format(5))
                direction = 'rtl' if lang == 'ar' else 'ltr'
                source = source.replace('<html>', f'<html lang="{lang}" dir="{direction}">', 1)
                source = source.replace('</head>', '<link rel="stylesheet" href="l10n.css"></head>', 1)
                if lang == 'ar':
                    # Format visible numbers only; never alter CSS, SVG geometry,
                    # inline scripts, URLs, or identifiers.
                    parts = re.split(r'(<[^>]+>)', source)
                    skip = False
                    for i, part in enumerate(parts):
                        if part.startswith(('<style', '<script')):
                            skip = True
                        elif part.startswith(('</style', '</script')):
                            skip = False
                        elif not part.startswith('<') and not skip:
                            parts[i] = part.translate(str.maketrans('0123456789', '٠١٢٣٤٥٦٧٨٩'))
                    source = ''.join(parts)
            (SRC / f'{name}.{lang}.html').write_text(source)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('languages', nargs='*', metavar='LANG', default=[])
    args = parser.parse_args()
    assert set(args.languages) <= set(LANGUAGES), args.languages
    generate(args.languages or LANGUAGES)
