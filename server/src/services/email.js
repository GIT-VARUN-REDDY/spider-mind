/**
 * Brevo (Sendinblue) transactional email service for Spider Mind.
 * Handles welcome emails, task reminders, and system notifications.
 */
export function createEmailService({ config, logger = console }) {
  const emailConfig = config?.email ?? {};
  const isConfigured = Boolean(emailConfig.brevoApiKey && emailConfig.fromEmail);

  async function sendEmail({ to, subject, htmlContent, textContent }) {
    if (!isConfigured) {
      logger.debug?.('Email disabled or unconfigured, skipping send', { to, subject });
      return { simulated: true, sent: false };
    }

    const payload = {
      sender: {
        name: emailConfig.fromName || 'Spider Mind',
        email: emailConfig.fromEmail,
      },
      to: [
        {
          email: to,
        },
      ],
      subject,
      htmlContent,
      ...(textContent ? { textContent } : {}),
    };

    try {
      const res = await fetch('https://api.brevo.com/v3/smtp/email', {
        method: 'POST',
        headers: {
          accept: 'application/json',
          'content-type': 'application/json',
          'api-key': emailConfig.brevoApiKey,
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(15000),
      });

      const body = await res.json().catch(() => ({}));
      if (res.ok) {
        logger.info?.('Email sent successfully via Brevo', { to, messageId: body.messageId });
        return { sent: true, messageId: body.messageId };
      }

      logger.warn?.(`Brevo email failed with status ${res.status}`, { to, error: body });
      return { sent: false, status: res.status, error: body };
    } catch (err) {
      logger.error?.('Brevo email request error', { to, error: err.message });
      return { sent: false, error: err.message };
    }
  }

  async function sendWelcomeEmail({ email, name }) {
    const displayName = name?.trim() || 'Spider-Friend';
    const subject = `Welcome to Spider Mind, ${displayName}! 🕸️`;

    const htmlContent = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #03040A; color: #FFFFFF; margin: 0; padding: 24px; }
    .card { max-width: 540px; margin: 0 auto; background: #0B0F1E; border: 1px solid rgba(50, 180, 255, 0.2); border-radius: 16px; padding: 32px; box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4); }
    .header { text-align: center; margin-bottom: 24px; }
    .badge { display: inline-block; background: rgba(255, 42, 68, 0.15); color: #FF2A44; border: 1px solid rgba(255, 42, 68, 0.4); border-radius: 9999px; padding: 6px 16px; font-weight: 700; font-size: 13px; text-transform: uppercase; letter-spacing: 1px; }
    h1 { color: #FFFFFF; font-size: 24px; margin: 16px 0 8px; font-weight: 800; }
    p { color: #A0AEC0; font-size: 15px; line-height: 1.6; margin: 8px 0; }
    .highlight { color: #32B4FF; font-weight: 600; }
    .features { background: rgba(255, 255, 255, 0.03); border-radius: 12px; padding: 18px; margin: 20px 0; border: 1px solid rgba(255, 255, 255, 0.06); }
    .feature-item { margin: 8px 0; display: flex; align-items: center; color: #E2E8F0; font-size: 14px; }
    .feature-item span { color: #32B4FF; margin-right: 8px; font-weight: bold; }
    .footer { text-align: center; margin-top: 24px; font-size: 12px; color: #718096; }
  </style>
</head>
<body>
  <div class="card">
    <div class="header">
      <div class="badge">Project Spider</div>
      <h1>Welcome aboard, ${displayName}!</h1>
      <p>Your interactive <span class="highlight">3D Mind Web</span> is ready to weave your tasks, ideas, questions, and goals.</p>
    </div>
    <div class="features">
      <div class="feature-item"><span>🕸️</span> <strong>3D Thread Graph:</strong> Navigate live webs across Work, Study & Personal.</div>
      <div class="feature-item"><span>⚡</span> <strong>Real-time Sync:</strong> Instant updates on Web & Android.</div>
      <div class="feature-item"><span>⏰</span> <strong>Timely Reminders:</strong> Keep your goals locked and on schedule.</div>
    </div>
    <p>Open Spider Mind from your browser or mobile app to start exploring your web!</p>
    <div class="footer">
      © ${new Date().getFullYear()} Spider Mind. Built for deep focus and superhuman execution.
    </div>
  </div>
</body>
</html>
    `.trim();

    return sendEmail({
      to: email,
      subject,
      htmlContent,
      textContent: `Welcome to Spider Mind, ${displayName}!\n\nYour 3D Mind Web is ready. Weave your tasks, ideas, and goals across all your devices in real-time.`,
    });
  }

  async function sendReminderEmail({ email, name, threadTitle, dueAt }) {
    const displayName = name?.trim() || 'Hero';
    const subject = `⏰ Reminder: "${threadTitle}" is due!`;

    const htmlContent = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #03040A; color: #FFFFFF; margin: 0; padding: 24px; }
    .card { max-width: 540px; margin: 0 auto; background: #0B0F1E; border: 1px solid rgba(255, 42, 68, 0.3); border-radius: 16px; padding: 32px; }
    .badge { display: inline-block; background: rgba(255, 42, 68, 0.15); color: #FF2A44; border-radius: 9999px; padding: 4px 12px; font-size: 12px; font-weight: 700; }
    h1 { color: #FFFFFF; font-size: 20px; margin: 16px 0 8px; }
    .task-box { background: rgba(255, 255, 255, 0.04); border-left: 4px solid #32B4FF; padding: 14px 18px; margin: 16px 0; border-radius: 4px; }
    .task-title { font-size: 16px; font-weight: 700; color: #FFFFFF; }
    .time { font-size: 13px; color: #A0AEC0; margin-top: 4px; }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">Due Reminder</div>
    <h1>Hey ${displayName}, don't let this slip!</h1>
    <div class="task-box">
      <div class="task-title">${threadTitle}</div>
      ${dueAt ? `<div class="time">Due: ${new Date(dueAt).toLocaleString()}</div>` : ''}
    </div>
    <p style="color: #A0AEC0; font-size: 14px;">Open your Spider Mind web to mark this thread as complete or reschedule.</p>
  </div>
</body>
</html>
    `.trim();

    return sendEmail({
      to: email,
      subject,
      htmlContent,
      textContent: `Hey ${displayName},\n\nYour task "${threadTitle}" is due now!\n\nOpen Spider Mind to check it off or update your web.`,
    });
  }

  return {
    isConfigured,
    sendEmail,
    sendWelcomeEmail,
    sendReminderEmail,
  };
}
