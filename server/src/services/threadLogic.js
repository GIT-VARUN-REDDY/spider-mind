// Pure helpers for PUT /threads/:id.
export const CLAMP_MS = 5 * 60 * 1000;

export const clampUpdatedAt = (value, now) => new Date(Math.min(new Date(value).getTime(), now.getTime() + CLAMP_MS));

/** A reminder keeps sentAt only when both its id and `at` are unchanged. */
export function mergeReminders(incoming, stored = []) {
  const byId = new Map(stored.map((r) => [r.id, r]));
  return incoming.map((r) => {
    const at = new Date(r.at);
    const prev = byId.get(r.id);
    const keep = prev && new Date(prev.at).getTime() === at.getTime();
    return { id: r.id, at, sentAt: keep ? (prev.sentAt ?? null) : null };
  });
}

/** completedAt is set when the status turns done, kept while it stays done, cleared otherwise. */
export function nextCompletedAt(status, stored, now) {
  if (status !== 'done') return null;
  return stored?.status === 'done' && stored.completedAt ? stored.completedAt : now;
}

/** Links must exist for this user, not be the thread itself, and be unique; order is preserved. */
export function filterLinks(requested, ownedIds, selfId) {
  const owned = new Set(ownedIds);
  const out = [];
  for (const id of requested) {
    if (id !== selfId && owned.has(id) && !out.includes(id)) out.push(id);
  }
  return out;
}

const trunc = (s, n) => (s.length > n ? s.slice(0, n - 1) + '…' : s);
export const activityMessage = (verb, title) => trunc(`${verb} "${title}"`, 200);

/** Which activity entries a save produces. `stored` is null for creates. */
export function describeChange(stored, next) {
  if (!stored) return [{ kind: 'created', message: activityMessage('Created', next.title) }];
  const out = [];
  if (stored.status !== next.status) {
    out.push({
      kind: 'status',
      message:
        next.status === 'done'
          ? activityMessage('Completed', next.title)
          : trunc(`Status ${stored.status} → ${next.status}: "${next.title}"`, 200),
    });
  }
  const before = new Set(stored.links.map(String));
  const added = next.links.filter((l) => !before.has(String(l)));
  if (added.length) {
    out.push({ kind: 'linked', message: trunc(`Linked ${added.length} thread${added.length > 1 ? 's' : ''} to "${next.title}"`, 200) });
  }
  const changed = (a, b) => JSON.stringify(a) !== JSON.stringify(b);
  const contentChanged =
    stored.title !== next.title ||
    stored.notes !== next.notes ||
    stored.type !== next.type ||
    stored.priority !== next.priority ||
    String(stored.spaceId) !== String(next.spaceId) ||
    (stored.dueAt?.getTime() ?? null) !== (next.dueAt?.getTime() ?? null) ||
    changed(stored.tags, next.tags) ||
    changed(stored.checklist, next.checklist) ||
    changed(stored.reminders.map((r) => [r.id, +new Date(r.at)]), next.reminders.map((r) => [r.id, +r.at]));
  if (contentChanged) out.push({ kind: 'updated', message: activityMessage('Updated', next.title) });
  return out;
}
