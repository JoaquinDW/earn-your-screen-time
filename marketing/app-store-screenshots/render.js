// Offline renderer. --first renders shot 01 in each language for font/layout QA.
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

(async () => {
  const src = path.join(__dirname, 'src');
  const browser = await chromium.launch({
    args: ['--allow-file-access-from-files', '--font-render-hinting=none', '--disable-lcd-text'],
    ...(process.env.CHROMIUM_EXECUTABLE_PATH ? { executablePath: process.env.CHROMIUM_EXECUTABLE_PATH } : {}),
  });
  const page = await browser.newPage({ viewport: { width: 1290, height: 2796 }, deviceScaleFactor: 1 });
  await page.route(/^https?:/, route => route.abort());
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('DOM.enable');
  await cdp.send('CSS.enable');
  const report = [];
  for (const file of fs.readdirSync(src).filter(f => f.endsWith('.html')).sort()) {
    if (process.argv.includes('--first') && !file.startsWith('01-')) continue;
    const [, name, language] = file.match(/^(\d{2}-[^.]+)(?:\.([^.]+))?\.html$/);
    const lang = language || 'en-US';
    const only = process.argv.find(a => a.startsWith('--lang='));
    if (only && lang !== only.slice(7)) continue;
    await page.goto('file://' + path.join(src, file));
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(300);
    const metrics = await page.evaluate(({ lang, name }) => {
      const errors = [];
      if ([...document.images].some(i => !i.complete || !i.naturalWidth)) errors.push('Missing image');
      if ([...document.fonts].some(f => f.status === 'error')) errors.push('Font load failed');
      const localized = !['en-US', 'es'].includes(lang);
      const headline = document.querySelector('.headline');
      const ranges = () => [...headline.childNodes].filter(n => n.nodeName !== 'BR').map(n => {
        const r = document.createRange(); r.selectNodeContents(n); return r.getBoundingClientRect();
      });
      if (localized) {
        // Both lines share one font size. Explicit <br> plus nowrap prevents a third line.
        let font = parseFloat(getComputedStyle(headline).fontSize);
        while (ranges().some(r => r.left < 80 || r.right > 1210) && font > 64) {
          headline.style.fontSize = `${--font}px`;
        }
        // Fit badges as a group, retaining one line per badge label.
        const laurels = document.querySelector('.laurels');
        if (laurels) {
          let font = 64;
          const width = () => [...laurels.querySelectorAll('.t')].reduce((sum, e) =>
            sum + Math.max(...[...e.children].map(c => c.scrollWidth)) + 152, 32);
          while (width() > 1162 && font > 34) {
            font--;
            laurels.querySelectorAll('b').forEach(e => e.style.fontSize = `${font}px`);
            laurels.querySelectorAll('.t span').forEach(e => e.style.fontSize = `${font * .45}px`);
          }
        }
        // Long native button labels retain their wording and fit the same controls.
        for (const e of document.querySelectorAll('.npill,.pill,.guide,.count span,.sheet h1,.msg h1,.bal b,.bal span,.m b,.sb,.imp,.tot,.next>span:first-child,.cust')) {
          let font = parseFloat(getComputedStyle(e).fontSize);
          e.style.whiteSpace = 'nowrap';
          while (e.scrollWidth > e.clientWidth + 1 && font > 9) e.style.fontSize = `${font -= .25}px`;
          if (e.scrollWidth > e.clientWidth + 1) errors.push(`Overflow: ${e.className}: ${e.textContent}`);
        }
        const card = document.querySelector('.card');
        if (card) {
          const text = card.lastElementChild;
          for (const e of text.children) {
            let font = parseFloat(getComputedStyle(e).fontSize);
            while (e.scrollWidth > text.clientWidth + 1 && font > 26) e.style.fontSize = `${--font}px`;
          }
          const avoid = name === '05-sessions' ? document.querySelector('.npill') :
            name === '02-outcome' ? document.querySelector('.note') : null;
          if (avoid) {
            const delta = avoid.getBoundingClientRect().bottom + 32 - card.getBoundingClientRect().top;
            if (delta > 0) card.style.top = `${card.offsetTop + delta}px`;
          }
          // Keep tilted labels inside the canvas, with the original phone placement.
          const rect = card.getBoundingClientRect();
          if (rect.bottom > 2780) card.style.top = `${card.offsetTop - (rect.bottom - 2780)}px`;
          const r = card.getBoundingClientRect();
          if (r.left < 16 || r.right > 1274) errors.push('Card outside canvas');
          if (name === '02-outcome') {
            const actions = document.querySelector('.actions');
            const gap = r.bottom + 32 - actions.getBoundingClientRect().top;
            if (gap > 0) actions.style.top = `${actions.offsetTop + gap / 2.2901}px`;
          }
        }
      }
      const lines = ranges();
      if (lines.some(r => r.left < 64 || r.right > 1226)) errors.push('Headline outside safe area');
      if (headline.querySelectorAll('br').length !== 1) errors.push('Headline must have exactly two lines');
      return { errors, headlineSize: getComputedStyle(headline).fontSize,
        headline: headline.innerText, lines: lines.map(r => ({ x: r.x, y: r.y, width: r.width, height: r.height })) };
    }, { lang, name });
    if (metrics.errors.length) throw new Error(`${file}: ${metrics.errors.join('; ')}`);
    const fonts = new Set();
    if (['ja', 'ko', 'zh-Hans', 'ru', 'ar'].includes(lang)) {
      // Probe the actual text faces using letters/numbers only. Decorative UI
      // symbols (✕, ▦, etc.) legitimately use the platform's symbol fallback.
      await page.evaluate(lang => {
        const script = { ja: 'Han|Hiragana|Katakana', ko: 'Hangul', 'zh-Hans': 'Han', ru: 'Cyrillic', ar: 'Arabic' }[lang];
        const native = new RegExp(script.split('|').map(s => `\\p{Script=${s}}`).join('|'), 'u');
        const groups = new Map();
        for (const e of document.body.querySelectorAll('*')) {
          const own = [...e.childNodes].filter(n => n.nodeType === Node.TEXT_NODE).map(n => n.textContent).join('');
          if (!native.test(own)) continue;
          const font = getComputedStyle(e).font;
          groups.set(font, (groups.get(font) || '') + own.replace(/[^\p{L}\p{M}\p{N}\s]/gu, '') + ' ');
        }
        let index = 0;
        for (const [font, text] of groups) {
          const probe = document.createElement('span');
          probe.dataset.auditFont = index++;
          probe.style.cssText = 'position:absolute;left:0;top:0;opacity:0;pointer-events:none';
          probe.style.font = font; probe.textContent = text;
          document.body.appendChild(probe);
        }
      }, lang);
      const { root } = await cdp.send('DOM.getDocument');
      const { nodeIds } = await cdp.send('DOM.querySelectorAll', { nodeId: root.nodeId, selector: '[data-audit-font]' });
      for (const nodeId of nodeIds) {
        const result = await cdp.send('CSS.getPlatformFontsForNode', { nodeId });
        for (const font of result.fonts) {
          fonts.add(font.familyName);
          if (!font.isCustomFont) throw new Error(`${file}: unbundled text fallback ${font.familyName}`);
        }
      }
      await page.evaluate(() => document.querySelectorAll('[data-audit-font]').forEach(e => e.remove()));
    }
    const out = path.join(__dirname, '6.9-inch', lang);
    fs.mkdirSync(out, { recursive: true });
    await page.screenshot({ path: path.join(out, name + '.png') });
    report.push({ lang, name, fonts: [...fonts], ...metrics });
    console.log(`6.9-inch/${lang}/${name}.png (${metrics.headlineSize})`);
  }
  fs.mkdirSync(path.join(__dirname, 'previews'), { recursive: true });
  fs.writeFileSync(path.join(__dirname, 'previews', process.argv.includes('--first') ? 'first-pass.json' : 'layout.json'), JSON.stringify(report, null, 2) + '\n');
  await browser.close();
})().catch(error => { console.error(error); process.exit(1); });
