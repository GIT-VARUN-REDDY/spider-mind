import test from 'node:test';
import assert from 'node:assert/strict';
import { verifyGoogleToken } from '../../src/services/googleAuth.js';
import { loadConfig } from '../../src/config.js';

test('config: googleClientId parses from environment or defaults to null', () => {
  const withoutGoogle = loadConfig({});
  assert.equal(withoutGoogle.googleClientId, null);

  const withGoogle = loadConfig({ GOOGLE_CLIENT_ID: 'test-client-id.apps.googleusercontent.com' });
  assert.equal(withGoogle.googleClientId, 'test-client-id.apps.googleusercontent.com');
});

test('verifyGoogleToken: returns null for invalid or empty inputs', async () => {
  assert.equal(await verifyGoogleToken(null), null);
  assert.equal(await verifyGoogleToken(''), null);
  assert.equal(await verifyGoogleToken('   '), null);
  assert.equal(await verifyGoogleToken('not-a-valid-token'), null);
});

test('verifyGoogleToken: verifies valid Google ID token via tokeninfo', async () => {
  const originalFetch = global.fetch;
  try {
    const fakeIdToken = 'header.payload.signature';
    const clientId = '493865528762-6g4edvbovdsmaai2q14rtfccv4icase5.apps.googleusercontent.com';

    global.fetch = async (url) => {
      if (url.includes('id_token=')) {
        return {
          ok: true,
          status: 200,
          json: async () => ({
            iss: 'https://accounts.google.com',
            email: 'spidey@example.com',
            email_verified: 'true',
            aud: clientId,
            sub: 'google-sub-12345',
            name: 'Peter Parker',
            picture: 'https://lh3.googleusercontent.com/avatar123',
            exp: Math.floor(Date.now() / 1000) + 3600,
          }),
        };
      }
      return { ok: false, status: 404, json: async () => ({}) };
    };

    const res = await verifyGoogleToken(fakeIdToken, clientId);
    assert.deepEqual(res, {
      email: 'spidey@example.com',
      name: 'Peter Parker',
      sub: 'google-sub-12345',
      picture: 'https://lh3.googleusercontent.com/avatar123',
    });

    // Mismatched client ID rejected
    const badClientRes = await verifyGoogleToken(fakeIdToken, 'other-client-id');
    assert.equal(badClientRes, null);
  } finally {
    global.fetch = originalFetch;
  }
});

test('verifyGoogleToken: verifies valid Google access token via tokeninfo + userinfo', async () => {
  const originalFetch = global.fetch;
  try {
    const fakeAccessToken = 'ya29.fake-access-token';
    const clientId = '493865528762-6g4edvbovdsmaai2q14rtfccv4icase5.apps.googleusercontent.com';

    global.fetch = async (url) => {
      if (url.includes('access_token=')) {
        return {
          ok: true,
          status: 200,
          json: async () => ({
            aud: clientId,
            sub: 'google-sub-access-999',
            expires_in: 3600,
          }),
        };
      }
      if (url.includes('userinfo')) {
        return {
          ok: true,
          status: 200,
          json: async () => ({
            sub: 'google-sub-access-999',
            email: 'miles@example.com',
            email_verified: 'true',
            name: 'Miles Morales',
            picture: 'https://lh3.googleusercontent.com/miles',
          }),
        };
      }
      return { ok: false, status: 404, json: async () => ({}) };
    };

    const res = await verifyGoogleToken(fakeAccessToken, clientId);
    assert.deepEqual(res, {
      email: 'miles@example.com',
      name: 'Miles Morales',
      sub: 'google-sub-access-999',
      picture: 'https://lh3.googleusercontent.com/miles',
    });
  } finally {
    global.fetch = originalFetch;
  }
});
