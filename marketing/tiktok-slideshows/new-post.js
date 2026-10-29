#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { ROOT, readJSON, identifier } = require('./lib/model');
try {
  const [formatID, id, language = 'en', ...extra] = process.argv.slice(2);
  if (!formatID || !id || extra.length || !['en', 'es'].includes(language)) throw new Error('Usage: node new-post.js <format-id> <new-id> [en|es]');
  const format = readJSON(path.join(ROOT, 'formats', `${identifier(formatID)}.json`));
  const post = {
    id: identifier(id), format: format.id, language, status: 'draft', topic: '', caption: '', hashtags: [], sources: [],
    slides: format.slides.map(spec => ({
      id: spec.id, copy: Object.fromEntries(Object.keys(spec.slots).map(slot => [slot, ''])),
      image: spec.image, fallback: spec.fallback,
      ...(spec.screen && { screen: spec.screen }), ...(spec.app && { app: spec.app }),
      ...(spec.iconSwap && { fromApps: ['tiktok', 'instagram', 'x'], toApps: ['duolingo', 'nyt-games', 'nike-run-club', 'earnit'] })
    }))
  };
  fs.writeFileSync(path.join(ROOT, 'posts', `${id}.json`), JSON.stringify(post, null, 2) + '\n', { flag: 'wx' });
  console.log(`Created posts/${id}.json with empty copy slots. Fill them before rendering.`);
} catch (error) { console.error(error.message); process.exitCode = 1; }
