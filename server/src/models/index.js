import mongoose from 'mongoose';

const { Schema } = mongoose;
const DAY = 24 * 3600;

const userSchema = new Schema(
  {
    email: { type: String, required: true, unique: true, lowercase: true, trim: true },
    name: { type: String, required: true },
    passwordHash: { type: String, default: null },
    googleId: { type: String, sparse: true, index: true, default: null },
    picture: { type: String, default: null },
    timezone: { type: String, default: 'UTC' },
    isVerified: { type: Boolean, default: false },
    verificationCode: { type: String, default: null },
    verificationCodeExpiresAt: { type: Date, default: null },
    resetPasswordCode: { type: String, default: null },
    resetPasswordCodeExpiresAt: { type: Date, default: null },
    createdAt: { type: Date, default: () => new Date() },
  },
  { versionKey: false },
);

const spaceSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, required: true },
    name: { type: String, required: true },
    color: { type: String, required: true },
    order: { type: Number, default: 0 },
  },
  { versionKey: false },
);
spaceSchema.index({ userId: 1, order: 1 });

const threadSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, required: true },
    title: { type: String, required: true },
    notes: { type: String, default: '' },
    type: { type: String, enum: ['idea', 'task', 'question', 'goal'], default: 'task' },
    status: { type: String, enum: ['todo', 'doing', 'done'], default: 'todo' },
    priority: { type: String, enum: ['low', 'medium', 'high'], default: 'medium' },
    spaceId: { type: Schema.Types.ObjectId, required: true },
    dueAt: { type: Date, default: null },
    reminders: [
      {
        _id: false,
        id: { type: String, required: true },
        at: { type: Date, required: true },
        sentAt: { type: Date, default: null },
      },
    ],
    tags: { type: [String], default: [] },
    keywords: { type: [String], default: [] },
    links: { type: [Schema.Types.ObjectId], default: [] },
    checklist: [
      {
        _id: false,
        id: { type: String, required: true },
        text: { type: String, required: true },
        done: { type: Boolean, default: false },
      },
    ],
    createdAt: { type: Date, required: true },
    // Client-controlled (clamped); drives last-writer-wins.
    updatedAt: { type: Date, required: true },
    completedAt: { type: Date, default: null },
    deletedAt: { type: Date, default: null },
    // Server write time: lets `since` pulls see writes from clients with skewed clocks.
    syncedAt: { type: Date, required: true },
    // Optimistic-concurrency counter shared by PUT, delete and the reminder scheduler.
    rev: { type: Number, default: 0 },
  },
  { versionKey: false },
);
threadSchema.index({ userId: 1, updatedAt: 1 });
threadSchema.index({ userId: 1, syncedAt: 1 });
threadSchema.index({ userId: 1, deletedAt: 1 });
threadSchema.index({ userId: 1, spaceId: 1 });
threadSchema.index({ 'reminders.at': 1, 'reminders.sentAt': 1 });
threadSchema.index(
  { deletedAt: 1 },
  { name: 'tombstone_ttl', expireAfterSeconds: 90 * DAY, partialFilterExpression: { deletedAt: { $type: 'date' } } },
);

const activitySchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, required: true },
    kind: { type: String, enum: ['created', 'updated', 'status', 'reminder', 'linked', 'deleted'], required: true },
    threadId: { type: Schema.Types.ObjectId, required: true },
    message: { type: String, required: true },
    at: { type: Date, required: true, default: () => new Date() },
  },
  { versionKey: false },
);
activitySchema.index({ userId: 1, at: -1 });
activitySchema.index({ userId: 1, threadId: 1, at: -1 });
activitySchema.index({ at: 1 }, { name: 'activity_ttl', expireAfterSeconds: 90 * DAY });

const deviceSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, required: true, index: true },
    token: { type: String, required: true, unique: true },
    platform: { type: String, enum: ['android', 'ios', 'web'], required: true },
    lastSeenAt: { type: Date, default: () => new Date() },
  },
  { versionKey: false },
);

const refreshTokenSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, required: true, index: true },
    familyId: { type: String, required: true, index: true },
    tokenHash: { type: String, required: true, unique: true },
    used: { type: Boolean, default: false },
    expiresAt: { type: Date, required: true },
  },
  { versionKey: false },
);
refreshTokenSchema.index({ expiresAt: 1 }, { name: 'refresh_ttl', expireAfterSeconds: 0 });

export const User = mongoose.model('User', userSchema);
export const Space = mongoose.model('Space', spaceSchema);
export const Thread = mongoose.model('Thread', threadSchema);
export const Activity = mongoose.model('Activity', activitySchema);
export const Device = mongoose.model('Device', deviceSchema);
export const RefreshToken = mongoose.model('RefreshToken', refreshTokenSchema);
export const allModels = [User, Space, Thread, Activity, Device, RefreshToken];
