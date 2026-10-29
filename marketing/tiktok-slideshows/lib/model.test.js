'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const { ROOT, readJSON, validate, imagePath, identifier } = require('./model');
const post = () => readJSON(path.join(ROOT,'posts/f2-01-pov.json'));
const format = readJSON(path.join(ROOT,'formats/f2-pov-pushups.json'));

test('starter batch is 24 posts, 4 per format, with 18 en and 6 es', () => {
  const posts = fs.readdirSync(path.join(ROOT,'posts')).filter(f=>f.endsWith('.json')).map(f=>readJSON(path.join(ROOT,'posts',f)));
  assert.equal(posts.length,24);
  assert.equal(posts.filter(p=>p.language==='en').length,18);
  assert.equal(posts.filter(p=>p.language==='es').length,6);
  for (const file of fs.readdirSync(path.join(ROOT,'formats'))) {
    const spec=readJSON(path.join(ROOT,'formats',file));
    assert.equal(posts.filter(p=>p.format===spec.id).length,4);
    for (const p of posts.filter(p=>p.format===spec.id)) validate(p,spec);
  }
});
test('copy limits apply to the full slide, caption, and extra copy slots', () => {
  for (const mutate of [p=>{p.slides[0].copy.title='word '.repeat(13).trim();},p=>{p.caption='a'.repeat(151);},p=>{p.slides[0].copy.secret='invisible copy';}]) {
    const p=post();mutate(p);assert.throws(()=>validate(p,format));
  }
});
test('hidden features and named competitors are rejected', () => {
  for (const text of ['study to earn','scan your books','prueba ScreenZen','usa Opal']) {
    const p=post();p.slides[0].copy.title=text;assert.throws(()=>validate(p,format),/Hidden feature or competitor/);
  }
});
test('ready export rejects unfilled data and missing third-party screens', () => {
  for (const id of ['f4-01-movement','f6-01-swap']) {
    const p=readJSON(path.join(ROOT,'posts',`${id}.json`));p.status='ready';
    const spec=readJSON(path.join(ROOT,'formats',`${p.format}.json`));
    assert.throws(()=>validate(p,spec,{ready:true}),id.startsWith('f4')?/Unfilled data/:/Missing asset/);
  }
});
test('data evidence is required when a seven-day template is filled', () => {
  const p=readJSON(path.join(ROOT,'posts/f4-01-movement.json'));
  const spec=readJSON(path.join(ROOT,'formats/f4-seven-days.json'));
  for(const slide of p.slides) for(const key of Object.keys(slide.copy)) slide.copy[key]=slide.copy[key].replace(/{{.*?}}/g,'10');
  assert.throws(()=>validate(p,spec),/need a source/);
});
test('input paths cannot escape their directories', () => {
  for(const value of ['../bad','a/b','--all','']) assert.throws(()=>identifier(value));
  for(const value of ['images/../../secret.jpg','https://example.com/p.png','images/a.svg']) assert.throws(()=>imagePath(value));
});
test('new-post expands empty slots and refuses to overwrite', () => {
  // Run an isolated copy so no test fixture enters the real posts directory.
  const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'earnit-new-post-'));
  try {
    for(const folder of ['formats','posts','lib']) fs.mkdirSync(path.join(temporary,folder));
    for(const file of ['new-post.js','lib/model.js','formats/f2-pov-pushups.json']) fs.copyFileSync(path.join(ROOT,file),path.join(temporary,file));
    const run=()=>spawnSync(process.execPath,[path.join(temporary,'new-post.js'),'f2-pov-pushups','example','es'],{encoding:'utf8'});
    assert.equal(run().status,0);
    const p=readJSON(path.join(temporary,'posts/example.json'));
    assert.equal(p.language,'es');assert.equal(p.slides.length,6);
    assert.ok(p.slides.every(s=>Object.values(s.copy).every(v=>v==='')));
    assert.notEqual(run().status,0);
  } finally { fs.rmSync(temporary,{recursive:true,force:true}); }
});
