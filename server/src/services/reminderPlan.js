// Pure part of the reminder scheduler: which due reminders to deliver or silently retire.
/**
 * @returns {{reminderId:string, at:Date, mode:'deliver'|'silent'}[]}
 * Done/deleted threads are skipped entirely. Reminders that came due longer than
 * `catchupMs` ago are retired without a push (the moment has passed).
 */
export function planClaims(thread, now, catchupMs) {
  if (thread.deletedAt || thread.status === 'done') return [];
  const out = [];
  for (const r of thread.reminders ?? []) {
    if (r.sentAt) continue;
    const at = new Date(r.at);
    if (at > now) continue;
    out.push({ reminderId: r.id, at, mode: now - at > catchupMs ? 'silent' : 'deliver' });
  }
  return out;
}
