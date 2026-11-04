// Pure. The Dart client implements the same rules (CONTRACT.md section 1).
export const MAX_KEYWORDS = 20;

export const STOP_WORDS = new Set(
  (
    'about above after again also been before being below between both come could does doing down during each ' +
    'from further gets getting have having here hers herself himself into itself just like make many more most ' +
    'much must myself need only other ours ourselves over same should some such take than that their theirs ' +
    'them themselves then there these they this those through under until upon very want was were what when ' +
    'where which while whom will with would your yours yourself yourselves'
  ).split(' '),
);

function stem(w) {
  if (w.length > 5 && (w.endsWith('ing') || w.endsWith('ed'))) w = w.slice(0, w.endsWith('ing') ? -3 : -2);
  if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) w = w.slice(0, -1);
  return w;
}

/** Derives keywords from title + notes + tags: first-appearance order, max 20. */
export function deriveKeywords(title = '', notes = '', tags = []) {
  const text = [title, notes, ...tags].join(' ').toLowerCase();
  const out = [];
  const seen = new Set();
  for (const raw of text.split(/[^a-z0-9]+/)) {
    if (raw.length < 4 || STOP_WORDS.has(raw)) continue;
    const w = stem(raw);
    if (seen.has(w)) continue;
    seen.add(w);
    out.push(w);
    if (out.length === MAX_KEYWORDS) break;
  }
  return out;
}
