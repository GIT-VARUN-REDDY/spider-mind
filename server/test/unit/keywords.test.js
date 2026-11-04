import test from 'node:test';
import assert from 'node:assert/strict';
import { deriveKeywords } from '../../src/services/keywords.js';

test('lowercases, splits on non-alphanumerics, drops short words', () => {
  assert.deepEqual(deriveKeywords('Buy MILK, eggs & bread!'), ['milk', 'egg', 'bread']);
});
test('drops stop words', () => {
  assert.deepEqual(deriveKeywords('What should this be about'), []);
});
test('strips ing/ed only when length > 5', () => {
  assert.deepEqual(deriveKeywords('planning'), ['plann']);
  assert.deepEqual(deriveKeywords('finished'), ['finish']);
  assert.deepEqual(deriveKeywords('bring'), ['bring']); // length 5
  assert.deepEqual(deriveKeywords('speed'), ['speed']); // length 5
});
test('strips a single trailing s except ss, when length > 3', () => {
  assert.deepEqual(deriveKeywords('tasks class boss'), ['task', 'class', 'boss']);
  assert.deepEqual(deriveKeywords('bus'), []);
  assert.deepEqual(deriveKeywords('meetings'), ['meeting']);
});
test('de-duplicates across title, notes and tags, in first-seen order', () => {
  assert.deepEqual(deriveKeywords('Budget review', 'review the budgets', ['Finance', 'budget']), [
    'budget',
    'review',
    'finance',
  ]);
});
test('caps at 20 keywords', () => {
  const words = Array.from({ length: 40 }, (_, i) => `word${String.fromCharCode(97 + (i % 26))}${i}x`);
  assert.equal(deriveKeywords(words.join(' ')).length, 20);
});
test('handles empty input and non-ASCII separators', () => {
  assert.deepEqual(deriveKeywords('', '', []), []);
  assert.deepEqual(deriveKeywords('naïve plan'), ['plan']);
});
