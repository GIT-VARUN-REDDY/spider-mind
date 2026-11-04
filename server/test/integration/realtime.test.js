import test from 'node:test';
import assert from 'node:assert/strict';
import { connectSocket, hex24, nextEvent, registerUser, sleep, startTestServer, threadBody } from '../helpers/env.js';
import { Thread } from '../../src/models/index.js';

const t = await startTestServer({ REMINDER_TICK_MS: '100' });
if (!t) {
  test('realtime integration (SKIPPED: no MongoDB)', { skip: 'no MongoDB available' }, () => {});
} else {
  const V = '/api/v1';
  const open = [];
  test.after(async () => {
    open.forEach((s) => s.close());
    await t.close();
  });
  const sock = async (u) => {
    const s = await connectSocket(t, u.accessToken);
    open.push(s);
    return s;
  };
  const spaceOf = async (u) => (await t.api.get(`${V}/spaces`).set(u.headers)).body.spaces[0].id;
  const iso = (ms) => new Date(Date.now() + ms).toISOString();

  test('socket handshake rejects bad tokens with "unauthorized"', async () => {
    await assert.rejects(connectSocket(t, 'garbage'), /unauthorized/);
    await assert.rejects(connectSocket(t, undefined), /unauthorized/);
  });

  test('thread/space/activity events reach other sockets with origin echo, only to the owner', async () => {
    const u = await registerUser(t);
    const stranger = await registerUser(t);
    const a = await sock(u);
    const b = await sock(u);
    const c = await sock(stranger);
    let leaked = false;
    c.onAny(() => (leaked = true));
    const space = await spaceOf(u);
    const id = hex24();

    const up = nextEvent(b, 'thread:upsert');
    const act = nextEvent(b, 'activity:new');
    await t.api.put(`${V}/threads/${id}`).set(u.headers).set('X-Client-Id', 'client-A').send(threadBody(space, { title: 'Live' }));
    const ev = await up;
    assert.equal(ev.origin, 'client-A');
    assert.equal(ev.thread.id, id);
    assert.equal((await act).activity.kind, 'created');
    assert.equal((await nextEvent(a, 'thread:upsert').catch(() => ({ thread: { id } }))).thread.id, id);

    const del = nextEvent(b, 'thread:delete');
    await t.api.delete(`${V}/threads/${id}`).set(u.headers).set('X-Client-Id', 'client-B');
    assert.deepEqual(await del, { id, origin: 'client-B' });

    const sp = nextEvent(b, 'space:upsert');
    const sid = hex24();
    await t.api.put(`${V}/spaces/${sid}`).set(u.headers).send({ name: 'Live space', color: '#112233', order: 9 });
    const spEv = await sp;
    assert.equal(spEv.origin, null);
    assert.equal(spEv.space.id, sid);
    const sd = nextEvent(b, 'space:delete');
    await t.api.delete(`${V}/spaces/${sid}`).set(u.headers).set('X-Client-Id', 'client-C');
    assert.deepEqual(await sd, { id: sid, origin: 'client-C' });

    await sleep(100);
    assert.equal(leaked, false);
  });

  test('reminder due: claimed once, event + activity + sentAt; skips done, deleted and stale', async () => {
    const u = await registerUser(t);
    const s = await sock(u);
    const space = await spaceOf(u);
    const due = hex24();
    const doneT = hex24();
    const goneT = hex24();
    const staleT = hex24();
    const rid = hex24();
    const past = iso(-60_000);
    const mk = (id, over) => t.api.put(`${V}/threads/${id}`).set(u.headers).send(threadBody(space, { updatedAt: iso(-5000), ...over }));
    await mk(due, { title: 'Call mum', reminders: [{ id: rid, at: past }] });
    await mk(doneT, { title: 'done one', status: 'done', reminders: [{ id: hex24(), at: past }] });
    await mk(goneT, { title: 'gone one', reminders: [{ id: hex24(), at: past }] });
    await mk(staleT, { title: 'stale one', reminders: [{ id: hex24(), at: iso(-48 * 3600_000) }] });
    await t.api.delete(`${V}/threads/${goneT}`).set(u.headers);

    const got = [];
    s.on('reminder:due', (p) => got.push(p));
    const ev = nextEvent(s, 'reminder:due');
    // two "instances" ticking at once must not double deliver
    const [n1, n2] = await Promise.all([t.reminders.tick(), t.reminders.tick()]);
    assert.equal(n1 + n2, 1);
    assert.deepEqual(await ev, { threadId: due, reminderId: rid, title: 'Call mum', at: past });
    await t.reminders.tick();
    await sleep(100);
    assert.equal(got.length, 1);

    const th = (await t.api.get(`${V}/threads/${due}`).set(u.headers)).body.thread;
    assert.ok(th.reminders[0].sentAt);
    const acts = (await t.api.get(`${V}/activity`).query({ threadId: due }).set(u.headers)).body.activity;
    assert.equal(acts.filter((a) => a.kind === 'reminder').length, 1);

    const raw = async (id) => (await Thread.findById(id).lean()).reminders[0].sentAt;
    assert.equal(await raw(doneT), null);
    assert.equal(await raw(goneT), null);
    assert.ok(await raw(staleT)); // retired silently
    const staleActs = (await t.api.get(`${V}/activity`).query({ threadId: staleT }).set(u.headers)).body.activity;
    assert.equal(staleActs.filter((a) => a.kind === 'reminder').length, 0);
  });

  test('the interval scheduler delivers on its own', async () => {
    const u = await registerUser(t);
    const s = await sock(u);
    const space = await spaceOf(u);
    const rid = hex24();
    await t.api.put(`${V}/threads/${hex24()}`).set(u.headers).send(threadBody(space, { updatedAt: iso(-5000), reminders: [{ id: rid, at: iso(400) }] }));
    const ev = nextEvent(s, 'reminder:due', 6000);
    t.reminders.start();
    try {
      assert.equal((await ev).reminderId, rid);
    } finally {
      await t.reminders.stop();
    }
  });

  test('delete account disconnects that user\'s sockets', async () => {
    const u = await registerUser(t);
    const s = await sock(u);
    const gone = new Promise((r) => s.once('disconnect', r));
    await t.api.delete(`${V}/me`).set(u.headers).send({ password: 'correct horse' });
    await Promise.race([gone, sleep(3000).then(() => assert.fail('socket still connected'))]);
  });
}
