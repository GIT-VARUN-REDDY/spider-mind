import { Activity } from '../models/index.js';
import { serializeActivity } from './serializers.js';

export function createActivityService({ hub }) {
  return {
    /** Persists an entry and pushes `activity:new` to the user's devices. */
    async record(userId, { kind, threadId, message, at = new Date() }) {
      const doc = await Activity.create({ userId, kind, threadId, message: message.slice(0, 200), at });
      const activity = serializeActivity(doc);
      hub.emit(String(userId), 'activity:new', { activity });
      return activity;
    },
  };
}
