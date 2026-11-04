import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { authenticate, errorHandler, notFoundHandler, requestContext } from './middleware/common.js';
import { authRouter } from './routes/auth.js';
import { dataRouter } from './routes/data.js';
import { healthRouter } from './routes/health.js';
import { createActivityService } from './services/activity.js';
import { createSpaceService } from './services/spaces.js';
import { createThreadService } from './services/threads.js';
import { createEmailService } from './services/email.js';

function limiter(config, max) {
  return rateLimit({
    windowMs: config.rateLimit.windowMs,
    limit: max,
    standardHeaders: true,
    legacyHeaders: false,
    handler: (_req, res) =>
      res.status(429).json({ error: { code: 'RATE_LIMITED', message: 'Too many requests, slow down' } }),
  });
}

/** Builds the Express app. `hub` is the realtime hub (emit-only from here). */
export function createApp({ config, logger, hub }) {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', config.trustProxy);

  const allowAll = config.corsOrigins.includes('*');
  app.use(requestContext(logger));
  app.use(
    helmet({
      contentSecurityPolicy: false,
      crossOriginEmbedderPolicy: false,
    })
  );
  app.use(
    cors({
      origin: allowAll ? true : config.corsOrigins,
      allowedHeaders: ['Authorization', 'Content-Type', 'X-Client-Id', 'X-Request-Id'],
      exposedHeaders: ['X-Request-Id'],
      maxAge: 600,
    }),
  );

  // Health endpoints sit before the limiter so probes never get throttled.
  const health = healthRouter();
  app.use(health);
  app.use('/api/v1', health);

  app.use(limiter(config, config.rateLimit.globalMax));
  app.use(express.json({ limit: config.bodyLimit }));

  const publicDir = fileURLToPath(new URL('../public', import.meta.url));
  app.use(express.static(publicDir));

  const activity = createActivityService({ hub });
  const email = createEmailService({ config, logger });
  const services = {
    config,
    hub,
    activity,
    email,
    spaces: createSpaceService({ hub }),
    threads: createThreadService({ hub, activity }),
  };

  const api = express.Router();
  api.use('/auth', limiter(config, config.rateLimit.authMax));
  api.use(authRouter(services)); // public auth routes + /me (self-authenticating)
  api.use(authenticate(config));
  api.use(dataRouter(services));
  app.use('/api/v1', api);

  app.get('*', (req, res, next) => {
    if (req.path.startsWith('/api') || req.path.startsWith('/socket.io')) {
      return next();
    }
    res.sendFile(path.join(publicDir, 'index.html'), (err) => {
      if (err) next();
    });
  });

  app.use(notFoundHandler);
  app.use(errorHandler(logger));
  return app;
}
