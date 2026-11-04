# Project Spider

A task, idea and goal tracker whose home screen is a **structured 3D web**: spokes are your spaces, rings are urgency (Now, This week, This month, Later, Done), depth is priority, shapes are types, and threads between nodes are your links and shared keywords. Everything syncs live across devices and reminds you on time.

* `app/` Flutter app (Android, iOS)
* `server/` Node.js 20 + Express + MongoDB + Socket.IO API (JWT auth, realtime, reminder scheduler)
* `docs/` CONTRACT.md (API and design spec), ARCHITECTURE.md, DEPLOYMENT.md

## Features
* Structured, pannable, zoomable 3D web with legend, depth fog, label thinning, keyword highlight, space filters
* Realtime tracking: changes from other devices ripple on the web; LIVE / OFFLINE / SYNCING status
* Offline-first: edits are saved on the device, queued, and synced with retry
* Timely reminders: scheduled on the device (works offline and when the app is closed), plus a server scheduler (cross-device, optional FCM push), plus a daily digest
* Threads list with swipe to complete or delete (undo), insights (streak, 14-day chart, next move, hub, loose ends), spaces manager, light/dark, reduce motion, JSON export, account deletion

## Run it
```bash
# 1. API + MongoDB
cp .env.example .env     # fill both JWT secrets
docker compose up -d --build
curl localhost:4000/api/v1/healthz

# 2. App
cd app
flutter create --org com.spider --project-name spider_mind --platforms=android,ios .
bash tool/configure_android.sh          # iOS: see tool/configure_ios.md
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:4000    # emulator; use your LAN IP on a phone
```
Release: `flutter build apk --release --dart-define=API_URL=https://api.yourdomain.com`.

## Verified status (be aware)
* **Server**: 26 unit and 23 integration tests pass against a real MongoDB.
* **Flutter pure logic** (layout, camera projection, label LOD, next move, notification planning, outbox, models): analyzer clean, 22 tests pass.
* **Flutter UI, state, plugins** (screens, painter, notifications, sockets): written to the pinned versions but **not compiled or run** in the authoring environment (no Flutter SDK). Expect to fix small compile issues on first `flutter analyze`. CI (`.github/workflows/app.yml`) runs analyze, tests and an APK build.
* Server-side push (FCM) is implemented on the server; the app currently relies on on-device scheduled notifications and does not register an FCM token.
