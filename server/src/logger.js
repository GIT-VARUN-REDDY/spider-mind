const LEVELS = { debug: 10, info: 20, warn: 30, error: 40, silent: 100 };

/** Minimal structured logger: one JSON object per line on stdout/stderr. */
export function createLogger(level = 'info', bindings = {}) {
  const min = LEVELS[level] ?? LEVELS.info;
  const write = (lvl, msg, fields) => {
    if (LEVELS[lvl] < min) return;
    const line = JSON.stringify({ ts: new Date().toISOString(), level: lvl, msg, ...bindings, ...fields }, (k, v) =>
      v instanceof Error ? { name: v.name, message: v.message, stack: v.stack } : v,
    );
    (LEVELS[lvl] >= LEVELS.warn ? process.stderr : process.stdout).write(line + '\n');
  };
  return {
    debug: (msg, f) => write('debug', msg, f),
    info: (msg, f) => write('info', msg, f),
    warn: (msg, f) => write('warn', msg, f),
    error: (msg, f) => write('error', msg, f),
    child: (more) => createLogger(level, { ...bindings, ...more }),
  };
}
