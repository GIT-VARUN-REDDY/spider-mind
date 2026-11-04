import { Activity, Thread } from '../models/index.js';
import { serializeActivity, serializeThread } from './serializers.js';
import { planClaims } from './reminderPlan.js';

const BATCH = 200;
const MAX_BATCHES_PER_TICK = 10;

/**
 * Reminder scheduler. Safe with several API instances: a reminder is only handled
 * by the instance whose updateOne actually flips sentAt (modifiedCount === 1).
 */
export function createReminderScheduler({ config, logger, hub, push }) {
  const { tickMs, catchupMs } = config.reminders;
  let timer = null;
  let running = null;

  async function claim(thread, c, now) {
    const res = await Thread.updateOne(
      {
        _id: thread._id,
        deletedAt: null,
        status: { $ne: 'done' },
        reminders: { $elemMatch: { id: c.reminderId, at: c.at, sentAt: null } },
      },
      { $set: { 'reminders.$.sentAt': now, syncedAt: now }, $inc: { rev: 1 } },
    );
    return res.modifiedCount === 1;
  }

  async function deliver(thread, c, now) {
    const userId = String(thread.userId);
    const doc = await Activity.create({
      userId,
      kind: 'reminder',
      threadId: thread._id,
      message: `Reminder: "${thread.title}"`.slice(0, 200),
      at: now,
    });
    hub.emit(userId, 'activity:new', { activity: serializeActivity(doc) });
    hub.emit(userId, 'reminder:due', {
      threadId: String(thread._id),
      reminderId: c.reminderId,
      title: thread.title,
      at: c.at.toISOString(),
    });
    const fresh = await Thread.findById(thread._id).lean();
    if (fresh) hub.emit(userId, 'thread:upsert', { thread: serializeThread(fresh), origin: null });
    try {
      await push.sendToUser(userId, {
        title: thread.title,
        body: thread.notes ? thread.notes.slice(0, 120) : 'Reminder',
        data: { type: 'reminder', threadId: String(thread._id), reminderId: c.reminderId },
      });
    } catch (err) {
      logger.warn('push failed', { err, threadId: String(thread._id) });
    }
  }

  /** One pass. Returns how many reminders this instance delivered. */
  async function tick(now = new Date()) {
    let delivered = 0;
    for (let batch = 0; batch < MAX_BATCHES_PER_TICK; batch++) {
      const due = await Thread.find({
        deletedAt: null,
        status: { $ne: 'done' },
        reminders: { $elemMatch: { at: { $lte: now }, sentAt: null } },
      })
        .limit(BATCH)
        .lean();
      let progressed = 0;
      for (const thread of due) {
        for (const c of planClaims(thread, now, catchupMs)) {
          try {
            if (!(await claim(thread, c, now))) continue;
            progressed++;
            if (c.mode === 'deliver') {
              await deliver(thread, c, now);
              delivered++;
            }
          } catch (err) {
            logger.error('reminder handling failed', { err, threadId: String(thread._id) });
          }
        }
      }
      if (due.length < BATCH || progressed === 0) break;
    }
    return delivered;
  }

  const guardedTick = () => {
    if (running) return running; // never overlap ticks within one process
    running = tick()
      .catch((err) => logger.error('reminder tick failed', { err }))
      .finally(() => {
        running = null;
      });
    return running;
  };

  return {
    tick,
    start() {
      if (timer) return;
      timer = setInterval(guardedTick, tickMs);
      timer.unref();
      guardedTick(); // catches up on reminders that came due while we were down
    },
    async stop() {
      if (timer) clearInterval(timer);
      timer = null;
      await running;
    },
  };
}
