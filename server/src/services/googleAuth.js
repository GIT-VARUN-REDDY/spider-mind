const GOOGLE_ISSUERS = ['accounts.google.com', 'https://accounts.google.com'];

async function gget(url, opts = {}) {
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(10000), ...opts });
    const d = await res.json().catch(() => ({}));
    return { ok: res.ok, status: res.status, d };
  } catch {
    return { ok: false, status: 500, d: {} };
  }
}

/**
 * Validates a Google ID token or OAuth access token with Google's servers.
 * Verifies issuer, expiration, email verification, and audience against the configured client ID.
 * Returns { email, name, sub, picture } or null.
 */
export async function verifyGoogleToken(token, configuredClientId) {
  if (typeof token !== 'string' || !token.trim()) return null;
  const raw = token.trim();
  const enc = encodeURIComponent(raw);

  // 1. Check if token is a Google JWT (ID token)
  if (raw.split('.').length === 3) {
    const { ok, d } = await gget(`https://oauth2.googleapis.com/tokeninfo?id_token=${enc}`);
    if (
      ok &&
      d.email &&
      GOOGLE_ISSUERS.includes(d.iss) &&
      String(d.email_verified) === 'true' &&
      Number(d.exp) * 1000 > Date.now()
    ) {
      if (!configuredClientId || d.aud === configuredClientId || d.azp === configuredClientId) {
        return {
          email: d.email,
          name: d.name || d.email.split('@')[0],
          sub: d.sub,
          picture: d.picture || null,
        };
      }
    }
  }

  // 2. Check if token is a Google OAuth access token
  const t = await gget(`https://oauth2.googleapis.com/tokeninfo?access_token=${enc}`);
  if (t.ok && Number(t.d?.expires_in) > 0) {
    if (!configuredClientId || t.d.aud === configuredClientId || t.d.azp === configuredClientId) {
      const u = await gget('https://www.googleapis.com/oauth2/v3/userinfo', {
        headers: { Authorization: `Bearer ${raw}` },
      });
      const sub = t.d.sub || t.d.user_id;
      if (u.ok && u.d?.email && String(u.d.email_verified) === 'true' && (!sub || u.d.sub === sub)) {
        return {
          email: u.d.email,
          name: u.d.name || u.d.email.split('@')[0],
          sub: u.d.sub,
          picture: u.d.picture || null,
        };
      }
    }
  }

  return null;
}
