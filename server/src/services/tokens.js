import { createHash, randomUUID } from 'node:crypto';
import jwt from 'jsonwebtoken';
import { ACCESS_TOKEN_TTL_SECONDS, REFRESH_TOKEN_TTL_SECONDS } from '../config.js';
import { RefreshToken } from '../models/index.js';
import { unauthorized } from '../utils/errors.js';

export const sha256 = (s) => createHash('sha256').update(s).digest('hex');

export function signAccessToken(config, userId) {
  return jwt.sign({ sub: userId }, config.jwtAccessSecret, { algorithm: 'HS256', expiresIn: ACCESS_TOKEN_TTL_SECONDS });
}

/** Returns the user id or throws 401. */
export function verifyAccessToken(config, token) {
  try {
    const p = jwt.verify(token, config.jwtAccessSecret, { algorithms: ['HS256'] });
    if (typeof p.sub !== 'string') throw new Error('no sub');
    return p.sub;
  } catch {
    throw unauthorized('Invalid or expired access token');
  }
}

function signRefreshToken(config, userId, familyId) {
  return jwt.sign({ sub: userId, fam: familyId, jti: randomUUID() }, config.jwtRefreshSecret, {
    algorithm: 'HS256',
    expiresIn: REFRESH_TOKEN_TTL_SECONDS,
  });
}

async function storeRefresh(config, userId, familyId) {
  const token = signRefreshToken(config, userId, familyId);
  await RefreshToken.create({
    userId,
    familyId,
    tokenHash: sha256(token),
    expiresAt: new Date(Date.now() + REFRESH_TOKEN_TTL_SECONDS * 1000),
  });
  return token;
}

/** Starts a new refresh family (login/register). */
export async function issueTokens(config, userId) {
  const uid = String(userId);
  const refreshToken = await storeRefresh(config, uid, randomUUID());
  return { accessToken: signAccessToken(config, uid), refreshToken, expiresIn: ACCESS_TOKEN_TTL_SECONDS };
}

/**
 * Rotation: each refresh token works once. Presenting an already-used token
 * means it leaked (or a client raced itself), so the whole family is revoked.
 */
export async function rotateRefreshToken(config, token) {
  let claims;
  try {
    claims = jwt.verify(token, config.jwtRefreshSecret, { algorithms: ['HS256'] });
  } catch {
    throw unauthorized('Invalid or expired refresh token');
  }
  const hash = sha256(token);
  const claimed = await RefreshToken.findOneAndUpdate({ tokenHash: hash, used: false }, { $set: { used: true } }).lean();
  if (!claimed) {
    if (claims.fam) await RefreshToken.deleteMany({ familyId: claims.fam, userId: claims.sub });
    throw unauthorized('Refresh token is no longer valid');
  }
  const userId = String(claimed.userId);
  const refreshToken = await storeRefresh(config, userId, claimed.familyId);
  return { accessToken: signAccessToken(config, userId), refreshToken, expiresIn: ACCESS_TOKEN_TTL_SECONDS, userId };
}

/** Logout: revoke the family of the presented token. Never throws on bad tokens. */
export async function revokeRefreshToken(token) {
  const doc = await RefreshToken.findOne({ tokenHash: sha256(token) }).lean();
  if (doc) await RefreshToken.deleteMany({ familyId: doc.familyId, userId: doc.userId });
}
