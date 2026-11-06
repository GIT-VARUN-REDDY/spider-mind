import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { Activity, Device, RefreshToken, Space, Thread, User } from '../models/index.js';
import { asyncHandler, authenticate, validate } from '../middleware/common.js';
import { badRequest, conflict, notFound, unauthorized } from '../utils/errors.js';
import {
  deleteMeBody,
  googleAuthBody,
  loginBody,
  patchMeBody,
  refreshBody,
  registerBody,
  sendVerificationBody,
  verifyCodeBody,
  forgotPasswordBody,
  resetPasswordBody,
} from '../validation/schemas.js';
import { issueTokens, revokeRefreshToken, rotateRefreshToken } from '../services/tokens.js';
import { createDefaultSpaces } from '../services/spaces.js';
import { serializeUser } from '../services/serializers.js';
import { verifyGoogleToken } from '../services/googleAuth.js';

export function authRouter({ config, hub, email }) {
  const r = Router();
  // A real bcrypt hash so unknown emails cost the same as wrong passwords.
  const dummyHash = bcrypt.hashSync('timing-equalizer', config.bcryptCost);

  r.post(
    '/auth/register',
    validate({ body: registerBody }),
    asyncHandler(async (req, res) => {
      const { email: userEmail, password, name, timezone } = req.body;
      if (await User.exists({ email: userEmail })) throw conflict('Email is already registered');
      const passwordHash = await bcrypt.hash(password, config.bcryptCost);
      const verificationCode = Math.floor(100000 + Math.random() * 900000).toString();
      const verificationCodeExpiresAt = new Date(Date.now() + 24 * 3600 * 1000);
      const user = await User.create({
        email: userEmail,
        name,
        passwordHash,
        timezone: timezone ?? 'UTC',
        isVerified: false,
        verificationCode,
        verificationCodeExpiresAt,
      });
      await createDefaultSpaces(user._id);
      email?.sendVerificationEmail({ email: user.email, name: user.name, code: verificationCode }).catch(() => {});
      const tokens = await issueTokens(config, user._id);
      res.status(201).json({ user: serializeUser(user), ...tokens, verificationSent: Boolean(config.email?.enabled) });
    }),
  );

  r.post(
    '/auth/send-verification',
    validate({ body: sendVerificationBody }),
    asyncHandler(async (req, res) => {
      const user = await User.findOne({ email: req.body.email });
      if (!user) {
        return res.json({ ok: true, sent: false, message: 'If an account exists, a verification code was sent.' });
      }
      if (user.isVerified) {
        return res.json({ ok: true, sent: false, alreadyVerified: true, message: 'Email is already verified.' });
      }
      const verificationCode = Math.floor(100000 + Math.random() * 900000).toString();
      user.verificationCode = verificationCode;
      user.verificationCodeExpiresAt = new Date(Date.now() + 24 * 3600 * 1000);
      await user.save();
      const result = await email?.sendVerificationEmail({
        email: user.email,
        name: user.name,
        code: verificationCode,
      });
      res.json({ ok: true, sent: Boolean(result?.sent), message: 'Verification code sent.' });
    }),
  );

  r.post(
    '/auth/verify-code',
    validate({ body: verifyCodeBody }),
    asyncHandler(async (req, res) => {
      const user = await User.findOne({ email: req.body.email });
      if (!user) throw notFound('User not found');
      if (user.isVerified) {
        return res.json({ ok: true, verified: true, user: serializeUser(user) });
      }
      if (!user.verificationCode || user.verificationCode !== req.body.code.trim()) {
        throw badRequest('Invalid verification code');
      }
      if (user.verificationCodeExpiresAt && new Date() > user.verificationCodeExpiresAt) {
        throw badRequest('Verification code has expired. Please request a new one.');
      }
      user.isVerified = true;
      user.verificationCode = null;
      user.verificationCodeExpiresAt = null;
      await user.save();
      email?.sendWelcomeEmail({ email: user.email, name: user.name }).catch(() => {});
      res.json({ ok: true, verified: true, user: serializeUser(user) });
    }),
  );

  r.post(
    '/auth/forgot-password',
    validate({ body: forgotPasswordBody }),
    asyncHandler(async (req, res) => {
      const user = await User.findOne({ email: req.body.email });
      if (!user) {
        return res.json({ ok: true, sent: false, message: 'If an account exists with this email, a reset code was sent.' });
      }
      const resetCode = Math.floor(100000 + Math.random() * 900000).toString();
      user.resetPasswordCode = resetCode;
      user.resetPasswordCodeExpiresAt = new Date(Date.now() + 3600 * 1000); // 1 hour
      await user.save();
      const result = await email?.sendPasswordResetEmail({
        email: user.email,
        name: user.name,
        code: resetCode,
      });
      res.json({ ok: true, sent: Boolean(result?.sent), message: 'Password reset code sent.' });
    }),
  );

  r.post(
    '/auth/reset-password',
    validate({ body: resetPasswordBody }),
    asyncHandler(async (req, res) => {
      const { email: userEmail, code, newPassword } = req.body;
      const user = await User.findOne({ email: userEmail });
      if (!user) throw notFound('User not found');
      if (!user.resetPasswordCode || user.resetPasswordCode !== code.trim()) {
        throw badRequest('Invalid reset code');
      }
      if (user.resetPasswordCodeExpiresAt && new Date() > user.resetPasswordCodeExpiresAt) {
        throw badRequest('Reset code has expired. Please request a new one.');
      }
      const newHash = await bcrypt.hash(newPassword, config.bcryptCost);
      user.passwordHash = newHash;
      user.resetPasswordCode = null;
      user.resetPasswordCodeExpiresAt = null;
      user.isVerified = true;
      user.verificationCode = null;
      user.verificationCodeExpiresAt = null;
      await user.save();
      await RefreshToken.deleteMany({ userId: user._id });
      const tokens = await issueTokens(config, user._id);
      res.json({ ok: true, message: 'Password reset successfully', user: serializeUser(user), ...tokens });
    }),
  );

  r.post(
    '/auth/login',
    validate({ body: loginBody }),
    asyncHandler(async (req, res) => {
      const user = await User.findOne({ email: req.body.email }).lean();
      const ok = await bcrypt.compare(req.body.password, user?.passwordHash ?? dummyHash);
      if (!user || !ok) throw unauthorized('Invalid email or password');
      res.json({ user: serializeUser(user), ...(await issueTokens(config, user._id)) });
    }),
  );

  r.get('/auth/config', (req, res) => {
    res.json({
      googleClientId: config.googleClientId,
      emailEnabled: Boolean(config.email?.enabled),
    });
  });

  r.post(
    '/auth/test-email',
    asyncHandler(async (req, res) => {
      const target = typeof req.body?.email === 'string' ? req.body.email.trim() : null;
      if (!target || !target.includes('@')) {
        return res.status(400).json({ error: { code: 'VALIDATION', message: 'Valid email is required' } });
      }
      const result = await email?.sendWelcomeEmail({ email: target, name: req.body?.name || 'Spider Hero' });
      res.json({ ok: true, result });
    }),
  );

  r.post(
    '/auth/google',
    validate({ body: googleAuthBody }),
    asyncHandler(async (req, res) => {
      const token = req.body.credential || req.body.idToken || req.body.accessToken;
      const profile = await verifyGoogleToken(token, config.googleClientId);
      if (!profile) {
        throw unauthorized('Invalid or expired Google credential');
      }

      const emailAddress = String(profile.email).toLowerCase().trim();
      let user = await User.findOne({ email: emailAddress });

      if (!user) {
        user = await User.create({
          email: emailAddress,
          name: profile.name?.trim() || emailAddress.split('@')[0],
          googleId: profile.sub,
          picture: profile.picture || null,
          timezone: 'UTC',
          isVerified: true,
        });
        await createDefaultSpaces(user._id);
        email?.sendWelcomeEmail({ email: user.email, name: user.name }).catch(() => {});
      } else {
        if (user.googleId && user.googleId !== profile.sub) {
          throw conflict('This email is linked to a different Google account');
        }
        let changed = false;
        if (!user.googleId) {
          user.googleId = profile.sub;
          changed = true;
        }
        if (!user.picture && profile.picture) {
          user.picture = profile.picture;
          changed = true;
        }
        if (changed) {
          await user.save();
        }
      }

      const tokens = await issueTokens(config, user._id);
      res.json({ user: serializeUser(user), ...tokens });
    }),
  );

  r.post(
    '/auth/refresh',
    validate({ body: refreshBody }),
    asyncHandler(async (req, res) => {
      const { accessToken, refreshToken, expiresIn } = await rotateRefreshToken(config, req.body.refreshToken);
      res.json({ accessToken, refreshToken, expiresIn });
    }),
  );

  r.post(
    '/auth/logout',
    asyncHandler(async (req, res) => {
      const t = req.body?.refreshToken;
      if (typeof t === 'string' && t.length <= 4096) await revokeRefreshToken(t).catch(() => {});
      res.status(204).end();
    }),
  );

  const auth = authenticate(config);
  r.get('/me', auth, (req, res) => res.json({ user: serializeUser(req.user) }));

  r.patch(
    '/me',
    auth,
    validate({ body: patchMeBody }),
    asyncHandler(async (req, res) => {
      const user = await User.findByIdAndUpdate(req.user.id, { $set: req.body }, { new: true, lean: true });
      res.json({ user: serializeUser(user) });
    }),
  );

  r.delete(
    '/me',
    auth,
    validate({ body: deleteMeBody }),
    asyncHandler(async (req, res) => {
      const user = await User.findById(req.user.id).lean();
      if (!user) throw unauthorized('User not found');
      if (user.passwordHash) {
        if (!req.body.password || !(await bcrypt.compare(req.body.password, user.passwordHash))) {
          throw unauthorized('Invalid password');
        }
      }
      const userId = user._id;
      await Promise.all([
        Thread.deleteMany({ userId }),
        Space.deleteMany({ userId }),
        Activity.deleteMany({ userId }),
        Device.deleteMany({ userId }),
        RefreshToken.deleteMany({ userId }),
      ]);
      await User.deleteOne({ _id: userId });
      hub.disconnectUser(String(userId));
      res.status(204).end();
    }),
  );
  return r;
}
