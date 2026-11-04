import { randomUUID } from 'node:crypto';
import { ZodError } from 'zod';
import { AppError, badRequest, unauthorized } from '../utils/errors.js';
import { verifyAccessToken } from '../services/tokens.js';
import { User } from '../models/index.js';

/** Request id, X-Client-Id and a one-line JSON access log. */
export function requestContext(logger) {
  return (req, res, next) => {
    const incoming = req.get('x-request-id');
    req.id = incoming && /^[\w.-]{8,64}$/.test(incoming) ? incoming : randomUUID();
    const client = req.get('x-client-id')?.trim();
    req.clientId = client && client.length <= 128 ? client : null;
    res.setHeader('X-Request-Id', req.id);
    const started = process.hrtime.bigint();
    res.on('finish', () => {
      logger.info('http', {
        reqId: req.id,
        method: req.method,
        path: req.originalUrl.split('?')[0],
        status: res.statusCode,
        ms: Number(process.hrtime.bigint() - started) / 1e6,
        userId: req.user?.id,
      });
    });
    next();
  };
}

/** Parses and replaces req.body / req.query / req.params with zod output. */
export const validate = (schemas) => (req, _res, next) => {
  try {
    for (const part of ['params', 'query', 'body']) {
      if (schemas[part]) req[part] = schemas[part].parse(req[part] ?? {});
    }
    next();
  } catch (err) {
    next(err);
  }
};

export const asyncHandler = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

export function authenticate(config) {
  return asyncHandler(async (req, _res, next) => {
    const header = req.get('authorization') ?? '';
    const m = /^Bearer\s+(.+)$/i.exec(header);
    if (!m) throw unauthorized();
    const userId = verifyAccessToken(config, m[1]);
    const user = await User.findById(userId).select('email name timezone').lean();
    if (!user) throw unauthorized('Account no longer exists');
    req.user = { id: String(user._id), email: user.email, name: user.name, timezone: user.timezone };
    next();
  });
}

export function notFoundHandler(req, _res, next) {
  next(new AppError(404, 'NOT_FOUND', `No route for ${req.method} ${req.path}`));
}

export function errorHandler(logger) {
  // eslint-disable-next-line no-unused-vars
  return (err, req, res, _next) => {
    let status = 500;
    let code = 'INTERNAL';
    let message = 'Internal server error';
    let details;
    if (err instanceof AppError) {
      ({ status, code, message, details } = err);
    } else if (err instanceof ZodError) {
      const e = badRequest('Validation failed');
      status = e.status;
      code = e.code;
      message = e.message;
      details = err.issues.map((i) => ({ path: i.path.join('.'), message: i.message }));
    } else if (err?.type === 'entity.too.large') {
      status = 400;
      code = 'VALIDATION';
      message = 'Request body too large';
    } else if (err?.type === 'entity.parse.failed' || err instanceof SyntaxError) {
      status = 400;
      code = 'VALIDATION';
      message = 'Malformed JSON body';
    } else if (err?.name === 'CastError') {
      status = 400;
      code = 'VALIDATION';
      message = 'Invalid identifier';
    } else if (err?.code === 11000) {
      status = 409;
      code = 'CONFLICT';
      message = 'Resource already exists';
    }
    if (status >= 500) logger.error('unhandled error', { reqId: req.id, err });
    res.status(status).json({ error: { code, message, ...(details ? { details } : {}) } });
  };
}
