'use strict';
const fs = require('node:fs');
const path = require('node:path');
const ROOT = path.resolve(__dirname, '..');
const LAYOUTS = ['text-hook', 'text-body', 'photo-caption', 'product', 'cta'];
const SCREENS = ['shield', 'pushups', 'earned', 'running', 'sessions', 'report'];
const APPS = ['duolingo', 'nyt-games', 'nike-run-club', 'earnit'];
const FORBIDDEN = /\b(study|studying|books?|scanning|scan|estudiar|estudio|estudia|libros?|escanear|escanea|opal|one\s*sec|screenzen|unrot|blocus|bepresent|doomit|piggy|koia|peep)\b/i;
const readJSON = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const words = text => String(text).match(/\S+/gu)?.length || 0;
function identifier(id) {
  if (typeof id !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id)) throw new Error(`Invalid id: ${id}`);
  return id;
}
function imagePath(file) {
  if (typeof file !== 'string' || !file.startsWith('images/') || file.includes('\\')) throw new Error('Image must be inside images/');
  const absolute = path.resolve(ROOT, file);
  if (!absolute.startsWith(path.join(ROOT, 'images') + path.sep)) throw new Error('Image escapes images/');
  if (!/\.(png|jpe?g|webp)$/i.test(file)) throw new Error('Photos must be PNG, JPEG or WebP');
  return absolute;
}
function thirdPartyAsset(app, slot) {
  identifier(app);
  if (!/^(icon|0[123])$/.test(slot)) throw new Error('Invalid app asset slot');
  const stem = `images/third-party/${app}/${slot}`;
  const file = ['png', 'jpg', 'webp'].map(ext => `${stem}.${ext}`).find(file => fs.existsSync(path.join(ROOT, file)));
  return { file: file || `${stem}.placeholder.svg`, placeholder: !file };
}
function validate(post, format, { ready = false } = {}) {
  const issues = [];
  const check = (condition, message) => { if (!condition) issues.push(message); };
  try { identifier(post.id); identifier(post.format); } catch (error) { issues.push(error.message); }
  check(format.id === post.format, 'Format id mismatch');
  check(['native', 'clean-list'].includes(format.family), 'Unknown style family');
  check(new Set(format.slides.map(s => s.id)).size === format.slides.length, 'Format slide ids must be unique');
  check(['en', 'es'].includes(post.language), 'Language must be en or es');
  check(['draft', 'ready'].includes(post.status), 'Status must be draft or ready');
  check(typeof post.caption === 'string' && post.caption.trim() && [...post.caption].length <= 150, 'Caption must be 1–150 characters');
  check(Array.isArray(post.hashtags) && post.hashtags.length >= 3 && post.hashtags.length <= 5 && post.hashtags.every(tag => /^#[\p{L}\p{N}_]+$/u.test(tag)), 'Use 3–5 hashtags');
  check(Array.isArray(post.sources) && post.sources.every(s => typeof s.claim === 'string' && typeof s.url === 'string' && /^(https?:\/\/|repo:)/.test(s.url)), 'Sources require claim and URL (https:// or repo:)');
  check(Array.isArray(format.slides) && format.slides.length >= 5 && format.slides.length <= 7, 'Format must contain 5–7 slides');
  check(Array.isArray(post.slides) && post.slides.length === format.slides.length, 'Slide count differs from format');
  const visible = [post.caption, ...(post.hashtags || [])];
  for (const [i, spec] of format.slides.entries()) {
    const slide = post.slides?.[i];
    check(LAYOUTS.includes(spec.layout), `Slide ${i+1}: unknown layout`);
    check(typeof spec.role === 'string' && spec.role.length > 0, `Slide ${i+1}: missing role`);
    check(spec.slots && Object.keys(spec.slots).every(key => ['title', 'body'].includes(key)) && Object.hasOwn(spec.slots, 'title'), `Slide ${i+1}: invalid slot definitions`);
    if (!slide) continue;
    check(slide.id === spec.id, `Slide ${i+1}: id/order differs from format`);
    check(slide.copy && typeof slide.copy === 'object', `Slide ${i+1}: missing copy`);
    for (const [slot, rule] of Object.entries(spec.slots)) {
      const value = slide.copy?.[slot];
      check(typeof value === 'string' && value.trim() && [...value].length <= rule.maxChars, `Slide ${i+1}.${slot}: required, max ${rule.maxChars} characters`);
      visible.push(value || '');
    }
    check(Object.keys(slide.copy || {}).every(key => Object.hasOwn(spec.slots, key)), `Slide ${i+1}: unknown copy slot`);
    const copy = Object.values(slide.copy || {}).join(' ');
    // The app name is visible in CTA layouts but is fixed layout text.
    check(words(copy) + (spec.layout === 'cta' ? 1 : 0) <= (i === 0 ? 12 : 25), `Slide ${i+1}: exceeds ${i === 0 ? 12 : 25} words`);
    check(['ivory', 'navy', 'cobalt'].includes(slide.fallback), `Slide ${i+1}: invalid fallback`);
    if (slide.image !== null) { try { imagePath(slide.image); } catch (error) { issues.push(error.message); } }
    if (spec.screen) check(SCREENS.includes(slide.screen), `Slide ${i+1}: missing product screen`);
    if (spec.app) check(APPS.includes(slide.app), `Slide ${i+1}: unsupported app`);
    if (spec.iconSwap) {
      check(Array.isArray(slide.fromApps) && slide.fromApps.length >= 1 && slide.fromApps.every(a => ['tiktok', 'instagram', 'x'].includes(a)), 'Invalid source icon list');
      check(Array.isArray(slide.toApps) && slide.toApps.length >= 1 && slide.toApps.length <= 4 && slide.toApps.every(a => APPS.includes(a)), 'Invalid destination icon list');
    }
  }
  check(!FORBIDDEN.test(visible.join(' ')), 'Hidden feature or competitor in visible copy');
  if (format.requiresEvidence && !JSON.stringify(visible).includes('{{')) check(post.sources?.some(s => !s.url.startsWith('repo:')), 'Real seven-day results need a source');
  if (ready) {
    check(post.status === 'ready', 'Post is a draft');
    check(!JSON.stringify(visible).includes('{{'), 'Unfilled data placeholders');
    for (const slide of post.slides || []) {
      const apps = [slide.app, ...(slide.fromApps || []), ...(slide.toApps || [])].filter(Boolean);
      for (const app of apps.filter(a => a !== 'earnit')) {
        const slots = slide.app === app ? ['icon', '01', '02', '03'] : ['icon'];
        for (const slot of slots) check(!thirdPartyAsset(app, slot).placeholder, `Missing asset: ${app}/${slot}`);
      }
    }
  }
  if (issues.length) throw new Error(`${post.id}:\n  ${issues.join('\n  ')}`);
}
module.exports = { ROOT, LAYOUTS, SCREENS, APPS, readJSON, escape, words, identifier, imagePath, thirdPartyAsset, validate };
