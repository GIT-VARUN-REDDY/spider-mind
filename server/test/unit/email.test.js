import test from 'node:test';
import assert from 'node:assert/strict';
import { createEmailService } from '../../src/services/email.js';

test('createEmailService: disabled when unconfigured', async () => {
  const service = createEmailService({ config: { email: { enabled: false } } });
  assert.equal(service.isConfigured, false);

  const res = await service.sendEmail({ to: 'spidey@example.com', subject: 'Test' });
  assert.deepEqual(res, { simulated: true, sent: false });
});

test('createEmailService: successfully formats and sends welcome email', async () => {
  const originalFetch = global.fetch;
  let sentPayload = null;
  let sentHeaders = null;

  try {
    global.fetch = async (url, opts) => {
      if (url.includes('api.brevo.com')) {
        sentPayload = JSON.parse(opts.body);
        sentHeaders = opts.headers;
        return {
          ok: true,
          status: 201,
          json: async () => ({ messageId: '<brevo-mock-msg-123@smtp-relay.mailin.fr>' }),
        };
      }
      return { ok: false, status: 404, json: async () => ({}) };
    };

    const service = createEmailService({
      config: {
        email: {
          brevoApiKey: 'test-api-key',
          fromEmail: 'noreply@spidermind.app',
          fromName: 'Spider Mind',
          enabled: true,
        },
      },
    });

    assert.equal(service.isConfigured, true);

    const res = await service.sendWelcomeEmail({ email: 'peter@example.com', name: 'Peter Parker' });
    assert.equal(res.sent, true);
    assert.equal(res.messageId, '<brevo-mock-msg-123@smtp-relay.mailin.fr>');

    assert.equal(sentHeaders['api-key'], 'test-api-key');
    assert.deepEqual(sentPayload.sender, { name: 'Spider Mind', email: 'noreply@spidermind.app' });
    assert.deepEqual(sentPayload.to, [{ email: 'peter@example.com' }]);
    assert.ok(sentPayload.subject.includes('Welcome to Spider Mind'));
    assert.ok(sentPayload.htmlContent.includes('Project Spider'));
  } finally {
    global.fetch = originalFetch;
  }
});

test('createEmailService: handles Brevo API errors gracefully', async () => {
  const originalFetch = global.fetch;
  try {
    global.fetch = async () => ({
      ok: false,
      status: 401,
      json: async () => ({ code: 'unauthorized', message: 'Key not found' }),
    });

    const service = createEmailService({
      config: {
        email: {
          brevoApiKey: 'bad-key',
          fromEmail: 'noreply@spidermind.app',
          enabled: true,
        },
      },
    });

    const res = await service.sendEmail({ to: 'peter@example.com', subject: 'Error test' });
    assert.equal(res.sent, false);
    assert.equal(res.status, 401);
  } finally {
    global.fetch = originalFetch;
  }
});
