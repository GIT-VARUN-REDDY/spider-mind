import test from 'node:test';
import assert from 'node:assert/strict';
import { startTestServer } from '../helpers/env.js';

const t = await startTestServer({ RATE_LIMIT_AUTH_MAX: '3', RATE_LIMIT_GLOBAL_MAX: '8' });
if (!t) {
  test('rate limit integration (SKIPPED: no MongoDB)', { skip: 'no MongoDB available' }, () => {});
} else {
  test.after(() => t.close());

  test('auth routes: 429 after 3 requests, standard error shape', async () => {
    const codes = [];
    for (let i = 0; i < 5; i++) codes.push((await t.api.post('/api/v1/auth/login').send({ email: 'a@b.co', password: 'x' })).status);
    assert.deepEqual(codes, [401, 401, 401, 429, 429]);
    const r = await t.api.post('/api/v1/auth/login').send({ email: 'a@b.co', password: 'x' });
    assert.equal(r.body.error.code, 'RATE_LIMITED');
  });

  test('health endpoints are never throttled; global limit applies elsewhere', async () => {
    for (let i = 0; i < 12; i++) assert.equal((await t.api.get('/healthz')).status, 200);
    let last;
    for (let i = 0; i < 12; i++) last = (await t.api.get('/api/v1/threads')).status;
    assert.equal(last, 429);
  });
}
