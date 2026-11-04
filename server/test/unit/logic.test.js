import test from 'node:test';
import assert from 'node:assert/strict';
import { clampUpdatedAt, describeChange, filterLinks, mergeReminders, nextCompletedAt } from '../../src/services/threadLogic.js';
import { planClaims } from '../../src/services/reminderPlan.js';
import { loadConfig, parseTrustProxy } from '../../src/config.js';
import { parseServiceAccount } from '../../src/services/push.js';
import { sha256 } from '../../src/services/tokens.js';

const now = new Date('2026-06-15T10:00:00Z');

test('clampUpdatedAt allows now+5min at most', () => {
  assert.equal(clampUpdatedAt('2026-06-15T10:03:00Z', now).toISOString(), '2026-06-15T10:03:00.000Z');
  assert.equal(clampUpdatedAt('2030-01-01T00:00:00Z', now).toISOString(), '2026-06-15T10:05:00.000Z');
  assert.equal(clampUpdatedAt('2020-01-01T00:00:00Z', now).toISOString(), '2020-01-01T00:00:00.000Z');
});
test('reminder keeps sentAt only when id and at are unchanged', () => {
  const sent = new Date('2026-06-15T09:00:00Z');
  const stored = [
    { id: 'a', at: new Date('2026-06-15T08:00:00Z'), sentAt: sent },
    { id: 'b', at: new Date('2026-06-15T08:00:00Z'), sentAt: sent },
  ];
  const r = mergeReminders(
    [
      { id: 'a', at: '2026-06-15T08:00:00.000Z' },
      { id: 'b', at: '2026-06-15T08:30:00Z' },
      { id: 'c', at: '2026-06-15T08:00:00Z' },
    ],
    stored,
  );
  assert.equal(r[0].sentAt, sent);
  assert.equal(r[1].sentAt, null);
  assert.equal(r[2].sentAt, null);
});
test('completedAt set on done, kept while done, cleared otherwise', () => {
  const earlier = new Date('2026-06-01T00:00:00Z');
  assert.equal(nextCompletedAt('done', { status: 'todo', completedAt: null }, now), now);
  assert.equal(nextCompletedAt('done', null, now), now);
  assert.equal(nextCompletedAt('done', { status: 'done', completedAt: earlier }, now), earlier);
  assert.equal(nextCompletedAt('doing', { status: 'done', completedAt: earlier }, now), null);
});
test('filterLinks drops unknown, self and duplicate ids', () => {
  assert.deepEqual(filterLinks(['a', 'self', 'x', 'a', 'b'], ['a', 'b', 'self'], 'self'), ['a', 'b']);
});
test('describeChange', () => {
  const base = { title: 'T', notes: '', type: 'task', priority: 'low', spaceId: 's', dueAt: null, tags: [], checklist: [], reminders: [], links: [], status: 'todo' };
  assert.equal(describeChange(null, base)[0].kind, 'created');
  assert.deepEqual(describeChange(base, { ...base }), []);
  assert.deepEqual(describeChange(base, { ...base, status: 'done' }).map((c) => c.kind), ['status']);
  assert.deepEqual(describeChange(base, { ...base, links: ['x'], title: 'U' }).map((c) => c.kind), ['linked', 'updated']);
});

test('planClaims: skips done/deleted/sent/future; marks stale as silent', () => {
  const h = 3600_000;
  const mk = (over) => ({
    status: 'todo',
    deletedAt: null,
    reminders: [
      { id: 'due', at: new Date(now - h), sentAt: null },
      { id: 'sent', at: new Date(now - h), sentAt: now },
      { id: 'future', at: new Date(+now + h), sentAt: null },
      { id: 'stale', at: new Date(now - 30 * h), sentAt: null },
    ],
    ...over,
  });
  assert.deepEqual(
    planClaims(mk(), now, 24 * h).map((c) => [c.reminderId, c.mode]),
    [['due', 'deliver'], ['stale', 'silent']],
  );
  assert.deepEqual(planClaims(mk({ status: 'done' }), now, 24 * h), []);
  assert.deepEqual(planClaims(mk({ deletedAt: now }), now, 24 * h), []);
});

test('config: dev defaults, production hard failures', () => {
  const dev = loadConfig({});
  assert.equal(dev.port, 4000);
  assert.deepEqual(dev.corsOrigins, ['*']);
  assert.throws(() => loadConfig({ NODE_ENV: 'production' }), /JWT_ACCESS_SECRET is required/);
  const long = 'x'.repeat(40);
  const ok = { NODE_ENV: 'production', MONGODB_URI: 'mongodb://m/db', JWT_ACCESS_SECRET: long, JWT_REFRESH_SECRET: long + 'y', CORS_ORIGINS: 'https://a.example' };
  assert.equal(loadConfig(ok).isProd, true);
  assert.throws(() => loadConfig({ ...ok, JWT_ACCESS_SECRET: 'short' }), /at least 32/);
  assert.throws(() => loadConfig({ ...ok, JWT_REFRESH_SECRET: long }), /must differ/);
  assert.throws(() => loadConfig({ ...ok, CORS_ORIGINS: '*' }), /must not contain/);
  assert.throws(() => loadConfig({ ...ok, BCRYPT_COST: '5' }), /BCRYPT_COST/);
  assert.throws(() => loadConfig({ PORT: 'abc' }), /PORT/);
});
test('parseTrustProxy', () => {
  assert.equal(parseTrustProxy(undefined), false);
  assert.equal(parseTrustProxy('1'), 1);
  assert.equal(parseTrustProxy('true'), true);
  assert.equal(parseTrustProxy('loopback'), 'loopback');
});
test('parseServiceAccount accepts raw JSON and base64', () => {
  const json = JSON.stringify({ project_id: 'p', client_email: 'e' });
  assert.equal(parseServiceAccount(json).project_id, 'p');
  assert.equal(parseServiceAccount(Buffer.from(json).toString('base64')).project_id, 'p');
  assert.throws(() => parseServiceAccount('{"a":1}'));
});
test('sha256 is stable hex', () => {
  assert.equal(sha256('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
});
