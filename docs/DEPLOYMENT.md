# Deployment

1. Get a Linux host with Docker, point a domain at it, and put a TLS proxy (Caddy or nginx) in front of port 4000. WebSocket upgrade must be allowed for `/socket.io`.
2. `cp .env.example .env`, set `JWT_ACCESS_SECRET` and `JWT_REFRESH_SECRET` (different, 32+ chars), `TRUST_PROXY=true` behind a proxy, and `CORS_ORIGINS` if you serve a web client.
3. `docker compose up -d --build`. Check `GET /api/v1/readyz`.
4. MongoDB: for production use a managed cluster (Atlas) and set `MONGODB_URI` instead of the bundled container; back it up.
5. Scale: several API replicas are safe, reminders are claimed atomically. Use a Socket.IO adapter (Redis) if you run more than one replica and need cross-replica realtime.
6. Build the app with `--dart-define=API_URL=https://api.yourdomain.com` and remove `usesCleartextTraffic` from the Android manifest.
