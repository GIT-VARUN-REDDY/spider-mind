import test from 'node:test';
import assert from 'node:assert/strict';
import { createPushSender } from '../../src/services/push.js';
import { createLogger } from '../../src/logger.js';

test('push without a service account is a logged no-op', async () => {
  const p = createPushSender({ serviceAccountRaw: null, logger: createLogger('silent') });
  assert.equal(p.enabled, false);
  assert.deepEqual(await p.sendToUser('u', { title: 't', body: 'b', data: {} }), { sent: 0, removed: 0 });
});
