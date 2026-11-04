const dtfCache = new Map();

function dtf(timeZone) {
  let f = dtfCache.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hourCycle: 'h23',
    });
    dtfCache.set(timeZone, f);
  }
  return f;
}

const WINDOWS_TO_IANA = {
  'india standard time': 'Asia/Kolkata',
  'pacific standard time': 'America/Los_Angeles',
  'eastern standard time': 'America/New_York',
  'central standard time': 'America/Chicago',
  'mountain standard time': 'America/Denver',
  'gmt standard time': 'Europe/London',
  'greenwich standard time': 'GMT',
  'w. europe standard time': 'Europe/Berlin',
  'tokyo standard time': 'Asia/Tokyo',
  'china standard time': 'Asia/Shanghai',
  'singapore standard time': 'Asia/Singapore',
  'aus central standard time': 'Australia/Darwin',
  'aus eastern standard time': 'Australia/Sydney',
  'e. europe standard time': 'Europe/Bucharest',
  'central european standard time': 'Europe/Warsaw',
  'ist': 'Asia/Kolkata',
};

export function resolveTimeZone(tz) {
  if (typeof tz !== 'string' || !tz.trim()) return 'UTC';
  const clean = tz.trim();
  const mapped = WINDOWS_TO_IANA[clean.toLowerCase()];
  if (mapped) return mapped;
  return clean;
}

export function isValidTimeZone(tz) {
  if (typeof tz !== 'string' || !tz) return false;
  const resolved = resolveTimeZone(tz);
  try {
    dtf(resolved);
    return true;
  } catch {
    return false;
  }
}

/** Falls back to UTC when a stored zone is no longer known to the runtime. */
export const safeTimeZone = (tz) => (isValidTimeZone(tz) ? tz : 'UTC');

/** "YYYY-MM-DD" of an instant in the given IANA zone. */
export function localDateKey(date, timeZone) {
  const parts = dtf(safeTimeZone(timeZone)).formatToParts(date);
  const get = (t) => parts.find((p) => p.type === t).value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}

/** Calendar arithmetic on "YYYY-MM-DD" keys (zone independent). */
export function addDaysToKey(key, days) {
  const [y, m, d] = key.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + days));
  return t.toISOString().slice(0, 10);
}
