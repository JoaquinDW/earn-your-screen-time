// Explicit manifest prevents unrelated language variants from entering the EN/ES set.
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
    page.on('pageerror', error => errors.push(error.message));
    for (const lang of ['en-US', 'es']) {
      const output = path.join(__dirname, '6.9-inch', lang);
      fs.mkdirSync(output, { recursive: true });
      for (const name of fs.readdirSync(output).filter(name => name.endsWith('.png'))) {
        fs.unlinkSync(path.join(output, name));
      }
      for (const frame of frames) {
        const file = `${frame.name}${lang === 'es' ? '.es' : ''}.html`;
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
          if (rect(h).bottom + 24 > rect(sub).top) issues.push('Headline overlaps subline');
          const phone = document.querySelector('.phone');
          if (phone && rect(sub).bottom + 30 > rect(phone).top) issues.push('Copy overlaps phone');
          const inset = document.querySelector('.camera-inset');
          if (inset && rect(document.querySelector('.exercise-list')).bottom + 16 > rect(inset).top) issues.push('Camera inset covers exercise list');
          for (const fact of document.querySelectorAll('.privacy-fact')) if (rect(fact).bottom > 2740) issues.push('Privacy fact clips');
          if (document.querySelector('.brand')) issues.push('Brand lockup remains');
          if (/\b(study|estudiar|estudio|books?|scanning)\b/i.test(document.body.innerText)) issues.push('Hidden feature appears');
          for (const image of document.images) if (!image.complete || !image.naturalWidth) issues.push('Missing image');
          return { issues, headline: lines.map(line => line.textContent), subline: sub.textContent, fontSize: getComputedStyle(h).fontSize };
        });
        const expected = lang === 'es' ? frame.headline_es : frame.headline;
        const subline = lang === 'es' ? frame.subline_es : frame.subline;
        if (JSON.stringify(audit.headline) !== JSON.stringify(expected) || audit.subline !== subline) audit.issues.push('Marketing copy differs from brief');
        if (audit.issues.length || errors.length) throw new Error(`${file}: ${[...audit.issues, ...errors].join('; ')}`);
        await page.screenshot({ path: path.join(output, frame.name + '.png') });
        console.log(`6.9-inch/${lang}/${frame.name}.png — headline ${audit.fontSize}, layout OK`);
      }
    }
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
