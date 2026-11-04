import { Router } from 'express';
import { dbIsUp } from '../db.js';

export function healthRouter() {
  const r = Router();
  r.get('/healthz', (_req, res) => res.json({ ok: true }));
  r.get('/readyz', async (_req, res) => {
    const up = await dbIsUp();
    res.status(up ? 200 : 503).json({ ok: up, db: up ? 'up' : 'down' });
  });
  return r;
}
