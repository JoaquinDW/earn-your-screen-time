// Explicit manifests exclude unrelated sources and generated drafts.
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const { pathToFileURL } = require('url');
const frames = require('./frames.json');

(async () => {
  const browser = await chromium.launch({ args: ['--allow-file-access-from-files'] });
  try {
    const page = await browser.newPage({ viewport: { width: 1290, height: 2796 }, deviceScaleFactor: 1 });
    const errors = [];
    page.on('request', request => { if (/^https?:/.test(request.url())) errors.push('Unexpected network request: ' + request.url()); });
    page.on('requestfailed', request => errors.push('Missing resource: ' + request.url()));
    page.on('pageerror', error => errors.push(error.message));
    const languages = ['en-US', 'es', 'de', 'fr', 'it', 'pt-BR', 'nl', 'pl', 'tr', 'ru', 'ja', 'ko', 'zh-Hans', 'ar'];
    for (const lang of (process.env.LANGUAGES ? process.env.LANGUAGES.split(',') : languages)) {
      const output = path.join(__dirname, '.build', lang);
      fs.mkdirSync(output, { recursive: true });
      for (const name of fs.readdirSync(output).filter(name => name.endsWith('.png'))) {
        fs.unlinkSync(path.join(output, name));
      }
      for (const frame of (process.env.FIRST_PASS ? frames.slice(0, 1) : frames)) {
        const file = `${frame.name}${lang === 'en-US' ? '' : '.' + lang}.html`;
        await page.goto(pathToFileURL(path.join(__dirname, 'src', file)).href);
        await page.evaluate(() => window.layoutReady);
        const audit = await page.evaluate(() => {
          const h = document.querySelector('.headline'), sub = document.querySelector('.sub');
          const lines = [...h.querySelectorAll('.headline-line')];
          const rect = element => element.getBoundingClientRect();
          const issues = [];
          if (lines.length !== 2) issues.push('Headline must have exactly two lines');
          for (const element of [...lines, sub]) {
            if (element.scrollWidth > element.clientWidth || rect(element).left < 0 || rect(element).right > 1290) issues.push('Copy overflows');
          }
          const range = document.createRange(); range.selectNodeContents(sub);
          if (new Set([...range.getClientRects()].map(r => Math.round(r.top))).size !== 1) issues.push('Subline must have exactly one line');
          if (rect(h).bottom + 24 > rect(sub).top) issues.push('Headline overlaps subline');
          const phone = document.querySelector('.phone');
          if (phone && rect(sub).bottom + 30 > rect(phone).top) issues.push('Copy overlaps phone');
          const note = document.querySelector('.note'), callout = document.querySelector('.card');
          if (note && !['en', 'es'].includes(document.documentElement.lang)) {
            if (rect(note).bottom + 16 > rect(callout).top) issues.push('Report callout covers footnote');
            if (rect(callout).bottom + 8 > rect(document.querySelector('.actions')).top) issues.push('Report callout covers actions');
            if (rect(document.querySelector('.done')).bottom > 2790) issues.push('Report action clips');
          }
          const inset = document.querySelector('.camera-inset');
          if (inset && rect(document.querySelector('.exercise-list')).bottom + 16 > rect(inset).top) issues.push('Camera inset covers exercise list');
          for (const fact of document.querySelectorAll('.privacy-fact')) if (rect(fact).bottom > 2740) issues.push('Privacy fact clips');
          for (const element of document.querySelectorAll('.laurels,.laurel,.card,.npill,.quiet,.weekdays,.prow,.hrow,.durs,.bal,.camera-count')) {
            if (element.scrollWidth > element.clientWidth + 2) issues.push('UI copy overflows: ' + element.className);
          }
          if (document.querySelector('.brand')) issues.push('Brand lockup remains');
          if (/\b(study|estudiar|estudio|books?|scanning)\b/i.test(document.body.innerText)) issues.push('Hidden feature appears');
          for (const image of document.images) if (!image.complete || !image.naturalWidth) issues.push('Missing image');
          return { issues, headline: lines.map(line => line.textContent), subline: sub.textContent, fontSize: getComputedStyle(h).fontSize };
        });
        const expected = lang === 'en-US' ? frame.headline : frame['headline_' + lang];
        const subline = lang === 'en-US' ? frame.subline : frame['subline_' + lang];
        if (JSON.stringify(audit.headline) !== JSON.stringify(expected) || audit.subline !== subline) audit.issues.push('Marketing copy differs from brief');
        if (audit.issues.length || errors.length) throw new Error(`${file}: ${[...audit.issues, ...errors].join('; ')}`);
        await page.screenshot({ path: path.join(output, frame.name + '.png') });
        console.log(`.build/${lang}/${frame.name}.png — headline ${audit.fontSize}, layout OK`);
      }
    }
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
