'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { ROOT, readJSON } = require('./model');
const STORE = path.resolve(ROOT, '../app-store-screenshots');
const FILES = { shield: '01-hook', pushups: '02-pushups', earned: '03-walk', running: '03-walk', sessions: '06-sessions', report: '08-outcome' };

// Reuse the existing phone DOM, styles, scenes, Instrument Serif and Figtree.
// No App Store headlines, badges, or sample personal results are exported.
async function renderScreen(browser, screen, language, destination) {
  const file = FILES[screen];
  let html = fs.readFileSync(path.join(STORE, 'src', `${file}.html`), 'utf8');
  if (language === 'es') {
    for (const [from, to] of readJSON(path.join(STORE, 'l10n/es.json')).swaps[file]) {
      if (!html.includes(from)) throw new Error(`Screenshot translation source changed: ${file}: ${from}`);
      html = html.replace(from, to);
    }
    html = html.replace('lang="en"', 'lang="es"');
  }
  html = html.replace('<head>', `<head><base href="${pathToFileURL(path.join(STORE, 'src') + path.sep).href}">`)
    .replace('<script src="fit.js"></script>', '')
    .replace('</head>', `<style>
      html,body{width:900px!important;height:1966px!important}
      body>.phone{left:0!important;top:0!important;margin:0!important;padding:0!important;width:900px!important;height:1966px!important;transform:none!important;border-radius:0!important;box-shadow:none!important}
      .screen{border-radius:0!important}.active-session{margin-top:34px;text-align:left;background:var(--panel);border:1px solid #2e5ce659;border-radius:18px;padding:16px}
      .active-session header{display:flex;justify-content:space-between;align-items:center;color:var(--cobalt-text);font-size:11px;letter-spacing:1.5px;font-weight:600}
      .active-session strong{font-size:20px;letter-spacing:0}.active-session p{font-size:12.5px;line-height:1.4;color:var(--muted);margin:12px 0}
      .active-session footer{font-size:14px;color:var(--cobalt-text);padding:12px 0}
    </style></head>`);
  const workFile = destination.replace(/\.png$/, '.html');
  fs.writeFileSync(workFile, html);
  const page = await browser.newPage({ viewport: { width: 900, height: 1966 }, deviceScaleFactor: 1 });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('requestfailed', request => errors.push(request.url()));
  try {
    await page.route(/^https?:/, route => { errors.push(`Unexpected network request: ${route.request().url()}`); return route.abort(); });
    await page.goto(pathToFileURL(workFile).href);
    await page.evaluate(async ({ screen, language, localizations }) => {
      await document.fonts.ready;
      for (const child of [...document.body.children]) if (!child.classList.contains('phone')) child.remove();
      const es = language === 'es';
      const put = (selector, value) => { document.querySelector(selector).textContent = value; };
      if (screen === 'shield') {
        put('.hook-content h1', es ? 'Apps bloqueadas' : 'Apps locked');
        put('.hook-content p', es ? 'Gana minutos y después inicia una sesión para usarlos.' : 'Earn minutes, then start a session to use them.');
      }
      if (screen === 'earned' || screen === 'running') {
        document.querySelectorAll('.hrow,.tot,.imp,.next,.ticks').forEach(el => el.remove());
        put('.num b', screen === 'running' ? '0' : '10');
        if (screen === 'running') {
          document.querySelector('.home .npill').remove();
          const band = document.createElement('section'); band.className = 'active-session';
          const header = document.createElement('header');
          const label = document.createElement('span'); label.textContent = localizations['session.active'];
          const time = document.createElement('strong'); time.textContent = '9:42';
          header.append(label, time);
          const explanation = document.createElement('p'); explanation.textContent = localizations['session.active.explanation'];
          const end = document.createElement('footer'); end.textContent = localizations['session.endAndSave'];
          band.append(header, explanation, end); document.querySelector('.home').append(band);
        }
      }
      if (screen === 'sessions') document.querySelector('.cust')?.remove();
      if (screen === 'report') {
        document.querySelectorAll('.m b').forEach(el => { el.textContent = '—'; });
        put('.note', es ? 'Aquí aparecen tus propios datos. Esta vista no muestra resultados personales.' : 'Your own totals appear here. This view does not show personal results.');
      }
      // Validate the rendered phone content too, including translated source UI.
      if (/\b(study|books?|scanning|estudiar|estudio|libros?|opal|screenzen|unrot)\b/i.test(document.body.innerText)) throw new Error('Hidden feature or competitor in phone screen');
      for (const image of document.images) await image.decode();
    }, { screen, language, localizations: sessionStrings(language) });
    if (errors.length) throw new Error(errors.join('; '));
    const bounds = await page.evaluate(() => {
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      const bounds = [];
      while (walker.nextNode()) {
        const node = walker.currentNode;
        if (!node.textContent.trim()) continue;
        const range = document.createRange(); range.selectNodeContents(node);
        for (const r of range.getClientRects()) if (r.width && r.height) bounds.push({
          x: r.x, y: r.y, width: r.width, height: r.height, text: node.textContent.trim()
        });
      }
      return bounds;
    });
    await page.screenshot({ path: destination });
    return bounds;
  } finally { await page.close(); fs.unlinkSync(workFile); }
}

function sessionStrings(language) {
  const catalog = readJSON(path.resolve(ROOT, '../../App/Resources/Localizable.xcstrings')).strings;
  return Object.fromEntries(['session.active', 'session.active.explanation', 'session.endAndSave'].map(key => [key, catalog[key].localizations[language].stringUnit.value]));
}
module.exports = { renderScreen };
