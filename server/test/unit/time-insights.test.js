import test from 'node:test';
import assert from 'node:assert/strict';
import { addDaysToKey, isValidTimeZone, localDateKey } from '../../src/utils/time.js';
import { computeInsights, computeStreak } from '../../src/services/insights.js';

test('localDateKey honours the zone', () => {
  const d = new Date('2026-03-10T23:30:00Z');
  assert.equal(localDateKey(d, 'UTC'), '2026-03-10');
  assert.equal(localDateKey(d, 'Pacific/Auckland'), '2026-03-11');
  assert.equal(localDateKey(d, 'America/Los_Angeles'), '2026-03-10');
});
test('localDateKey across a DST change', () => {
  // US DST began 2026-03-08 at 02:00 local; 06:30Z is 23:30 the day before (PST, -8).
  assert.equal(localDateKey(new Date('2026-03-08T07:30:00Z'), 'America/New_York'), '2026-03-08');
  assert.equal(localDateKey(new Date('2026-03-08T04:59:00Z'), 'America/New_York'), '2026-03-07');
});
test('addDaysToKey crosses month and year', () => {
  assert.equal(addDaysToKey('2026-01-01', -1), '2025-12-31');
  assert.equal(addDaysToKey('2026-02-27', 3), '2026-03-02');
});
test('time zone validation', () => {
  assert.ok(isValidTimeZone('Europe/Berlin'));
  assert.ok(!isValidTimeZone('Mars/Base'));
  assert.equal(localDateKey(new Date('2026-01-01T00:00:00Z'), 'Mars/Base'), '2026-01-01');
});

const T = (over) => ({ status: 'todo', dueAt: null, completedAt: null, ...over });
const now = new Date('2026-06-15T10:00:00Z');

test('counts', () => {
  const r = computeInsights(
    [
      T({ dueAt: '2026-06-14T10:00:00Z' }), // overdue
      T({ dueAt: '2026-06-15T09:00:00Z' }), // overdue + today
      T({ dueAt: '2026-06-15T20:00:00Z' }), // today
      T({ dueAt: '2026-06-18T08:00:00Z' }), // next 7
      T({ dueAt: '2026-06-22T08:00:00Z' }), // day +7: included
      T({ dueAt: '2026-06-23T08:00:00Z' }), // day +8: no
      T({ status: 'doing' }),
      T({ status: 'done', dueAt: '2026-06-14T10:00:00Z', completedAt: '2026-06-15T08:00:00Z' }),
    ],
    now,
    'UTC',
  );
  assert.deepEqual(r.counts, { total: 8, open: 7, done: 1, overdue: 2, dueToday: 2, dueNext7: 2 });
});
test('completedByDay has 14 oldest-first days in the user zone', () => {
  const r = computeInsights(
    [
      T({ status: 'done', completedAt: '2026-06-15T09:30:00Z' }),
      T({ status: 'done', completedAt: '2026-06-14T23:30:00Z' }), // Berlin: June 15
      T({ status: 'done', completedAt: '2026-06-02T12:00:00Z' }), // outside the window
    ],
    now,
    'Europe/Berlin',
  );
  assert.equal(r.completedByDay.length, 14);
  assert.equal(r.completedByDay[0].date, '2026-06-02');
  assert.equal(r.completedByDay[0].count, 1);
  assert.deepEqual(r.completedByDay[13], { date: '2026-06-15', count: 2 });
});
test('streak: today counts; empty today falls back to yesterday; gap resets', () => {
  const m = (...days) => new Map(days.map((d) => [d, 1]));
  assert.equal(computeStreak(m('2026-06-15', '2026-06-14', '2026-06-13'), '2026-06-15'), 3);
  assert.equal(computeStreak(m('2026-06-14', '2026-06-13'), '2026-06-15'), 2);
  assert.equal(computeStreak(m('2026-06-13'), '2026-06-15'), 0);
  assert.equal(computeStreak(m('2026-06-15', '2026-06-13'), '2026-06-15'), 1);
  assert.equal(computeStreak(new Map(), '2026-06-15'), 0);
});
test('streak is not limited to the 14 day window', () => {
  const days = Array.from({ length: 30 }, (_, i) => ({
    status: 'done',
    completedAt: new Date(now.getTime() - i * 86400_000).toISOString(),
  }));
  assert.equal(computeInsights(days, now, 'UTC').streak, 30);
});
