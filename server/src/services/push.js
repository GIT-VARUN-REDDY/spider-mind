import { Device } from '../models/index.js';

/** Accepts raw JSON or base64-encoded JSON. Returns the object or throws. */
export function parseServiceAccount(raw) {
  const text = raw.trim();
  const json = text.startsWith('{') ? text : Buffer.from(text, 'base64').toString('utf8');
  const obj = JSON.parse(json);
  if (!obj || typeof obj !== 'object' || !obj.project_id) throw new Error('service account JSON has no project_id');
  return obj;
}

const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

/**
 * FCM sender. `loadMessaging` is injectable for tests; by default firebase-admin is
 * imported lazily so the server runs fine without it when push is not configured.
 */
export function createPushSender({ serviceAccountRaw, logger, loadMessaging = defaultLoader }) {
  let messagingPromise = null;
  let warned = false;
  const warnOnce = (msg, f) => {
    if (!warned) logger.warn(msg, f);
    warned = true;
  };

  const getMessaging = () => {
    if (!messagingPromise) messagingPromise = loadMessaging(parseServiceAccount(serviceAccountRaw));
    return messagingPromise;
  };

  return {
    enabled: Boolean(serviceAccountRaw),
    async sendToUser(userId, { title, body, data }) {
      if (!serviceAccountRaw) {
        warnOnce('FCM_SERVICE_ACCOUNT_JSON not set: push notifications are disabled');
        return { sent: 0, removed: 0 };
      }
      const devices = await Device.find({ userId }).select('token').lean();
      if (!devices.length) return { sent: 0, removed: 0 };
      let messaging;
      try {
        messaging = await getMessaging();
      } catch (err) {
        messagingPromise = null;
        warnOnce('push disabled: could not initialise firebase-admin', { err });
        return { sent: 0, removed: 0 };
      }
      const tokens = devices.map((d) => d.token);
      const res = await messaging.sendEachForMulticast({
        tokens,
        notification: { title, body },
        data,
        android: { priority: 'high' },
        apns: { headers: { 'apns-priority': '10' } },
      });
      const dead = [];
      res.responses.forEach((r, i) => {
        if (!r.success && DEAD_TOKEN_CODES.has(r.error?.code)) dead.push(tokens[i]);
      });
      if (dead.length) await Device.deleteMany({ token: { $in: dead } });
      return { sent: res.successCount, removed: dead.length };
    },
  };
}

async function defaultLoader(account) {
  const admin = (await import('firebase-admin')).default ?? (await import('firebase-admin'));
  const app = admin.apps?.length ? admin.app() : admin.initializeApp({ credential: admin.credential.cert(account) });
  return admin.messaging(app);
}
