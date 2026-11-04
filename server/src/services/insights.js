import { addDaysToKey, localDateKey } from '../utils/time.js';

/**
 * Pure. `threads` are live (not deleted) threads with status, dueAt, completedAt.
 * dueToday / dueNext7 are by calendar day in the user's zone and only count open
 * threads; dueNext7 covers tomorrow through today+7. overdue = open and dueAt < now.
 */
export function computeInsights(threads, now, timeZone) {
  const today = localDateKey(now, timeZone);
  const horizon = addDaysToKey(today, 7);
  const counts = { total: threads.length, open: 0, done: 0, overdue: 0, dueToday: 0, dueNext7: 0 };
  const doneByDay = new Map();

  for (const t of threads) {
    if (t.status === 'done') {
      counts.done++;
      if (t.completedAt) {
        const k = localDateKey(new Date(t.completedAt), timeZone);
        doneByDay.set(k, (doneByDay.get(k) ?? 0) + 1);
      }
      continue;
    }
    counts.open++;
    if (!t.dueAt) continue;
    const due = new Date(t.dueAt);
    if (due < now) counts.overdue++;
    const k = localDateKey(due, timeZone);
    if (k === today) counts.dueToday++;
    else if (k > today && k <= horizon) counts.dueNext7++;
  }

  const completedByDay = [];
  for (let i = 13; i >= 0; i--) {
    const date = addDaysToKey(today, -i);
    completedByDay.push({ date, count: doneByDay.get(date) ?? 0 });
  }
  return { counts, completedByDay, streak: computeStreak(doneByDay, today) };
}

/** Consecutive days with >= 1 completion, ending today or (if today is empty) yesterday. */
export function computeStreak(doneByDay, today) {
  let day = doneByDay.get(today) ? today : addDaysToKey(today, -1);
  let streak = 0;
  while (doneByDay.get(day)) {
    streak++;
    day = addDaysToKey(day, -1);
  }
  return streak;
}
