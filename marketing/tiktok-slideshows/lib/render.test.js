'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { ROOT, readJSON } = require('./model');
const { slideHTML } = require('../render');

test('copy is escaped rather than interpreted as markup', () => {
  const post = readJSON(path.join(ROOT,'posts/f1-01-autopilot.json'));
  const format = readJSON(path.join(ROOT,'formats/f1-listicle.json'));
  post.slides[0].copy.title='<script>alert("oops")</script>';
  const html=slideHTML(post,format,post.slides[0],format.slides[0],{},new Set());
  assert.ok(html.includes('&lt;script&gt;'));
  assert.ok(!html.includes('<script>'));
});
test('loaded photos do not inherit the ivory fallback text colors', () => {
  const post = readJSON(path.join(ROOT,'posts/f1-01-autopilot.json'));
  const format = readJSON(path.join(ROOT,'formats/f1-listicle.json'));
  // An existing placeholder supplies a local fixture; no photograph is generated.
  const fixture=path.join(ROOT,'images/photo-test.png');
  try {
    fs.writeFileSync(fixture,Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6RYkAAAAASUVORK5CYII=','base64'),{flag:'wx'});
    post.slides[1].image='images/photo-test.png';
    const html=slideHTML(post,format,post.slides[1],format.slides[1],{},new Set());
    assert.ok(html.includes('native photo layout-text-body'));
    assert.ok(!html.includes('fallback-ivory'));
  } finally { fs.rmSync(fixture,{force:true}); }
});
test('draft asset labels remain visible when the same missing icon appears twice', () => {
  const post=readJSON(path.join(ROOT,'posts/f6-01-swap.json'));
  const format=readJSON(path.join(ROOT,'formats/f6-app-list.json'));
  const warnings=new Set();
  slideHTML(post,format,post.slides[0],format.slides[0],{},warnings);
  const first=slideHTML(post,format,post.slides[1],format.slides[1],{},warnings);
  const second=slideHTML(post,format,post.slides[1],format.slides[1],{},warnings);
  assert.ok(first.includes('draft · assets needed'));
  assert.ok(second.includes('draft · assets needed'));
});
