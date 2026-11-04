import { Router } from 'express';
import { Activity, Device, Thread } from '../models/index.js';
import { asyncHandler, validate } from '../middleware/common.js';
import {
  activityQuery,
  deviceBody,
  deviceDeleteQuery,
  idParam,
  spaceBody,
  spaceDeleteQuery,
  threadBody,
  threadsQuery,
} from '../validation/schemas.js';
import { computeInsights } from '../services/insights.js';
import { serializeActivity } from '../services/serializers.js';

const MAX_DEVICES = 20;

/** Authenticated resource routes: spaces, threads, insights, activity, devices. */
export function dataRouter({ spaces, threads }) {
  const r = Router();

  r.get('/spaces', asyncHandler(async (req, res) => res.json({ spaces: await spaces.list(req.user.id) })));
  r.put(
    '/spaces/:id',
    validate({ params: idParam, body: spaceBody }),
    asyncHandler(async (req, res) => res.json({ space: await spaces.put(req.user.id, req.params.id, req.body, req.clientId) })),
  );
  r.delete(
    '/spaces/:id',
    validate({ params: idParam, query: spaceDeleteQuery }),
    asyncHandler(async (req, res) => {
      await spaces.remove(req.user.id, req.params.id, req.query.moveTo, req.clientId);
      res.status(204).end();
    }),
  );

  r.get(
    '/threads',
    validate({ query: threadsQuery }),
    asyncHandler(async (req, res) => res.json(await threads.list(req.user.id, req.query.since))),
  );
  r.put(
    '/threads/:id',
    validate({ params: idParam, body: threadBody }),
    asyncHandler(async (req, res) => res.json(await threads.put(req.user.id, req.params.id, req.body, req.clientId))),
  );
  r.get(
    '/threads/:id',
    validate({ params: idParam }),
    asyncHandler(async (req, res) => res.json({ thread: await threads.get(req.user.id, req.params.id) })),
  );
  r.delete(
    '/threads/:id',
    validate({ params: idParam }),
    asyncHandler(async (req, res) => {
      await threads.remove(req.user.id, req.params.id, req.clientId);
      res.status(204).end();
    }),
  );

  r.get(
    '/insights',
    asyncHandler(async (req, res) => {
      const rows = await Thread.find({ userId: req.user.id, deletedAt: null }).select('status dueAt completedAt').lean();
      res.json(computeInsights(rows, new Date(), req.user.timezone));
    }),
  );

  r.get(
    '/activity',
    validate({ query: activityQuery }),
    asyncHandler(async (req, res) => {
      const { limit, before, threadId } = req.query;
      const q = { userId: req.user.id };
      if (before) q.at = { $lt: new Date(before) };
      if (threadId) q.threadId = threadId;
      const rows = await Activity.find(q).sort({ at: -1, _id: -1 }).limit(limit).lean();
      res.json({ activity: rows.map(serializeActivity) });
    }),
  );

  r.put(
    '/devices',
    validate({ body: deviceBody }),
    asyncHandler(async (req, res) => {
      const { token, platform } = req.body;
      await Device.updateOne(
        { token },
        { $set: { userId: req.user.id, platform, lastSeenAt: new Date() } },
        { upsert: true },
      );
      const extra = await Device.find({ userId: req.user.id }).sort({ lastSeenAt: -1 }).skip(MAX_DEVICES).select('_id').lean();
      if (extra.length) await Device.deleteMany({ _id: { $in: extra.map((d) => d._id) } });
      res.status(204).end();
    }),
  );
  r.delete(
    '/devices',
    validate({ query: deviceDeleteQuery }),
    asyncHandler(async (req, res) => {
      await Device.deleteOne({ userId: req.user.id, token: req.query.token });
      res.status(204).end();
    }),
  );
  return r;
}
