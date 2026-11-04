import http from 'node:http';
import { fileURLToPath } from 'node:url';
import { loadConfig } from './config.js';
import { createLogger } from './logger.js';
import { connectDb, disconnectDb } from './db.js';
import { createApp } from './app.js';
import { createRealtimeHub } from './realtime/index.js';
import { createPushSender } from './services/push.js';
import { createReminderScheduler } from './services/reminders.js';

/**
 * Boots everything. `env` overrides process.env (used by tests); the returned
 * `stop()` shuts down in order: scheduler, sockets/HTTP, Mongo.
 */
export async function startServer({ env = process.env, config = loadConfig(env), logger } = {}) {
  const log = logger ?? createLogger(config.logLevel);
  if (config.usingDevSecrets) log.warn('using built-in development JWT secrets');

  await connectDb(config.mongoUri, log);
  const hub = createRealtimeHub({ config, logger: log });
  const app = createApp({ config, logger: log, hub });
  const server = http.createServer(app);
  hub.attach(server);

  const push = createPushSender({ serviceAccountRaw: config.fcmServiceAccount, logger: log });
  if (!push.enabled) log.info('FCM_SERVICE_ACCOUNT_JSON not set: server push disabled (on-device reminders still work)');
  const reminders = createReminderScheduler({ config, logger: log, hub, push });

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(config.port, config.host, resolve);
  });
  const { port } = server.address();
  if (config.reminders.enabled) reminders.start();
  log.info('server listening', { port, env: config.env });

  let stopping = null;
  const stop = () =>
    (stopping ??= (async () => {
      await reminders.stop();
      const closed = new Promise((resolve) => server.close(resolve));
      server.closeIdleConnections?.();
      await hub.close();
      await Promise.race([closed, new Promise((r) => setTimeout(r, config.shutdownTimeoutMs).unref())]);
      server.closeAllConnections?.();
      await disconnectDb();
      log.info('server stopped');
    })());

  return { app, server, hub, reminders, config, port, url: `http://127.0.0.1:${port}`, stop };
}

export { createApp };

import { existsSync } from 'node:fs';

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain) {
  try {
    if (typeof process.loadEnvFile === 'function' && existsSync('.env')) {
      process.loadEnvFile('.env');
    }
    const s = await startServer();
    for (const sig of ['SIGTERM', 'SIGINT']) {
      process.once(sig, () => {
        s.stop().then(() => process.exit(0), () => process.exit(1));
      });
    }
  } catch (err) {
    process.stderr.write(`${err.message ?? err}\n`);
    process.exit(1);
  }
}
