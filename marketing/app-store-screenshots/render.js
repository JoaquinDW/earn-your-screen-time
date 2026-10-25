// Renders every page in src/ to en-US/ and es/ at 1290 x 2796 (6.9" iPhone).
// Run through render.sh, which builds the Spanish pages first.
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

(async () => {
  const src = path.join(__dirname, 'src');
  const browser = await chromium.launch({ args: ['--allow-file-access-from-files'] });
  const page = await browser.newPage({ viewport: { width: 1290, height: 2796 }, deviceScaleFactor: 1 });
  for (const file of fs.readdirSync(src).filter(f => f.endsWith('.html')).sort()) {
    const es = file.endsWith('.es.html');
    const name = file.replace(/(\.es)?\.html$/, '');
    await page.goto('file://' + path.join(src, file));
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(300);
    await page.screenshot({ path: path.join(__dirname, es ? 'es' : 'en-US', name + '.png') });
    console.log((es ? 'es/' : 'en-US/') + name + '.png');
  }
  await browser.close();
})();
