#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { ROOT, SCREENS, readJSON, escape, identifier, imagePath, thirdPartyAsset, validate } = require('./lib/model');
const { playwright } = require('./lib/runtime');
const { renderScreen } = require('./lib/screens');
const fileURL = file => pathToFileURL(file).href;
const iconPath = path.resolve(ROOT, '../../App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png');
const imageTag = (file, className = '') => `<img class="${className}" src="${escape(fileURL(file))}" alt="">`;

function icon(app, warnings) {
  if (app === 'earnit') return imageTag(iconPath, 'app-icon');
  const asset = thirdPartyAsset(app, 'icon');
  if (asset.placeholder) warnings.add(`Missing third-party asset: ${app}/icon`);
  return imageTag(path.join(ROOT, asset.file), 'app-icon');
}

function slideHTML(post, format, slide, spec, screens, warnings) {
  const photo = slide.image && imagePath(slide.image);
  const hasPhoto = photo && fs.existsSync(photo);
  if (photo && !hasPhoto) warnings.add(`Solid fallback: ${slide.image}`);
  const assetWarnings = new Set();
  let phones = '', visual = '', demo = '', appIcon = '';
  const phone = file => `<div class="phone">${imageTag(file)}</div>`;
  if (spec.screen) phones = phone(screens[`${post.language}/${slide.screen}`]);
  if (spec.app) {
    appIcon = icon(slide.app, assetWarnings);
    if (slide.app === 'earnit') phones = ['shield', 'pushups', 'sessions'].map(screen => phone(screens[`${post.language}/${screen}`])).join('');
    else phones = ['01', '02', '03'].map(slot => {
      const asset = thirdPartyAsset(slide.app, slot);
      if (asset.placeholder) assetWarnings.add(`Missing third-party asset: ${slide.app}/${slot}`);
      return phone(path.join(ROOT, asset.file));
    }).join('');
  }
  if (spec.iconSwap) visual = `<section class="icon-swap" data-safe><div class="icon-group">${slide.fromApps.map(app => icon(app, assetWarnings)).join('')}</div><svg class="arrow" viewBox="0 0 130 120" aria-hidden="true"><path d="M8 92Q65 15 115 73M85 35l33 42-50 2" stroke="currentColor" stroke-width="12" stroke-linecap="round" stroke-linejoin="round" fill="none"/></svg><div class="icon-group">${slide.toApps.map(app => icon(app, assetWarnings)).join('')}</div></section>`;
  if (spec.screen || slide.app === 'earnit') demo = `<div class="demo" data-safe>${post.language === 'es' ? 'vista de ejemplo · sin resultados personales' : 'example screen · no personal results'}</div>`;
  if (spec.layout === 'cta') appIcon = icon('earnit', warnings);
  const dataPlaceholder = Object.values(slide.copy).some(value => value.includes('{{'));
  const assetPlaceholder = assetWarnings.size > 0;
  for (const note of assetWarnings) warnings.add(note);
  const draftLabel = dataPlaceholder ? (post.language === 'es' ? 'plantilla · añade datos reales' : 'template · add real data') : assetPlaceholder ? (post.language === 'es' ? 'borrador · faltan imágenes' : 'draft · assets needed') : '';
  const values = { title: escape(slide.copy.title), body: escape(slide.copy.body), phones, visual, demo, icon: appIcon };
  const template = fs.readFileSync(path.join(ROOT, 'layouts', `${spec.layout}.html`), 'utf8');
  const content = template.replace(/{{(\w+)}}/g, (_, key) => values[key] || '').replace(/<p><\/p>/g, '');
  return `<!doctype html><html lang="${post.language}"><head><meta charset="utf-8"><link rel="stylesheet" href="${fileURL(path.join(ROOT, 'layouts/base.css'))}"></head>
  <body class="${format.family} ${hasPhoto ? 'photo' : `no-photo fallback-${slide.fallback}`} layout-${spec.layout} ${draftLabel ? 'has-draft' : ''} ${spec.layout === 'text-body' ? 'outlined' : ''}">
  <div class="background" ${hasPhoto ? `style="background-image:url('${escape(fileURL(photo))}')"` : ''}></div><div class="shade"></div>${draftLabel ? `<div class="draft" data-safe>${draftLabel}</div>` : ''}${content}</body></html>`;
}

async function auditSlide(page) {
  return page.evaluate(() => {
    const issues = [];
    const rect = el => el.getBoundingClientRect();
    for (const block of document.querySelectorAll('[data-safe]')) {
      const r = rect(block);
      if (r.top < 150 || r.bottom > 1520 || r.left < 60 || r.right > 960) issues.push(`Outside safe zone: ${block.className}`);
      if (block.scrollWidth > block.clientWidth + 1 || block.scrollHeight > block.clientHeight + 1) issues.push(`Overflow: ${block.className}`);
      for (const text of block.querySelectorAll('h1,p')) {
        const r = rect(text);
        if (r.right > 960 || r.bottom > 1520 || text.scrollWidth > text.clientWidth + 1) issues.push(`Text overflow: ${text.textContent}`);
        const style = getComputedStyle(text);
        const lines = Math.round((r.height - parseFloat(style.paddingTop) - parseFloat(style.paddingBottom)) / parseFloat(style.lineHeight));
        if (block.classList.contains('body') && text.tagName === 'P' && lines > 3) issues.push(`Body exceeds three lines: ${text.textContent}`);
      }
    }
    const heading = document.querySelector('.product-heading'), phones = document.querySelector('.phones');
    if (heading && phones && rect(heading).bottom + 25 > rect(phones).top) issues.push('Heading overlaps phone');
    const hook = document.querySelector('.hook'), icons = document.querySelector('.icon-swap');
    if (hook && icons && rect(hook).bottom + 40 > rect(icons).top) issues.push('Hook overlaps icons');
    for (const image of document.images) if (!image.complete || !image.naturalWidth) issues.push('Missing image');
    return { issues, title: document.querySelector('h1').textContent, hookFontSize: getComputedStyle(document.querySelector('h1')).fontSize };
  });
}

async function contactSheet(browser, post, output, warningList) {
  const thumbs = post.slides.map((slide, i) => `<figure>${imageTag(path.join(output, `${String(i+1).padStart(2, '0')}.png`))}<figcaption>${String(i+1).padStart(2,'0')} · ${escape(slide.id)}</figcaption></figure>`).join('');
  const status = post.status === 'draft' ? 'DRAFT' : 'READY';
  const html = `<!doctype html><meta charset="utf-8"><style>@font-face{font-family:TikTok;src:url('${fileURL(path.join(ROOT,'fonts/TikTokSans-Bold.woff2'))}')}*{box-sizing:border-box}body{margin:0;background:#e6e6e6;color:#111;font:16px TikTok,sans-serif;width:984px;padding:24px}header{height:100px}h1{font-size:25px;margin:0 0 10px}p{margin:0;font-size:14px}main{display:grid;grid-template-columns:repeat(3,300px);gap:18px}figure{margin:0}img{display:block;width:300px;height:533.333px}figcaption{height:30px;padding:7px 0;font-size:13px}</style><header><h1>${escape(post.id)} · ${post.language.toUpperCase()} · ${status}</h1><p>${post.slides.length} slides · ${warningList.some(w=>w.startsWith('Solid fallback')) ? 'solid backgrounds; add photos to images/' : 'backgrounds loaded'}${post.status === 'draft' ? ' · replace placeholders before uploading' : ''}</p></header><main>${thumbs}</main>`;
  const work = path.join(output, 'contact.html');
  fs.writeFileSync(work, html);
  const page = await browser.newPage({ viewport: { width: 984, height: 124 + Math.ceil(post.slides.length/3)*582 }, deviceScaleFactor: 1 });
  try {
    await page.goto(fileURL(work));
    await page.evaluate(async()=> { await document.fonts.ready; await Promise.all([...document.images].map(img=>img.decode())); });
    await page.screenshot({ path: path.join(ROOT, 'previews', `${post.id}.png`), fullPage: true });
  } finally { await page.close(); fs.unlinkSync(work); }
}

async function main() {
  const args = process.argv.slice(2);
  const flags = new Set(args.filter(arg => arg.startsWith('--')));
  const ids = args.filter(arg => !arg.startsWith('--'));
  if ([...flags].some(flag => !['--all', '--validate', '--ready', '--help'].includes(flag))) throw new Error('Unknown option. Use --help.');
  if (flags.has('--help')) { console.log('node render.js <post-id> | --all [--validate] [--ready]\nWrites out/<id>/01.png…caption.txt and previews/<id>.png. --ready rejects drafts or missing third-party assets.'); return; }
  if ((flags.has('--all') && ids.length) || (!flags.has('--all') && ids.length !== 1)) throw new Error('Choose one post id or --all. Use --help.');
  const names = flags.has('--all') ? fs.readdirSync(path.join(ROOT, 'posts')).filter(n => n.endsWith('.json')).sort().map(n=>n.slice(0,-5)) : ids;
  const jobs = names.map(id => {
    identifier(id);
    const post = readJSON(path.join(ROOT, 'posts', `${id}.json`));
    if (post.id !== id) throw new Error(`Post id must match filename: ${id}`);
    identifier(post.format);
    const format = readJSON(path.join(ROOT, 'formats', `${post.format}.json`));
    validate(post, format, { ready: flags.has('--ready') || post.status === 'ready' });
    return { post, format };
  });
  if (flags.has('--validate')) { console.log(`Validated ${jobs.length} posts (${jobs.filter(j=>j.post.language==='en').length} en / ${jobs.filter(j=>j.post.language==='es').length} es).`); return; }
  const launch = { args: ['--allow-file-access-from-files'] };
  if (process.env.CHROMIUM_PATH) launch.executablePath = process.env.CHROMIUM_PATH;
  const browser = await playwright().chromium.launch(launch);
  fs.mkdirSync(path.join(ROOT, 'previews'), { recursive: true });
  const work = path.join(ROOT, 'out', '.screens'); fs.mkdirSync(work, { recursive: true });
  try {
    const screens = {};
    const needed = new Set();
    for (const {post} of jobs) for (const slide of post.slides) {
      if (slide.screen) needed.add(`${post.language}/${slide.screen}`);
      if (slide.app === 'earnit') for (const screen of ['shield','pushups','sessions']) needed.add(`${post.language}/${screen}`);
    }
    for (const key of needed) {
      const [language, screen] = key.split('/');
      if (!SCREENS.includes(screen)) throw new Error('Unsupported screen');
      const destination = path.join(work, `${language}-${screen}.png`);
      await renderScreen(browser, screen, language, destination); screens[key] = destination;
    }
    for (const {post,format} of jobs) {
      // Validate a complete post before replacing its previous successful export.
      const destination = path.join(ROOT, 'out', post.id);
      const output = fs.mkdtempSync(path.join(ROOT, 'out', `.${post.id}-`));
      const warnings = new Set(), audits = [];
      const page = await browser.newPage({ viewport: { width:1080, height:1920 }, deviceScaleFactor:1 });
      const errors = [];
      page.on('pageerror',error=>errors.push(error.message));
      page.on('requestfailed',request=>errors.push(`Missing resource: ${request.url()}`));
      await page.route(/^https?:/, route=> { errors.push(`Unexpected network: ${route.request().url()}`); return route.abort(); });
      try {
        for (const [i,slide] of post.slides.entries()) {
          const html = slideHTML(post,format,slide,format.slides[i],screens,warnings);
          const source = path.join(output,'slide.html'); fs.writeFileSync(source,html);
          await page.goto(fileURL(source));
          await page.evaluate(async()=> { await document.fonts.ready; await Promise.all([...document.images].map(img=>img.decode())); });
          const audit = await auditSlide(page);
          if (audit.issues.length || errors.length) throw new Error(`${post.id}/${i+1}: ${[...audit.issues,...errors].join('; ')}`);
          const filename = `${String(i+1).padStart(2,'0')}.png`;
          await page.screenshot({ path:path.join(output,filename) });
          audits.push({ filename, ...audit });
          fs.unlinkSync(source);
        }
        const draft = post.status === 'draft' ? 'DRAFT — replace data / third-party asset placeholders before upload.\n\n' : '';
        fs.writeFileSync(path.join(output,'caption.txt'), `${draft}${post.caption}\n\n${post.hashtags.join(' ')}\n`);
        fs.writeFileSync(path.join(output,'qa.json'),JSON.stringify({id:post.id,status:post.status,warnings:[...warnings],slides:audits},null,2)+'\n');
        await contactSheet(browser,post,output,[...warnings]);
        fs.rmSync(destination, { recursive: true, force: true });
        fs.renameSync(output, destination);
        console.log(`${post.id}: ${audits.length} slides + caption + contact sheet; ${post.status}${warnings.size ? ` (${warnings.size} fallback/asset notes)` : ''}`);
      } finally { await page.close(); fs.rmSync(output, { recursive: true, force: true }); }
    }
  } finally { await browser.close(); }
}
if (require.main === module) main().catch(error=> { console.error(error.message); process.exitCode=1; });
module.exports = { slideHTML, auditSlide };
