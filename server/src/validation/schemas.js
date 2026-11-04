import { z } from 'zod';
import { OBJECT_ID_RE } from '../utils/ids.js';
import { isValidTimeZone, resolveTimeZone } from '../utils/time.js';

export const objectId = z
  .string()
  .regex(OBJECT_ID_RE, 'must be a 24 character hex id')
  .transform((s) => s.toLowerCase());

const isoDate = z.string().datetime({ offset: true, message: 'must be an ISO-8601 date-time' });
const timezone = z.string().max(64).refine(isValidTimeZone, 'must be a valid IANA time zone').transform(resolveTimeZone);

export const idParam = z.object({ id: objectId });

export const registerBody = z.object({
  email: z.string().trim().toLowerCase().email().max(254),
  password: z.string().min(8).max(128),
  name: z.string().trim().min(1).max(60),
  timezone: timezone.optional(),
});
export const loginBody = z.object({
  email: z.string().trim().toLowerCase().max(254),
  password: z.string().min(1).max(128),
});
export const googleAuthBody = z
  .object({
    credential: z.string().min(1).max(8192).optional(),
    idToken: z.string().min(1).max(8192).optional(),
    accessToken: z.string().min(1).max(8192).optional(),
  })
  .refine((b) => Boolean(b.credential || b.idToken || b.accessToken), 'credential, idToken, or accessToken is required');

export const refreshBody = z.object({ refreshToken: z.string().min(1).max(4096) });
export const patchMeBody = z
  .object({ name: z.string().trim().min(1).max(60).optional(), timezone: timezone.optional() })
  .refine((b) => b.name !== undefined || b.timezone !== undefined, 'nothing to update');
export const deleteMeBody = z.object({ password: z.string().min(1).max(128).optional() });

export const spaceBody = z.object({
  name: z.string().trim().min(1).max(40),
  color: z
    .string()
    .regex(/^#[0-9a-fA-F]{6}$/, 'must be #RRGGBB')
    .transform((s) => s.toUpperCase()),
  order: z.number().int().min(0).max(100000),
});
export const spaceDeleteQuery = z.object({ moveTo: objectId.optional() });

export const LIMITS = { threads: 1000, reminders: 20, checklist: 50, tags: 30, tagLen: 30, links: 100, spaces: 20 };

const uniqueBy = (key) => (arr, ctx) => {
  const seen = new Set();
  for (const it of arr) {
    const k = typeof it === 'string' ? it : it[key];
    if (seen.has(k)) ctx.addIssue({ code: 'custom', message: `duplicate ${key}` });
    seen.add(k);
  }
};

export const threadBody = z.object({
  id: objectId.optional(),
  title: z.string().trim().min(1).max(200),
  notes: z.string().max(2000).default(''),
  type: z.enum(['idea', 'task', 'question', 'goal']),
  status: z.enum(['todo', 'doing', 'done']),
  priority: z.enum(['low', 'medium', 'high']),
  spaceId: objectId,
  dueAt: isoDate.nullish().transform((v) => v ?? null),
  reminders: z
    .array(z.object({ id: objectId, at: isoDate }))
    .max(LIMITS.reminders)
    .superRefine(uniqueBy('id'))
    .default([]),
  tags: z.array(z.string().trim().min(1).max(LIMITS.tagLen)).max(LIMITS.tags).default([]),
  links: z.array(objectId).max(LIMITS.links).default([]),
  checklist: z
    .array(z.object({ id: objectId, text: z.string().trim().min(1).max(200), done: z.boolean().default(false) }))
    .max(LIMITS.checklist)
    .superRefine(uniqueBy('id'))
    .default([]),
  createdAt: isoDate.optional(),
  updatedAt: isoDate,
});

export const threadsQuery = z.object({ since: isoDate.optional() });

export const activityQuery = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(50),
  before: isoDate.optional(),
  threadId: objectId.optional(),
});

export const deviceBody = z.object({
  token: z.string().min(1).max(4096),
  platform: z.enum(['android', 'ios', 'web']),
});
export const deviceDeleteQuery = z.object({ token: z.string().min(1).max(4096) });
