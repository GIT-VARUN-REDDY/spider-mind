import { Space, Thread } from '../models/index.js';
import { LIMITS } from '../validation/schemas.js';
import { badRequest, conflict, notFound } from '../utils/errors.js';
import { toOid } from '../utils/ids.js';
import { serializeSpace, serializeThread } from './serializers.js';

export const DEFAULT_SPACES = [
  { name: 'Work', color: '#32B4FF' },
  { name: 'Study', color: '#3DDC97' },
  { name: 'Personal', color: '#FF2A44' },
];

export const createDefaultSpaces = (userId) =>
  Space.insertMany(DEFAULT_SPACES.map((s, order) => ({ userId, ...s, order })));

export function createSpaceService({ hub }) {
  return {
    async list(userId) {
      const rows = await Space.find({ userId }).sort({ order: 1, _id: 1 }).lean();
      return rows.map(serializeSpace);
    },

    async put(userId, id, body, origin) {
      const existing = await Space.findById(id).lean();
      if (existing && String(existing.userId) !== userId) throw conflict('Id is already in use');
      if (!existing && (await Space.countDocuments({ userId })) >= LIMITS.spaces) {
        throw badRequest(`Space limit of ${LIMITS.spaces} reached`);
      }
      const saved = await Space.findOneAndUpdate(
        { _id: id, userId },
        { $set: { name: body.name, color: body.color, order: body.order } },
        { upsert: true, new: true, lean: true, setDefaultsOnInsert: true },
      );
      const space = serializeSpace(saved);
      hub.emit(userId, 'space:upsert', { space, origin });
      return space;
    },

    async remove(userId, id, moveTo, origin) {
      const space = await Space.findOne({ _id: id, userId }).lean();
      if (!space) throw notFound('Space not found');
      if ((await Space.countDocuments({ userId })) <= 1) throw conflict('Cannot delete your last space');

      const inUse = await Thread.countDocuments({ userId, spaceId: id, deletedAt: null });
      let moved = [];
      if (inUse > 0) {
        if (!moveTo || moveTo === id || !(await Space.exists({ _id: moveTo, userId }))) {
          throw conflict('Space has threads: pass a valid moveTo space id');
        }
        const now = new Date();
        const ids = (await Thread.find({ userId, spaceId: id, deletedAt: null }).select('_id').lean()).map((t) => t._id);
        await Thread.updateMany(
          { userId, _id: { $in: ids } },
          { $set: { spaceId: toOid(moveTo), updatedAt: now, syncedAt: now }, $inc: { rev: 1 } },
        );
        moved = await Thread.find({ userId, _id: { $in: ids } }).lean();
      }
      await Space.deleteOne({ _id: id, userId });
      hub.emit(userId, 'space:delete', { id, origin });
      for (const t of moved) hub.emit(userId, 'thread:upsert', { thread: serializeThread(t), origin });
    },
  };
}
