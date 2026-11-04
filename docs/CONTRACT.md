# PROJECT SPIDER: platform contract

Product: **Spider Mind** (brand: PROJECT SPIDER). A personal "thread" tracker. Every thing the user must
remember, do, decide or ask is a **thread**. Threads live in **spaces** (life areas) and are shown as a
**structured 3D spider web**. Threads are tracked live across devices and the user gets timely reminders.

Stack: Flutter app (Android, iOS, web), Node.js 20+ (Express, Socket.IO, Mongoose), MongoDB 6/7.
Dart package name `spider_mind`. App bundle id `app.projectspider.mind`. Display name "Project Spider".

Everything below is binding. Where this contract and your instinct differ, follow the contract.

## 1. Domain model

* **User**: id, email (unique, lowercase), name, passwordHash, timezone (IANA, default "UTC"), createdAt.
* **Space** (a spoke of the web): id, name (1-40), color ('#RRGGBB'), order (int). New users get three
  default spaces: Work `#32B4FF`, Study `#3DDC97`, Personal `#FF2A44`.
* **Thread**: see `app/lib/models/thread.dart` (authoritative field list). JSON on the wire:

```json
{
  "id": "24hex", "title": "string 1-200", "notes": "string 0-2000",
  "type": "idea|task|question|goal", "status": "todo|doing|done", "priority": "low|medium|high",
  "spaceId": "24hex", "dueAt": "ISO-8601 UTC|null",
  "reminders": [{"id": "24hex", "at": "ISO UTC", "sentAt": "ISO UTC|null"}],
  "tags": ["manual"], "keywords": ["server-derived"], "links": ["otherThreadId"],
  "checklist": [{"id": "24hex", "text": "1-200", "done": false}],
  "createdAt": "ISO", "updatedAt": "ISO", "completedAt": "ISO|null"
}
```
Limits per user: 1000 threads, 20 reminders per thread, 50 checklist items, 30 tags (each <= 30 chars),
100 links, 20 spaces.

* **Activity**: id, kind (`created|updated|status|reminder|linked|deleted`), threadId, message (<=200), at.
  It is the live tracking timeline. Written by the server on every thread mutation and reminder delivery.
  Keep 90 days (Mongo TTL index on `at`).
* **Device**: userId, token (FCM, unique), platform (`android|ios|web`), lastSeenAt.

Clients create ids themselves (24 hex chars, ObjectId-compatible) so create works offline and PUT is idempotent.

Key words: the server derives `keywords` from title + notes + tags on every save: lowercase, split on
non-alphanumerics, drop words under 4 chars and a stop list, strip a trailing "ing"/"ed" when length > 5, strip a
single trailing "s" (not "ss") when length > 3, de-duplicate, keep at most 20. Two threads that share a keyword
get an automatic weak link in the web. Explicit `links` are strong links. Edge building for the app is already
implemented in `app/lib/features/web3d/web_edges.dart`.

## 2. REST API (base path `/api/v1`, JSON, UTF-8)

All endpoints except auth, health and docs need `Authorization: Bearer <accessToken>`.
Every request may carry `X-Client-Id: <random per install>`; the server echoes it as `origin` in realtime events.

Errors always: `{"error":{"code":"VALIDATION|UNAUTHORIZED|FORBIDDEN|NOT_FOUND|CONFLICT|RATE_LIMITED|INTERNAL","message":"human readable","details":optional}}`
with HTTP 400, 401, 403, 404, 409, 429, 500.

### Auth
* `POST /auth/register` `{email, password(>=8, <=128), name(1-60), timezone?}` -> 201 `{user, accessToken, refreshToken, expiresIn}`; 409 if the email exists. Creates the 3 default spaces.
* `POST /auth/login` `{email, password}` -> 200 same shape; 401 on bad credentials (same message for unknown email and wrong password).
* `POST /auth/refresh` `{refreshToken}` -> 200 `{accessToken, refreshToken, expiresIn}`. Refresh tokens rotate; reusing an old one revokes that whole token family (401).
* `POST /auth/logout` `{refreshToken}` -> 204 (always).
* `GET /me` -> `{user}`; `PATCH /me` `{name?, timezone?}` -> `{user}`; `DELETE /me` `{password}` -> 204, deletes the user and ALL their data.
`user` = `{id, email, name, timezone}`. Access token lifetime 15 min (`expiresIn` is 900). Refresh token 30 days.

### Spaces
* `GET /spaces` -> `{spaces:[{id,name,color,order}]}` sorted by order.
* `PUT /spaces/:id` `{name, color, order}` upsert with a client-made id -> 200 `{space}`.
* `DELETE /spaces/:id?moveTo=<spaceId>` -> 204. 409 if the space has threads and no valid `moveTo`; 409 if it is the user's last space. Threads are moved when `moveTo` is given.

### Threads
* `GET /threads?since=<ISO>` -> `{threads:[Thread], deletedIds:[id], serverTime:"ISO"}`. Without `since` returns every live thread and `deletedIds: []`. With `since` returns threads with `updatedAt > since` and ids deleted after `since` (soft-delete tombstones kept 90 days). Clients store `serverTime` as the next cursor.
* `PUT /threads/:id` body = Thread without `keywords`/`completedAt`/`sentAt` (`dueAt`, `reminders`, `tags`, `links`, `checklist`, `notes`, `createdAt` optional) -> 200 `{thread, applied}`.
  Last-writer-wins on `updatedAt`: if the stored thread's `updatedAt` is newer than the body's, nothing changes and `{thread: stored, applied:false}` is returned. Otherwise the thread is upserted (`applied:true`). `updatedAt` from the client is clamped to at most server-now + 5 minutes. Server sets `completedAt` when status becomes `done` and clears it otherwise. A reminder keeps its `sentAt` only if its `id` and `at` are unchanged. `spaceId` must be one of the user's spaces (400 otherwise). `links` are filtered to ids that belong to the user and are not the thread itself. 400 when over the limits.
* `GET /threads/:id` -> `{thread}` or 404.
* `DELETE /threads/:id` -> 204, idempotent. Soft delete (tombstone), pulls the id from other threads' `links`.

### Insights
* `GET /insights` -> `{counts:{total,open,done,overdue,dueToday,dueNext7}, completedByDay:[{date:"YYYY-MM-DD",count}] (last 14 days incl. today, in the user's timezone, oldest first), streak:int (consecutive days up to today, or up to yesterday if today has none, with >= 1 completed thread)}`.

### Activity
* `GET /activity?limit=50&before=<ISO>&threadId=<id>` -> `{activity:[{id,kind,threadId,message,at}]}` newest first, limit max 100.

### Devices (push)
* `PUT /devices` `{token, platform}` -> 204. `DELETE /devices?token=` -> 204.

### Ops
* `GET /healthz` -> `{ok:true}`; `GET /readyz` -> `{ok:true, db:"up"}` or 503 when Mongo is down.

Security: helmet, CORS from `CORS_ORIGINS` (comma list, `*` allowed only when `NODE_ENV!=production`), global rate limit 300 req/min/IP,
auth routes 20 req/min/IP, JSON body limit 256kb, every query scoped by `userId`, zod validation on every body/query,
passwords hashed with bcryptjs (cost 12), JWT HS256 with separate access/refresh secrets, refresh tokens stored only as SHA-256 hashes.

## 3. Realtime (Socket.IO v4 on the same server, path `/socket.io`)

Handshake: `io(url, {auth:{token: accessToken}})`. Invalid/expired token -> connection error with message `unauthorized`
(the client refreshes the token and reconnects). Each user joins room `user:<id>`.

Server -> client events (all payloads include `origin`, the `X-Client-Id` of the request that caused it, or null):
`thread:upsert {thread, origin}`, `thread:delete {id, origin}`, `space:upsert {space, origin}`, `space:delete {id, origin}`,
`activity:new {activity}`, `reminder:due {threadId, reminderId, title, at}`.
Clients ignore events whose `origin` equals their own client id. Client -> server: none (only Socket.IO ping).

## 4. Reminders (the "timely notifications" feature)

Two independent layers so a reminder is never missed:

1. **On-device scheduling (primary, works offline and with the app closed).** After every sync/realtime change
   the app cancels and re-schedules one local notification per reminder where `sentAt == null`, `at` is in the future
   and the thread is not done/deleted, using `flutter_local_notifications` `zonedSchedule` (exact alarm,
   `AndroidScheduleMode.exactAllowWhileIdle`). Notification id = positive 31-bit hash of the reminder id. Payload =
   thread id; tapping opens that thread. A daily digest notification (default 09:00 local, user configurable or off)
   is scheduled with `matchDateTimeComponents: DateTimeComponents.time`.
   Also schedule a heads-up for a thread's `dueAt` itself when it has no reminders (title "Due now").
2. **Server scheduler + push (secondary, cross-device).** Every `REMINDER_TICK_MS` (default 15000) the server claims due
   reminders atomically (`updateOne` with `$elemMatch` + positional `$set` of `sentAt`, count modified === 1), then writes an
   Activity, emits `reminder:due` to the user's room, and sends an FCM message to the user's devices if
   `FCM_SERVICE_ACCOUNT_JSON` is configured (otherwise logs once and skips). Invalid FCM tokens are deleted.
   Works across several API instances because of the atomic claim.

## 5. Flutter app architecture (package `spider_mind`)

State management: `provider` (ChangeNotifier). HTTP: `http`. Realtime: `socket_io_client`. Storage: `shared_preferences`
for cache + outbox + settings, `flutter_secure_storage` for tokens. Offline-first: the UI reads from the in-memory store
that is hydrated from the cache; writes apply locally at once (optimistic) and go to an outbox that is flushed
(PUT/DELETE, in order, with retry and backoff) when online. Pull sync = `GET /threads?since=`; live updates from Socket.IO.
Conflicts: last-writer-wins by `updatedAt` (server answers `applied:false` with the stored copy, which the app adopts).

Config: `--dart-define=API_BASE_URL=...` (default `http://10.0.2.2:4000` on Android emulator, `http://localhost:4000` elsewhere);
a Settings field can override the server URL.

Pinned dependencies (use exactly these constraints in `pubspec.yaml`): `provider: ^6.1.2`, `http: ^1.2.2`,
`socket_io_client: ^2.0.3+1`, `shared_preferences: ^2.3.2`, `flutter_secure_storage: ^9.2.2`,
`flutter_local_notifications: 17.2.4`, `timezone: ^0.9.4`, `flutter_timezone: ^2.1.0`, `intl: ^0.19.0`,
`firebase_core: ^3.6.0`, `firebase_messaging: ^15.1.3`, `url_launcher: ^6.3.0`. Dev: `flutter_lints: ^4.0.0`, `flutter_test` (sdk).
SDK: `sdk: ">=3.4.0 <4.0.0"`, Flutter >= 3.22. Material 3. Do NOT add other packages and do NOT add fonts or image assets.
Do not use any API that was removed in Flutter 3.22+.

FCM is optional and gated by `--dart-define=ENABLE_FCM=true`; when off, no Firebase code runs.

## 6. The structured 3D web (the signature feature)

Rendered by our own perspective engine in pure Dart (`CustomPainter`), no plugins. The web has real structure:

* **Spokes = spaces.** Space i of S sits at angle `-pi/2 + 2*pi*i/S` (first space points up). Spoke and label use the space colour.
* **Rings = urgency** (`bandOf` in `app/lib/models/urgency.dart`): inner ring NOW, then THIS WEEK, THIS MONTH, LATER, DONE (done is
  hidden unless `showDone`). Ring radius grows with the number of rows needed so nodes never overlap.
* **Depth (z) = priority**: high is nearer the camera, low is farther. `z = (priority.index - 1) * 0.8`.
* **Cell layout**: threads in the same (space, ring) cell are sorted by priority (high first), due date, creation, and packed in
  rows of 3 along the wedge; further rows move outward. Layout is deterministic (no randomness) so the web is stable between runs.
* **Threads (strands)** between nodes come from `buildWebEdges`: explicit links are solid, bright, curved silk; keyword links are thin, dotted.
* **Visual distinction** (must be explained by a legend):
  colour = space; shape = type (task circle, idea diamond, question hexagon, goal five-point star, larger);
  fill = status (todo outlined ring with faint fill, doing solid with a rotating progress arc, done dim filled with a tick);
  size + depth = priority; overdue = pulsing red halo; progress arc from checklist; selected = white double ring;
  live update from another device = expanding ripple (`flashIds`).
* **Camera**: orbit (yaw/pitch), dolly zoom, pan; a default overview tilt around 50 degrees; "fit" frames the whole web with margin
  so zooming out stays clear (labels thin out with level-of-detail, only important ones remain). Smooth easing, double tap = fit,
  mouse wheel / pinch zoom, one finger orbit, two fingers pan + zoom. Tap selects the nearest node within 28 px.
* **Clarity rules**: labels collision-avoided; far nodes fade by depth fog; selected thread's strands highlight and animated
  particles flow along them; everything else dims to 35%. Respect `reduceMotion` (no pulses/particles, instant camera moves).
  `lowGraphics` disables blur/glow/particles.

Files owned by the 3D module, all under `app/lib/features/web3d/` (plus tests): `web_layout.dart`, `web_camera.dart`,
`web_painter.dart`, `web_view_3d.dart`, `web_legend.dart`. Already written by the architect: `web_edges.dart`.

Public API the rest of the app relies on (names and signatures are fixed):

```dart
// web_view_3d.dart
class WebController extends ChangeNotifier {
  void fit();                 // frame the whole web
  void resetView();           // default tilt + fit
  void focusOn(String threadId);
  void zoomBy(double factor); // >1 zooms in
}
class WebView3D extends StatefulWidget {
  const WebView3D({
    super.key,
    required this.threads,        // List<Thread>
    required this.spaces,         // List<Space>
    required this.controller,     // WebController
    required this.onSelect,       // void Function(String? threadId)
    this.selectedId,              // String?
    this.flashIds = const <String>{},
    this.showDone = false,
    this.hiddenSpaceIds = const <String>{},
    this.highlightKeyword,        // String? dim everything that lacks this keyword
    this.reduceMotion = false,
    this.lowGraphics = false,
  });
}
// web_legend.dart
Future<void> showWebLegend(BuildContext context); // modal bottom sheet explaining every encoding
```
`WebView3D` fills its parent (use `LayoutBuilder`), draws its own background (theme aware: near-black in dark theme, soft
blue-grey in light), and calls `onSelect(null)` when the empty background is tapped.

## 7. Flutter screens (clean, understandable, not complex)

Bottom navigation with 4 tabs and one floating "New thread" button:
1. **Web** (default): the 3D web full-bleed; top: space filter chips (tap toggles a space, colour dot), search icon (keyword highlight),
   legend (i) and recenter buttons; a live-status pill (LIVE / OFFLINE n pending / SYNCING); bottom: selected-thread card with quick actions
   (Start, Done, Open). Empty state invites the first thread.
2. **Threads**: grouped list (Overdue, Today, This week, Later, No date, Done) with search, type/status filters, swipe to complete/delete (with undo), tap to open.
3. **Insights**: counts, streak, 14-day completion bars (custom painter), by-space split, **Next move** (ranked open tasks with a reason),
   **Hub** (most connected thread), **Loose ends** (threads with no strands), live activity timeline.
4. **Settings**: account, appearance (system/light/dark), reminders (permission status, exact-alarm status, daily digest time, send test notification),
   graphics (reduce motion, low graphics), spaces manager (add/rename/recolour/reorder/delete with move), server URL, export JSON, sign out, delete account.
Plus: auth screen (login/register), thread editor/detail (full-screen route: title, notes, type, status, priority, space, due date+time,
reminders with quick presets "at due time / 1 hour / 1 day before" and custom, checklist, tags + auto keywords, linked threads picker, per-thread activity, delete).

Design language: dark-first, brand colours crimson `#FF2A44`, electric blue `#32B4FF`, midnight `#03040A`/`#0B0F1E` surfaces; light theme with the same accents.
Generous spacing, 48px touch targets, clear hierarchy, sentence-case copy, no jargon. Accessible: semantic labels, contrast, text scaling safe,
a full non-3D path (Threads tab) so everything works without the web view.

Next-move score for an open task: `deg*3` (+`100 + overdueDays` if overdue, `+40 - 5*daysLeft` if due in <= 3 days, `+max(0,10 - 0.5*daysLeft)` otherwise with a due date, `+8` for high priority, `+3` for doing).
Hub = open thread with the highest degree (>= 2). Loose = open threads with degree 0.

## 8. Repo layout

```
spider-mind/
  README.md  docker-compose.yml  .github/workflows/{server.yml,app.yml}  docs/{CONTRACT.md,API.md,ARCHITECTURE.md,DEPLOYMENT.md}
  server/   (Node.js)  package.json .env.example Dockerfile src/** test/**
  app/      (Flutter)  pubspec.yaml analysis_options.yaml lib/** test/** tool/configure_android.sh tool/configure_ios.md
```
