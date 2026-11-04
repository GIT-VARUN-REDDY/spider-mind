import test from 'node:test';
import assert from 'node:assert/strict';
import { hex24, registerUser, startTestServer, threadBody } from '../helpers/env.js';

const t = await startTestServer();
if (!t) {
  test('threads integration (SKIPPED: no MongoDB)', { skip: 'no MongoDB available' }, () => {});
} else {
  test.after(() => t.close());
  const V = '/api/v1';
  const put = (u, id, body, extra = {}) => t.api.put(`${V}/threads/${id}`).set(u.headers).set(extra).send(body);
  const spacesOf = async (u) => (await t.api.get(`${V}/spaces`).set(u.headers)).body.spaces;
  const iso = (ms) => new Date(Date.now() + ms).toISOString();

  test('PUT creates, is idempotent, derives keywords, GET returns it', async () => {
    const u = await registerUser(t);
    const [work] = await spacesOf(u);
    const id = hex24();
    const body = threadBody(work.id, { title: 'Planning budgets', notes: 'review quarterly numbers', tags: ['Finance'] });
    const r = await put(u, id, { ...body, id });
    assert.equal(r.status, 200);
    assert.equal(r.body.applied, true);
    assert.equal(r.body.thread.id, id);
    assert.deepEqual(r.body.thread.keywords, ['plann', 'budget', 'review', 'quarterly', 'number', 'finance']);
    assert.equal(r.body.thread.completedAt, null);
    const again = await put(u, id, body);
    assert.equal(again.body.applied, true);
    assert.equal(again.body.thread.createdAt, r.body.thread.createdAt);
    const g = await t.api.get(`${V}/threads/${id}`).set(u.headers);
    assert.equal(g.body.thread.title, 'Planning budgets');
    const list = await t.api.get(`${V}/threads`).set(u.headers);
    assert.equal(list.body.threads.length, 1);
    assert.deepEqual(list.body.deletedIds, []);
    assert.ok(Date.parse(list.body.serverTime));
  });

  test('last-writer-wins on updatedAt, clamp to now+5min, completedAt handling', async () => {
    const u = await registerUser(t);
    const [work] = await spacesOf(u);
    const id = hex24();
    const t0 = iso(-60_000);
    await put(u, id, threadBody(work.id, { title: 'v2', updatedAt: iso(-10_000) }));
    const stale = await put(u, id, threadBody(work.id, { title: 'v1', updatedAt: t0 }));
    assert.equal(stale.body.applied, false);
    assert.equal(stale.body.thread.title, 'v2');

    const done = await put(u, id, threadBody(work.id, { title: 'v3', status: 'done', updatedAt: iso(-5_000) }));
    assert.equal(done.body.applied, true);
    const completedAt = done.body.thread.completedAt;
    assert.ok(completedAt);
    const stillDone = await put(u, id, threadBody(work.id, { title: 'v4', status: 'done', updatedAt: iso(-1000) }));
    assert.equal(stillDone.body.thread.completedAt, completedAt);
    const reopened = await put(u, id, threadBody(work.id, { status: 'doing', updatedAt: iso(0) }));
    assert.equal(reopened.body.thread.completedAt, null);

    const future = await put(u, id, threadBody(work.id, { title: 'future', updatedAt: '2099-01-01T00:00:00Z' }));
    assert.equal(future.body.applied, true);
    const clamped = Date.parse(future.body.thread.updatedAt);
    assert.ok(clamped <= Date.now() + 5 * 60_000 + 1000 && clamped > Date.now() + 4 * 60_000);
  });

  test('reminder sentAt survives only when id and at are unchanged', async () => {
    const u = await registerUser(t);
    const [work] = await spacesOf(u);
    const id = hex24();
    const r1 = hex24();
    const r2 = hex24();
    const at = iso(-3600_000);
    await put(u, id, threadBody(work.id, { updatedAt: iso(-5000), reminders: [{ id: r1, at }, { id: r2, at }] }));
    await t.reminders.tick();
    const sent = (await t.api.get(`${V}/threads/${id}`).set(u.headers)).body.thread.reminders;
    assert.ok(sent.every((r) => r.sentAt));
    const upd = await put(u, id, threadBody(work.id, { reminders: [{ id: r1, at }, { id: r2, at: iso(3600_000) }] }));
    const [a, b] = upd.body.thread.reminders;
    assert.ok(a.sentAt);
    assert.equal(b.sentAt, null);
  });

  test('since returns changes + tombstones; delete is idempotent and unlinks', async () => {
    const u = await registerUser(t);
    const [work] = await spacesOf(u);
    const a = hex24();
    const b = hex24();
    await put(u, a, threadBody(work.id, { title: 'alpha' }));
    await put(u, b, threadBody(work.id, { title: 'beta', links: [a] }));
    const first = await t.api.get(`${V}/threads`).set(u.headers);
    assert.deepEqual(first.body.threads.find((x) => x.id === b).links, [a]);
    const cursor = first.body.serverTime;
    await new Promise((r) => setTimeout(r, 15));

    assert.equal((await t.api.delete(`${V}/threads/${a}`).set(u.headers)).status, 204);
    assert.equal((await t.api.delete(`${V}/threads/${a}`).set(u.headers)).status, 204);
    assert.equal((await t.api.delete(`${V}/threads/${hex24()}`).set(u.headers)).status, 204);
    assert.equal((await t.api.get(`${V}/threads/${a}`).set(u.headers)).status, 404);

    const delta = await t.api.get(`${V}/threads`).query({ since: cursor }).set(u.headers);
    assert.deepEqual(delta.body.deletedIds, [a]);
    assert.deepEqual(delta.body.threads.map((x) => x.id), [b]); // beta changed: link pulled
    assert.deepEqual(delta.body.threads[0].links, []);
    const later = await t.api.get(`${V}/threads`).query({ since: delta.body.serverTime }).set(u.headers);
    assert.deepEqual([later.body.threads, later.body.deletedIds], [[], []]);
    const all = await t.api.get(`${V}/threads`).set(u.headers);
    assert.deepEqual(all.body.deletedIds, []);
    assert.equal(all.body.threads.length, 1);

    const act = await t.api.get(`${V}/activity`).set(u.headers);
    assert.ok(act.body.activity.some((x) => x.kind === 'deleted' && x.threadId === a));
    // an edit older than the deletion must not resurrect it
    const stale = await put(u, a, threadBody(work.id, { title: 'zombie', updatedAt: iso(-3600_000) }));
    assert.equal(stale.status, 404);
  });

  test('links are filtered to own, live, non-self threads', async () => {
    const u = await registerUser(t);
    const other = await registerUser(t);
    const [work] = await spacesOf(u);
    const [theirs] = await spacesOf(other);
    const mine = hex24();
    const foreign = hex24();
    const self = hex24();
    await put(u, mine, threadBody(work.id));
    await put(other, foreign, threadBody(theirs.id));
    const r = await put(u, self, threadBody(work.id, { links: [mine, foreign, self, hex24(), mine] }));
    assert.deepEqual(r.body.thread.links, [mine]);
  });

  test('validation: spaceId, limits, id mismatch, bad dates, foreign ids', async () => {
    const u = await registerUser(t);
    const other = await registerUser(t);
    const [work] = await spacesOf(u);
    const [theirs] = await spacesOf(other);
    const ok = threadBody(work.id);
    assert.equal((await put(u, hex24(), threadBody(hex24()))).status, 400);
    assert.equal((await put(u, hex24(), threadBody(theirs.id))).status, 400);
    assert.equal((await put(u, hex24(), { ...ok, id: hex24() })).status, 400);
    assert.equal((await put(u, hex24(), { ...ok, title: '' })).status, 400);
    assert.equal((await put(u, hex24(), { ...ok, title: 'x'.repeat(201) })).status, 400);
    assert.equal((await put(u, hex24(), { ...ok, notes: 'x'.repeat(2001) })).status, 400);
    assert.equal((await put(u, hex24(), { ...ok, type: 'epic' })).status, 400);
    assert.equal((await put(u, hex24(), { ...ok, updatedAt: 'yesterday' })).status, 400);
    assert.equal((await put(u, hex24(), { ...ok, tags: Array.from({ length: 31 }, (_, i) => `t${i}`) })).status, 400);
    assert.equal((await put(u, hex24(), { ...ok, tags: ['x'.repeat(31)] })).status, 400);
    assert.equal((await put(u, hex24(), { ...ok, reminders: Array.from({ length: 21 }, () => ({ id: hex24(), at: iso(1000) })) })).status, 400);
    assert.equal((await put(u, hex24(), { ...ok, checklist: Array.from({ length: 51 }, () => ({ id: hex24(), text: 'a' })) })).status, 400);
    assert.equal((await put(u, hex24(), { ...ok, links: Array.from({ length: 101 }, () => hex24()) })).status, 400);
    const good = await put(u, hex24(), { ...ok, checklist: [{ id: hex24(), text: 'step' }], dueAt: iso(86400_000), reminders: [{ id: hex24(), at: iso(1000) }] });
    assert.equal(good.status, 200);
    assert.equal(good.body.thread.checklist[0].done, false);
    // another user's id: no leak, no overwrite
    const id = hex24();
    await put(other, id, threadBody(theirs.id));
    assert.equal((await put(u, id, ok)).status, 409);
    assert.equal((await t.api.get(`${V}/threads/${id}`).set(u.headers)).status, 404);
    assert.equal((await t.api.delete(`${V}/threads/${id}`).set(u.headers)).status, 204);
    assert.equal((await t.api.get(`${V}/threads/${id}`).set(other.headers)).status, 200);
  });

  test('spaces: upsert, validation, delete rules with moveTo', async () => {
    const u = await registerUser(t);
    const [work, study, personal] = await spacesOf(u);
    const sid = hex24();
    const created = await t.api.put(`${V}/spaces/${sid}`).set(u.headers).send({ name: 'Garden', color: '#aabbcc', order: 3 });
    assert.equal(created.status, 200);
    assert.deepEqual(created.body.space, { id: sid, name: 'Garden', color: '#AABBCC', order: 3 });
    assert.equal((await t.api.put(`${V}/spaces/${sid}`).set(u.headers).send({ name: 'x', color: 'red', order: 0 })).status, 400);
    assert.equal((await t.api.put(`${V}/spaces/${sid}`).set(u.headers).send({ name: 'x'.repeat(41), color: '#000000', order: 0 })).status, 400);
    await t.api.put(`${V}/spaces/${sid}`).set(u.headers).send({ name: 'Garden 2', color: '#000000', order: 5 });
    assert.equal((await spacesOf(u))[3].name, 'Garden 2'); // sorted by order

    const th = hex24();
    await put(u, th, threadBody(work.id));
    assert.equal((await t.api.delete(`${V}/spaces/${work.id}`).set(u.headers)).status, 409);
    assert.equal((await t.api.delete(`${V}/spaces/${work.id}`).query({ moveTo: work.id }).set(u.headers)).status, 409);
    assert.equal((await t.api.delete(`${V}/spaces/${work.id}`).query({ moveTo: hex24() }).set(u.headers)).status, 409);
    assert.equal((await t.api.delete(`${V}/spaces/${work.id}`).query({ moveTo: study.id }).set(u.headers)).status, 204);
    assert.equal((await t.api.get(`${V}/threads/${th}`).set(u.headers)).body.thread.spaceId, study.id);
    assert.equal((await t.api.delete(`${V}/spaces/${personal.id}`).set(u.headers)).status, 204); // empty: no moveTo needed
    assert.equal((await t.api.delete(`${V}/spaces/${sid}`).set(u.headers)).status, 204);
    assert.equal((await t.api.delete(`${V}/spaces/${study.id}`).set(u.headers)).status, 409); // last space
    assert.equal((await t.api.delete(`${V}/spaces/${hex24()}`).set(u.headers)).status, 404);
    // 20 space cap
    const u2 = await registerUser(t);
    for (let i = 0; i < 17; i++) assert.equal((await t.api.put(`${V}/spaces/${hex24()}`).set(u2.headers).send({ name: `s${i}`, color: '#000000', order: i })).status, 200);
    assert.equal((await t.api.put(`${V}/spaces/${hex24()}`).set(u2.headers).send({ name: 'over', color: '#000000', order: 99 })).status, 400);
  });

  test('insights, activity paging/filter, devices', async () => {
    const u = await registerUser(t, { timezone: 'UTC' });
    const [work] = await spacesOf(u);
    const ids = [hex24(), hex24(), hex24()];
    await put(u, ids[0], threadBody(work.id, { title: 'overdue one', dueAt: iso(-86400_000 * 2) }));
    await put(u, ids[1], threadBody(work.id, { title: 'finished', status: 'done' }));
    await put(u, ids[2], threadBody(work.id, { title: 'someday', dueAt: iso(3 * 86400_000) }));
    const ins = (await t.api.get(`${V}/insights`).set(u.headers)).body;
    assert.equal(ins.counts.total, 3);
    assert.equal(ins.counts.open, 2);
    assert.equal(ins.counts.done, 1);
    assert.equal(ins.counts.overdue, 1);
    assert.equal(ins.completedByDay.length, 14);
    assert.equal(ins.completedByDay[13].count, 1);
    assert.equal(ins.streak, 1);

    const all = (await t.api.get(`${V}/activity`).set(u.headers)).body.activity;
    assert.ok(all.length >= 3);
    assert.deepEqual(Object.keys(all[0]).sort(), ['at', 'id', 'kind', 'message', 'threadId']);
    assert.ok(all.every((a, i) => i === 0 || a.at <= all[i - 1].at));
    const lim = (await t.api.get(`${V}/activity`).query({ limit: 2 }).set(u.headers)).body.activity;
    assert.equal(lim.length, 2);
    const before = (await t.api.get(`${V}/activity`).query({ before: lim[1].at }).set(u.headers)).body.activity;
    assert.ok(before.every((a) => a.at < lim[1].at));
    const one = (await t.api.get(`${V}/activity`).query({ threadId: ids[1] }).set(u.headers)).body.activity;
    assert.ok(one.length === 1 && one.every((a) => a.threadId === ids[1]));
    assert.deepEqual(one.map((a) => a.kind).sort(), ['created']);
    assert.equal((await t.api.get(`${V}/activity`).query({ limit: 101 }).set(u.headers)).status, 400);

    assert.equal((await t.api.put(`${V}/devices`).set(u.headers).send({ token: 'abc', platform: 'ios' })).status, 204);
    assert.equal((await t.api.put(`${V}/devices`).set(u.headers).send({ token: 'abc', platform: 'android' })).status, 204);
    assert.equal((await t.api.put(`${V}/devices`).set(u.headers).send({ token: 'abc', platform: 'tv' })).status, 400);
    const { Device } = await import('../../src/models/index.js');
    assert.equal(await Device.countDocuments({ token: 'abc' }), 1);
    assert.equal((await t.api.delete(`${V}/devices`).query({ token: 'abc' }).set(u.headers)).status, 204);
    assert.equal(await Device.countDocuments({ token: 'abc' }), 0);
  });
}
