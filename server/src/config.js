import { z } from 'zod';

const DEV_ACCESS_SECRET = 'dev-only-access-secret-do-not-use-in-production';
const DEV_REFRESH_SECRET = 'dev-only-refresh-secret-do-not-use-in-production';

const bool = (def) =>
  z
    .string()
    .optional()
    .transform((v) => {
      if (v === undefined || v === '') return def;
      return ['1', 'true', 'yes', 'on'].includes(v.toLowerCase());
    });

const int = (def, min, max) =>
  z
    .string()
    .optional()
    .transform((v) => (v === undefined || v === '' ? def : Number(v)))
    .pipe(z.number().int().min(min).max(max));

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: int(4000, 0, 65535),
  HOST: z.string().default('0.0.0.0'),
  MONGODB_URI: z.string().optional(),
  JWT_ACCESS_SECRET: z.string().optional(),
  JWT_REFRESH_SECRET: z.string().optional(),
  BCRYPT_COST: int(12, 4, 15),
  CORS_ORIGINS: z.string().optional(),
  TRUST_PROXY: z.string().optional(),
  RATE_LIMIT_WINDOW_MS: int(60_000, 100, 3_600_000),
  RATE_LIMIT_GLOBAL_MAX: int(300, 1, 1_000_000),
  RATE_LIMIT_AUTH_MAX: int(20, 1, 1_000_000),
  BODY_LIMIT: z.string().default('256kb'),
  REMINDER_SCHEDULER_ENABLED: bool(true),
  REMINDER_TICK_MS: int(15_000, 50, 3_600_000),
  REMINDER_CATCHUP_HOURS: int(24, 1, 720),
  FCM_SERVICE_ACCOUNT_JSON: z.string().optional(),
  LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error', 'silent']).optional(),
  SHUTDOWN_TIMEOUT_MS: int(10_000, 100, 120_000),
  GOOGLE_CLIENT_ID: z.string().optional(),
  BREVO_API_KEY: z.string().optional(),
  FROM_EMAIL: z.string().optional(),
  FROM_NAME: z.string().optional(),
});

/** Turns the TRUST_PROXY string into what Express' `trust proxy` setting accepts. */
export function parseTrustProxy(v) {
  if (v === undefined || v === '') return false;
  const s = v.trim().toLowerCase();
  if (s === 'false' || s === '0' || s === 'no') return false;
  if (s === 'true' || s === 'yes') return true;
  if (/^\d+$/.test(s)) return Number(s);
  return v.trim(); // "loopback", CIDR list, ...
}

export function parseOrigins(v) {
  return (v ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

export class ConfigError extends Error {
  constructor(problems) {
    super(`Invalid configuration:\n - ${problems.join('\n - ')}`);
    this.name = 'ConfigError';
    this.problems = problems;
  }
}

/** Validates the environment. Pure: pass any env object. Throws ConfigError. */
export function loadConfig(env = process.env) {
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    throw new ConfigError(parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`));
  }
  const e = parsed.data;
  const isProd = e.NODE_ENV === 'production';
  const problems = [];

  const corsOrigins = e.CORS_ORIGINS === undefined ? (isProd ? [] : ['*']) : parseOrigins(e.CORS_ORIGINS);
  if (isProd) {
    for (const name of ['JWT_ACCESS_SECRET', 'JWT_REFRESH_SECRET']) {
      const v = e[name];
      if (!v) problems.push(`${name} is required in production`);
      else if (v.length < 32) problems.push(`${name} must be at least 32 characters in production`);
    }
    if (e.JWT_ACCESS_SECRET && e.JWT_ACCESS_SECRET === e.JWT_REFRESH_SECRET) {
      problems.push('JWT_ACCESS_SECRET and JWT_REFRESH_SECRET must differ');
    }
    if (!e.MONGODB_URI) problems.push('MONGODB_URI is required in production');
    if (corsOrigins.includes('*')) problems.push('CORS_ORIGINS must not contain "*" in production');
    if (e.BCRYPT_COST < 10) problems.push('BCRYPT_COST must be >= 10 in production');
  }
  if (problems.length) throw new ConfigError(problems);

  return Object.freeze({
    env: e.NODE_ENV,
    isProd,
    port: e.PORT,
    host: e.HOST,
    mongoUri: e.MONGODB_URI ?? 'mongodb://127.0.0.1:27017/spidermind',
    jwtAccessSecret: e.JWT_ACCESS_SECRET ?? DEV_ACCESS_SECRET,
    jwtRefreshSecret: e.JWT_REFRESH_SECRET ?? DEV_REFRESH_SECRET,
    usingDevSecrets: !e.JWT_ACCESS_SECRET || !e.JWT_REFRESH_SECRET,
    bcryptCost: e.BCRYPT_COST,
    corsOrigins,
    trustProxy: parseTrustProxy(e.TRUST_PROXY),
    rateLimit: {
      windowMs: e.RATE_LIMIT_WINDOW_MS,
      globalMax: e.RATE_LIMIT_GLOBAL_MAX,
      authMax: e.RATE_LIMIT_AUTH_MAX,
    },
    bodyLimit: e.BODY_LIMIT,
    reminders: {
      enabled: e.REMINDER_SCHEDULER_ENABLED,
      tickMs: e.REMINDER_TICK_MS,
      catchupMs: e.REMINDER_CATCHUP_HOURS * 3_600_000,
    },
    fcmServiceAccount: e.FCM_SERVICE_ACCOUNT_JSON || null,
    logLevel: e.LOG_LEVEL ?? (e.NODE_ENV === 'test' ? 'silent' : 'info'),
    shutdownTimeoutMs: e.SHUTDOWN_TIMEOUT_MS,
    googleClientId: e.GOOGLE_CLIENT_ID || null,
    email: {
      brevoApiKey: e.BREVO_API_KEY || null,
      fromEmail: e.FROM_EMAIL || null,
      fromName: e.FROM_NAME || 'Spider Mind',
      enabled: Boolean(e.BREVO_API_KEY && e.FROM_EMAIL),
    },
  });
}

export const ACCESS_TOKEN_TTL_SECONDS = 900;
export const REFRESH_TOKEN_TTL_SECONDS = 30 * 24 * 3600;
