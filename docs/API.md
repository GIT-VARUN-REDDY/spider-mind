# Spider Mind API reference

Node.js 20 (Express 4, Mongoose 8, Socket.IO 4). Base path `/api/v1`, JSON UTF-8. The binding spec is
`docs/CONTRACT.md`; this file documents how the server implements it.

```bash
API=http://localhost:4000/api/v1
```

## Conventions

* Auth: `Authorization: Bearer <accessToken>` on everything except `/auth/*`, `/healthz`, `/readyz`.
* `X-Client-Id: <random per install>` is optional; it is echoed as `origin` in realtime events caused by that request.
* `X-Request-Id` is accepted or generated and returned; it appears in the JSON access log.
* Ids are 24 hex characters, chosen by the client. Timestamps are ISO-8601 UTC.
* Errors always have this shape:

```json
{"error":{"code":"VALIDATION","message":"Validation failed","details":[{"path":"title","message":"..."}]}}
```

| HTTP | code | meaning |
|---|---|---|
| 400 | VALIDATION | bad body/query/params, malformed JSON, body over 256kb, limits exceeded |
| 401 | UNAUTHORIZED | missing/invalid/expired token, bad credentials, deleted account |
| 403 | FORBIDDEN | reserved |
| 404 | NOT_FOUND | unknown resource or route |
| 409 | CONFLICT | email taken, id owned by another user, space delete rules |
| 429 | RATE_LIMITED | 300 req/min/IP overall, 20 req/min/IP on `/auth/*` (health probes exempt) |
| 500 | INTERNAL | unexpected; details are only in the server log |

Limits per user: 1000 threads, 20 reminders per thread, 50 checklist items, 30 tags (<= 30 chars), 100 links, 20 spaces.

## Auth

```bash
curl -X POST $API/auth/register -H 'Content-Type: application/json' \
  -d '{"email":"me@example.com","password":"correct horse","name":"Me","timezone":"Europe/Berlin"}'
# 201 {"user":{"id","email","name","timezone"},"accessToken","refreshToken","expiresIn":900}

curl -X POST $API/auth/login   -H 'Content-Type: application/json' -d '{"email":"me@example.com","password":"correct horse"}'
curl -X POST $API/auth/refresh -H 'Content-Type: application/json' -d '{"refreshToken":"..."}'
# 200 {"accessToken","refreshToken","expiresIn":900}
curl -X POST $API/auth/logout  -H 'Content-Type: application/json' -d '{"refreshToken":"..."}'   # always 204
curl $API/me -H "Authorization: Bearer $TOKEN"
curl -X PATCH $API/me -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"name":"New","timezone":"Asia/Tokyo"}'
curl -X DELETE $API/me -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"password":"correct horse"}'  # 204
```

* Registration creates the spaces Work `#32B4FF`, Study `#3DDC97`, Personal `#FF2A44`.
* Login answers 401 "Invalid email or password" for both unknown email and wrong password (and spends the same bcrypt time).
* Access tokens are HS256 JWTs valid 15 minutes. Refresh tokens are HS256 JWTs valid 30 days, stored only as SHA-256 hashes.
* **Rotation and reuse detection:** every refresh token works exactly once. Presenting a token that was already used (or
  revoked) answers 401 and deletes the whole token family, so the legitimate holder must log in again. Two concurrent
  refreshes with the same token therefore also end the session; clients must serialise refreshes.
* `DELETE /me` removes the user, spaces, threads (including tombstones), activity, devices and refresh tokens, and
  disconnects the user's sockets.

## Spaces

```bash
curl $API/spaces -H "Authorization: Bearer $TOKEN"
curl -X PUT $API/spaces/64b7f0c2a1b2c3d4e5f60718 -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"name":"Garden","color":"#3ddc97","order":3}'        # 200 {"space":{...}} (color is upper-cased)
curl -X DELETE "$API/spaces/<id>?moveTo=<otherSpaceId>" -H "Authorization: Bearer $TOKEN"   # 204
```

Delete rules: 404 if unknown; 409 if it is your last space; 409 if it still has live threads and `moveTo` is missing,
equal to the id or not yours; otherwise the threads move (each gets a new `updatedAt`, `thread:upsert` is emitted). A space
without threads can be deleted without `moveTo`.

## Threads

```bash
curl -X PUT $API/threads/64b7f0c2a1b2c3d4e5f60719 -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -H 'X-Client-Id: phone-1' -d '{
  "title":"Send invoice","notes":"","type":"task","status":"todo","priority":"high",
  "spaceId":"64b7f0c2a1b2c3d4e5f60718","dueAt":"2026-06-20T09:00:00Z",
  "reminders":[{"id":"64b7f0c2a1b2c3d4e5f6071a","at":"2026-06-20T08:00:00Z"}],
  "tags":["billing"],"links":[],"checklist":[{"id":"64b7f0c2a1b2c3d4e5f6071b","text":"Attach PDF","done":false}],
  "createdAt":"2026-06-15T10:00:00Z","updatedAt":"2026-06-15T10:00:00Z"}'
# 200 {"thread":{...,"keywords":["send","invoice","billing"],"completedAt":null},"applied":true}

curl "$API/threads?since=2026-06-15T10:00:00Z" -H "Authorization: Bearer $TOKEN"
# {"threads":[...],"deletedIds":["..."],"serverTime":"2026-06-15T10:05:00.123Z"}
curl $API/threads/<id> -H "Authorization: Bearer $TOKEN"
curl -X DELETE $API/threads/<id> -H "Authorization: Bearer $TOKEN"   # 204, idempotent
```

PUT semantics:

* Required: `title`, `type`, `status`, `priority`, `spaceId`, `updatedAt`. If `id` is in the body it must match the URL.
  `keywords`, `completedAt` and `sentAt` from clients are ignored.
* **Last-writer-wins:** if the stored `updatedAt` is newer than the body's, nothing changes and `{thread: stored, applied:false}`
  is returned. Equal timestamps apply. The client `updatedAt` is clamped to server-now + 5 minutes.
* `completedAt` is set when status becomes `done`, kept while it stays done, cleared otherwise. `createdAt` is taken from the
  first write and never changes afterwards.
* A reminder keeps `sentAt` only if both its `id` and `at` are unchanged.
* `spaceId` must be one of your spaces (400). `links` are silently reduced to ids of your live threads, without the thread itself and duplicates.
* Keywords: lowercase, split on non-alphanumerics (`[^a-z0-9]+`, ASCII only), drop words under 4 chars and a stop list
  (`src/services/keywords.js`), strip trailing `ing`/`ed` when length > 5, then a single trailing `s` (not `ss`) when length > 3,
  de-duplicate in order of appearance, keep 20.
* An id that belongs to another user answers 409 (never leaks or overwrites). Editing a thread that was deleted after the
  edit's `updatedAt` answers 404 (the delete wins); a newer edit resurrects it.
* **Delete** is a soft delete: a tombstone (`deletedAt`) kept 90 days (Mongo TTL), the id is pulled from other threads'
  `links` (those threads get a new `updatedAt` and a `thread:upsert`).
* **Sync:** `GET /threads` without `since` returns all live threads and `deletedIds: []`. With `since` it returns threads
  whose `updatedAt` > since **or** that were written by the server after `since` (this also catches writes from devices with
  a slow clock and reminder `sentAt` changes), plus ids deleted after `since`. `serverTime` is read before the query, so
  storing it as the next cursor never skips a write.

## Insights

`GET /insights` -> `{counts:{total,open,done,overdue,dueToday,dueNext7}, completedByDay:[{date,count} x14], streak}`.
Everything is computed over live threads in the user's time zone (`PATCH /me`).
`open` = not done; `overdue` = open and `dueAt` < now; `dueToday` = open and due on today's local date (may also be overdue);
`dueNext7` = open and due on a local date from tomorrow through today+7. `completedByDay` counts threads by the local date of
`completedAt`, oldest first, today last. `streak` = consecutive local days with at least one completion, ending today, or
yesterday when today has none.

## Activity

`GET /activity?limit=50&before=<ISO>&threadId=<id>` -> `{activity:[{id,kind,threadId,message,at}]}`, newest first, limit max 100.
Written on create (`created`), status change (`status`), new links (`linked`), content changes (`updated`), delete (`deleted`)
and reminder delivery (`reminder`). A repeated identical PUT writes nothing. Kept 90 days.

## Devices (push)

```bash
curl -X PUT $API/devices -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"token":"<fcm token>","platform":"android"}'  # 204
curl -X DELETE "$API/devices?token=<fcm token>" -H "Authorization: Bearer $TOKEN"                                                                  # 204
```

A token belongs to one user (re-registering moves it). At most 20 devices per user are kept (oldest dropped).

## Ops

`GET /healthz` -> `{"ok":true}`; `GET /readyz` -> `{"ok":true,"db":"up"}` or 503 `{"ok":false,"db":"down"}`. Both also exist
at the root (`/healthz`) for container probes. Both skip rate limiting.

## Realtime (Socket.IO v4, path `/socket.io`)

```js
const socket = io(baseUrl, { auth: { token: accessToken } });   // bad/expired token => connect_error "unauthorized"
```

The server joins you to room `user:<id>`. Server to client events:

| event | payload |
|---|---|
| `thread:upsert` | `{thread, origin}` (also for link clean-up, space moves and reminder `sentAt`; `origin` null for server-caused changes) |
| `thread:delete` | `{id, origin}` |
| `space:upsert` / `space:delete` | `{space, origin}` / `{id, origin}` |
| `activity:new` | `{activity}` |
| `reminder:due` | `{threadId, reminderId, title, at}` |

`origin` is the `X-Client-Id` of the causing request or null; clients ignore events with their own id. The client sends nothing.
The handshake is the only authentication; sockets of a deleted account are disconnected.

## Reminders

Every `REMINDER_TICK_MS` (15 s) each API instance runs the scheduler:

1. Finds live, not-done threads with a reminder where `at <= now` and `sentAt == null`.
2. **Claims** each reminder with `updateOne({_id, reminders: {$elemMatch: {id, at, sentAt: null}}}, {$set: {'reminders.$.sentAt': now}})`;
   only the instance with `modifiedCount === 1` continues, so several instances never double-deliver.
3. Writes an Activity (`reminder`), emits `activity:new`, `reminder:due` and `thread:upsert` (with `sentAt`) to `user:<id>`, and
   sends an FCM push to the user's devices.

Catch-up: on start the first tick delivers everything that came due while the server was down, as long as it is at most
`REMINDER_CATCHUP_HOURS` (24) old. Older reminders are marked sent without push, event or activity. Done and deleted threads are
never touched (their reminders stay unsent, and are retired by the same rule if the thread is reopened later).

Push: set `FCM_SERVICE_ACCOUNT_JSON` (raw JSON or base64). `firebase-admin` is loaded lazily; when it is not configured or not
installed the server logs once and skips push. Tokens FCM reports as invalid/unregistered are deleted.

## Scaling notes

* Reminder claiming and token rotation are safe across instances (atomic Mongo updates).
* Socket.IO uses the in-memory adapter: an event is emitted to sockets connected to the instance that handled the request or
  claimed the reminder. Behind several instances either use sticky routing and a shared adapter (not bundled) or rely on the
  other two layers (pull sync on foreground, on-device reminders, FCM push).
* Rate limits are per instance and per IP; set `TRUST_PROXY` correctly behind a proxy.

## Environment variables

See `server/.env.example` for the annotated list: `NODE_ENV, PORT, HOST, MONGODB_URI, JWT_ACCESS_SECRET, JWT_REFRESH_SECRET,
BCRYPT_COST, CORS_ORIGINS, TRUST_PROXY, RATE_LIMIT_WINDOW_MS, RATE_LIMIT_GLOBAL_MAX, RATE_LIMIT_AUTH_MAX, BODY_LIMIT,
REMINDER_SCHEDULER_ENABLED, REMINDER_TICK_MS, REMINDER_CATCHUP_HOURS, FCM_SERVICE_ACCOUNT_JSON, LOG_LEVEL, SHUTDOWN_TIMEOUT_MS`.
In production the server refuses to start without both JWT secrets (>= 32 chars, different) and `MONGODB_URI`, with `*` in
`CORS_ORIGINS`, or with `BCRYPT_COST` < 10.

## Running

```bash
cd server && cp .env.example .env && npm ci && npm run dev          # needs MongoDB
docker compose up --build                                            # from the repo root (set JWT secrets in .env)
npm run test:unit                                                    # no database
MONGODB_URI=mongodb://localhost:27017 npm run test:integration       # uses a throwaway database per test file
```

Without `MONGODB_URI` the integration tests try `mongodb-memory-server` (uses `mongod` from PATH or `MONGOMS_SYSTEM_BINARY`);
if no MongoDB is available they print a loud banner and report the suite as skipped. `REQUIRE_MONGO=1` turns that into a failure.
