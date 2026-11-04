import test from 'node:test';
import assert from 'node:assert/strict';
import { hex24, registerUser, startTestServer } from '../helpers/env.js';

const t = await startTestServer();
if (!t) {
  test('auth integration (SKIPPED: no MongoDB)', { skip: 'no MongoDB available' }, () => {});
} else {
  test.after(() => t.close());
  const V = '/api/v1';

  test('register creates user + 3 default spaces; duplicate email is 409', async () => {
    const u = await registerUser(t, { timezone: 'Europe/Berlin' });
    assert.equal(u.expiresIn, 900);
    assert.equal(u.user.timezone, 'Europe/Berlin');
    assert.equal(u.user.passwordHash, undefined);
    const spaces = await t.api.get(`${V}/spaces`).set(u.headers);
    assert.deepEqual(spaces.body.spaces.map((s) => [s.name, s.color, s.order]), [
      ['Work', '#32B4FF', 0],
      ['Study', '#3DDC97', 1],
      ['Personal', '#FF2A44', 2],
    ]);
    const dup = await t.api.post(`${V}/auth/register`).send({ email: u.email.toUpperCase(), password: 'abcdefgh', name: 'X' });
    assert.equal(dup.status, 409);
    assert.equal(dup.body.error.code, 'CONFLICT');
  });

  test('login: same 401 for unknown email and wrong password', async () => {
    const u = await registerUser(t);
    const ok = await t.api.post(`${V}/auth/login`).send({ email: u.email, password: 'correct horse' });
    assert.equal(ok.status, 200);
    assert.ok(ok.body.accessToken && ok.body.refreshToken);
    const bad = await t.api.post(`${V}/auth/login`).send({ email: u.email, password: 'nope nope' });
    const unknown = await t.api.post(`${V}/auth/login`).send({ email: 'ghost@example.com', password: 'nope nope' });
    assert.equal(bad.status, 401);
    assert.equal(unknown.status, 401);
    assert.deepEqual(bad.body, unknown.body);
  });

  test('refresh rotates; reusing an old token revokes the family', async () => {
    const u = await registerUser(t);
    const r1 = await t.api.post(`${V}/auth/refresh`).send({ refreshToken: u.refreshToken });
    assert.equal(r1.status, 200);
    assert.notEqual(r1.body.refreshToken, u.refreshToken);
    assert.equal(r1.body.expiresIn, 900);
    const r2 = await t.api.post(`${V}/auth/refresh`).send({ refreshToken: r1.body.refreshToken });
    assert.equal(r2.status, 200);
    // replay the first token: 401 and the whole family dies
    const replay = await t.api.post(`${V}/auth/refresh`).send({ refreshToken: u.refreshToken });
    assert.equal(replay.status, 401);
    const afterRevoke = await t.api.post(`${V}/auth/refresh`).send({ refreshToken: r2.body.refreshToken });
    assert.equal(afterRevoke.status, 401);
    // a new login is a new family and still works
    const login = await t.api.post(`${V}/auth/login`).send({ email: u.email, password: 'correct horse' });
    const ok = await t.api.post(`${V}/auth/refresh`).send({ refreshToken: login.body.refreshToken });
    assert.equal(ok.status, 200);
  });

  test('logout is always 204 and kills the token', async () => {
    const u = await registerUser(t);
    assert.equal((await t.api.post(`${V}/auth/logout`).send({ refreshToken: u.refreshToken })).status, 204);
    assert.equal((await t.api.post(`${V}/auth/logout`).send({ refreshToken: 'garbage' })).status, 204);
    assert.equal((await t.api.post(`${V}/auth/logout`).send({})).status, 204);
    assert.equal((await t.api.post(`${V}/auth/refresh`).send({ refreshToken: u.refreshToken })).status, 401);
  });

  test('/me get + patch, tz validation', async () => {
    const u = await registerUser(t);
    const me = await t.api.get(`${V}/me`).set(u.headers);
    assert.equal(me.body.user.email, u.email);
    const p = await t.api.patch(`${V}/me`).set(u.headers).send({ name: 'New', timezone: 'Asia/Tokyo' });
    assert.deepEqual([p.body.user.name, p.body.user.timezone], ['New', 'Asia/Tokyo']);
    assert.equal((await t.api.patch(`${V}/me`).set(u.headers).send({ timezone: 'Nope/Zone' })).status, 400);
    assert.equal((await t.api.patch(`${V}/me`).set(u.headers).send({})).status, 400);
  });

  test('validation and auth errors use the standard shape', async () => {
    const short = await t.api.post(`${V}/auth/register`).send({ email: 'a@b.co', password: 'short', name: 'A' });
    assert.equal(short.status, 400);
    assert.equal(short.body.error.code, 'VALIDATION');
    assert.ok(Array.isArray(short.body.error.details));
    assert.equal((await t.api.post(`${V}/auth/register`).send({ email: 'not-an-email', password: 'longenough', name: 'A' })).status, 400);

    const noAuth = await t.api.get(`${V}/threads`);
    assert.equal(noAuth.status, 401);
    assert.equal(noAuth.body.error.code, 'UNAUTHORIZED');
    assert.equal((await t.api.get(`${V}/threads`).set('Authorization', 'Bearer junk')).status, 401);

    const u = await registerUser(t);
    const badId = await t.api.get(`${V}/threads/not-an-id`).set(u.headers);
    assert.equal(badId.status, 400);
    assert.equal((await t.api.get(`${V}/threads/${hex24()}`).set(u.headers)).status, 404);
    const nf = await t.api.get(`${V}/nothing-here`).set(u.headers);
    assert.equal(nf.status, 404);
    assert.equal(nf.body.error.code, 'NOT_FOUND');
    const bad = await t.api.post(`${V}/auth/login`).set('Content-Type', 'application/json').send('{oops');
    assert.equal(bad.status, 400);
    assert.equal(bad.body.error.code, 'VALIDATION');
    const big = await t.api.post(`${V}/auth/login`).send({ email: 'a@b.co', password: 'x'.repeat(300_000) });
    assert.equal(big.status, 400);
  });

  test('health endpoints', async () => {
    assert.deepEqual((await t.api.get('/healthz')).body, { ok: true });
    assert.deepEqual((await t.api.get(`${V}/readyz`)).body, { ok: true, db: 'up' });
  });

  test('delete account purges everything and invalidates tokens', async () => {
    const u = await registerUser(t);
    const other = await registerUser(t);
    const spaces = (await t.api.get(`${V}/spaces`).set(u.headers)).body.spaces;
    const id = hex24();
    await t.api.put(`${V}/threads/${id}`).set(u.headers).send({
      title: 'x', type: 'task', status: 'todo', priority: 'low', spaceId: spaces[0].id, updatedAt: new Date().toISOString(),
    });
    await t.api.put(`${V}/devices`).set(u.headers).send({ token: 'tok-' + u.email, platform: 'android' });

    assert.equal((await t.api.delete(`${V}/me`).set(u.headers).send({ password: 'wrong password' })).status, 401);
    assert.equal((await t.api.delete(`${V}/me`).set(u.headers).send({ password: 'correct horse' })).status, 204);

    assert.equal((await t.api.get(`${V}/me`).set(u.headers)).status, 401);
    assert.equal((await t.api.post(`${V}/auth/refresh`).send({ refreshToken: u.refreshToken })).status, 401);
    assert.equal((await t.api.post(`${V}/auth/login`).send({ email: u.email, password: 'correct horse' })).status, 401);
    const { Thread, Space, Activity, Device, RefreshToken } = await import('../../src/models/index.js');
    const filter = { userId: u.user.id };
    const counts = await Promise.all([Thread, Space, Activity, Device, RefreshToken].map((m) => m.countDocuments(filter)));
    assert.deepEqual(counts, [0, 0, 0, 0, 0]);
    assert.equal((await t.api.get(`${V}/me`).set(other.headers)).status, 200); // others untouched
  });

  test('/auth/config returns configured googleClientId', async () => {
    const res = await t.api.get(`${V}/auth/config`);
    assert.equal(res.status, 200);
    assert.ok('googleClientId' in res.body);
  });

  test('/auth/google validates token and signs in / registers user', async () => {
    const originalFetch = global.fetch;
    try {
      const mockGoogleId = 'sub-google-test-101';
      const mockEmail = `g_${Date.now()}@example.com`;

      global.fetch = async (url) => {
        if (url.includes('id_token=valid.jwt.token')) {
          return {
            ok: true,
            status: 200,
            json: async () => ({
              iss: 'https://accounts.google.com',
              email: mockEmail,
              email_verified: 'true',
              aud: t.config.googleClientId || undefined,
              sub: mockGoogleId,
              name: 'Google Spidey',
              picture: 'https://lh3.googleusercontent.com/pic',
              exp: Math.floor(Date.now() / 1000) + 3600,
            }),
          };
        }
        return { ok: false, status: 400, json: async () => ({}) };
      };

      // 1. Invalid credential -> 401
      const bad = await t.api.post(`${V}/auth/google`).send({ credential: 'invalid.token.here' });
      assert.equal(bad.status, 401);
      assert.equal(bad.body.error.code, 'UNAUTHORIZED');

      // 2. Valid credential -> 200 + creates user + default spaces + issue tokens
      const ok = await t.api.post(`${V}/auth/google`).send({ credential: 'valid.jwt.token' });
      assert.equal(ok.status, 200);
      assert.equal(ok.body.user.email, mockEmail);
      assert.equal(ok.body.user.name, 'Google Spidey');
      assert.ok(ok.body.accessToken);
      assert.ok(ok.body.refreshToken);

      // Verify default spaces were created
      const spaces = await t.api.get(`${V}/spaces`).set('Authorization', `Bearer ${ok.body.accessToken}`);
      assert.equal(spaces.body.spaces.length, 3);

      // 3. Repeat sign-in logs into same account
      const okAgain = await t.api.post(`${V}/auth/google`).send({ credential: 'valid.jwt.token' });
      assert.equal(okAgain.status, 200);
      assert.equal(okAgain.body.user.id, ok.body.user.id);
    } finally {
      global.fetch = originalFetch;
    }
  });
}
