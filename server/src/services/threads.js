import { Space, Thread } from '../models/index.js';
import { LIMITS } from '../validation/schemas.js';
import { AppError, badRequest, conflict, notFound } from '../utils/errors.js';
import { toOid } from '../utils/ids.js';
import { deriveKeywords } from './keywords.js';
import { serializeThread } from './serializers.js';
import { activityMessage, clampUpdatedAt, describeChange, filterLinks, mergeReminders, nextCompletedAt } from './threadLogic.js';

const MAX_ATTEMPTS = 5;

export function createThreadService({ hub, activity }) {
  const emitUpsert = (userId, thread, origin) => hub.emit(userId, 'thread:upsert', { thread, origin });

  async function liveLinkIds(userId, ids) {
    if (!ids.length) return [];
    const rows = await Thread.find({ userId, _id: { $in: ids }, deletedAt: null }).select('_id').lean();
    return rows.map((r) => String(r._id));
  }

  /** Upsert with last-writer-wins. Returns {thread, applied}. */
  async function put(userId, id, body, origin) {
    if (body.id && body.id !== id) throw badRequest('Body id does not match URL id');
    if (!(await Space.exists({ _id: body.spaceId, userId }))) throw badRequest('spaceId is not one of your spaces');

    const now = new Date();
    const updatedAt = clampUpdatedAt(body.updatedAt, now);
    const links = filterLinks(body.links, await liveLinkIds(userId, body.links), id);

    for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
      const stored = await Thread.findOne({ _id: id }).lean();
      if (stored && String(stored.userId) !== userId) throw conflict('Id is already in use');

      const tombstone = stored?.deletedAt ?? null;
      if (tombstone && updatedAt < tombstone) throw notFound('Thread was deleted');
      if (stored && !tombstone && stored.updatedAt > updatedAt) {
        return { thread: serializeThread(stored), applied: false };
      }
      const live = stored && !tombstone ? stored : null;
      if (!live && (await Thread.countDocuments({ userId, deletedAt: null })) >= LIMITS.threads) {
        throw badRequest(`Thread limit of ${LIMITS.threads} reached`);
      }

      const createdAt = live ? live.createdAt : clampUpdatedAt(body.createdAt ?? now, now);
      const next = {
        title: body.title,
        notes: body.notes,
        type: body.type,
        status: body.status,
        priority: body.priority,
        spaceId: toOid(body.spaceId),
        dueAt: body.dueAt ? new Date(body.dueAt) : null,
        reminders: mergeReminders(body.reminders, live?.reminders),
        tags: body.tags,
        keywords: deriveKeywords(body.title, body.notes, body.tags),
        links: links.map(toOid),
        checklist: body.checklist,
        createdAt,
        updatedAt,
        completedAt: nextCompletedAt(body.status, live, now),
        deletedAt: null,
        syncedAt: now,
      };

      let saved;
      if (!stored) {
        try {
          saved = (await Thread.create({ _id: id, userId, rev: 0, ...next })).toObject();
        } catch (err) {
          if (err?.code === 11000) continue;
          throw err;
        }
      } else {
        saved = await Thread.findOneAndUpdate(
          { _id: id, userId, rev: stored.rev },
          { $set: next, $inc: { rev: 1 } },
          { new: true, lean: true },
        );
        if (!saved) continue; // someone (client, scheduler) wrote in between: re-evaluate
      }

      const thread = serializeThread(saved);
      emitUpsert(userId, thread, origin);
      for (const c of describeChange(live, next)) {
        await activity.record(userId, { ...c, threadId: id, at: now });
      }
      return { thread, applied: true };
    }
    throw new AppError(409, 'CONFLICT', 'Concurrent update, please retry');
  }

  async function get(userId, id) {
    const t = await Thread.findOne({ _id: id, userId, deletedAt: null }).lean();
    if (!t) throw notFound('Thread not found');
    return serializeThread(t);
  }

  async function list(userId, since) {
    const serverTime = new Date(); // taken before reading so no write can fall in a gap
    if (!since) {
      const rows = await Thread.find({ userId, deletedAt: null }).sort({ createdAt: 1, _id: 1 }).lean();
      return { threads: rows.map(serializeThread), deletedIds: [], serverTime: serverTime.toISOString() };
    }
    const s = new Date(since);
    const [rows, gone] = await Promise.all([
      Thread.find({ userId, deletedAt: null, $or: [{ updatedAt: { $gt: s } }, { syncedAt: { $gt: s } }] })
        .sort({ updatedAt: 1, _id: 1 })
        .lean(),
      Thread.find({ userId, deletedAt: { $gt: s } }).select('_id').lean(),
    ]);
    return {
      threads: rows.map(serializeThread),
      deletedIds: gone.map((g) => String(g._id)),
      serverTime: serverTime.toISOString(),
    };
  }

  /** Idempotent soft delete; strips the id from other threads' links. */
  async function remove(userId, id, origin) {
    const now = new Date();
    const t = await Thread.findOneAndUpdate(
      { _id: id, userId, deletedAt: null },
      { $set: { deletedAt: now, syncedAt: now }, $inc: { rev: 1 } },
      { new: true, lean: true },
    );
    if (!t) return;
    const linked = await Thread.find({ userId, deletedAt: null, links: id }).select('_id').lean();
    if (linked.length) {
      const ids = linked.map((l) => l._id);
      await Thread.updateMany(
        { userId, _id: { $in: ids } },
        { $pull: { links: toOid(id) }, $set: { updatedAt: now, syncedAt: now }, $inc: { rev: 1 } },
      );
      const fresh = await Thread.find({ userId, _id: { $in: ids } }).lean();
      for (const f of fresh) emitUpsert(userId, serializeThread(f), origin);
    }
    hub.emit(userId, 'thread:delete', { id, origin });
    await activity.record(userId, { kind: 'deleted', threadId: id, message: activityMessage('Deleted', t.title), at: now });
  }

  return { put, get, list, remove };
}
