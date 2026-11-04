# Architecture

* **Data flow**: UI -> `AppState` (optimistic write, persisted to SharedPreferences) -> ordered outbox -> REST `PUT/DELETE` -> server -> Socket.IO event to other devices -> `AppState` merge (last writer wins by `updatedAt`).
* **Pull sync**: `GET /threads?since=<cursor>` on start, reconnect and pull-to-refresh; tombstones for deletes.
* **Reminders**: `planNotifications` (pure) -> `NotificationService.apply` cancels and reschedules all local notifications after every change. Server scheduler is a second layer.
* **3D web**: `WebLayout` (deterministic polar layout) -> `WebCamera` (own perspective projection) -> `WebPainter` (CustomPainter), `WebView3D` handles gestures and animation ticker.
* **Auth**: 15 min access JWT, rotating 30 day refresh token with reuse detection; tokens in the platform keystore.
See CONTRACT.md for the full API.
