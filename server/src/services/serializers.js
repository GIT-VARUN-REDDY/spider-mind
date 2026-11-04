const iso = (d) => (d ? new Date(d).toISOString() : null);

export function serializeThread(t) {
  return {
    id: String(t._id),
    title: t.title,
    notes: t.notes ?? '',
    type: t.type,
    status: t.status,
    priority: t.priority,
    spaceId: String(t.spaceId),
    dueAt: iso(t.dueAt),
    reminders: (t.reminders ?? []).map((r) => ({ id: r.id, at: iso(r.at), sentAt: iso(r.sentAt) })),
    tags: t.tags ?? [],
    keywords: t.keywords ?? [],
    links: (t.links ?? []).map(String),
    checklist: (t.checklist ?? []).map((c) => ({ id: c.id, text: c.text, done: !!c.done })),
    createdAt: iso(t.createdAt),
    updatedAt: iso(t.updatedAt),
    completedAt: iso(t.completedAt),
  };
}

export const serializeSpace = (s) => ({ id: String(s._id), name: s.name, color: s.color, order: s.order });
export const serializeUser = (u) => ({ id: String(u._id ?? u.id), email: u.email, name: u.name, timezone: u.timezone });
export const serializeActivity = (a) => ({
  id: String(a._id),
  kind: a.kind,
  threadId: String(a.threadId),
  message: a.message,
  at: iso(a.at),
});
