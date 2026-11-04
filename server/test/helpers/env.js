import { execFileSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import mongoose from 'mongoose';
import request from 'supertest';
import { io as ioClient } from 'socket.io-client';
import { startServer } from '../../src/index.js';

const BASE_ENV = {
  NODE_ENV: 'test',
  PORT: '0',
  BCRYPT_COST: '4',
  REMINDER_SCHEDULER_ENABLED: 'false',
  RATE_LIMIT_GLOBAL_MAX: '100000',
  RATE_LIMIT_AUTH_MAX: '100000',
};

async function resolveMongo() {
  const dbName = `spidermind_test_${randomBytes(4).toString('hex')}`;
  if (process.env.MONGODB_URI) {
    const uri = process.env.MONGODB_URI.replace(/^(mongodb(?:\+srv)?:\/\/[^/?]+)(\/[^?]*)?/, `$1/${dbName}`);
    return { uri, stop: async () => {} };
  }
  try {
    if (!process.env.MONGOMS_SYSTEM_BINARY) {
      const bin = execFileSync('sh', ['-c', 'command -v mongod'], { encoding: 'utf8' }).trim();
      if (bin) process.env.MONGOMS_SYSTEM_BINARY = bin;
    }
  } catch {
    /* no system mongod: mongodb-memory-server will try to download one */
  }
  const { MongoMemoryServer } = await import('mongodb-memory-server');
  const mms = await Promise.race([
    MongoMemoryServer.create(),
    new Promise((_, rej) => setTimeout(() => rej(new Error('mongodb-memory-server timed out')), 60_000)),
  ]);
  return { uri: mms.getUri(dbName), stop: () => mms.stop() };
}

/**
 * Boots the API against a real MongoDB. Returns null (after a loud warning) when no
 * MongoDB is available, unless REQUIRE_MONGO=1 (CI), in which case it throws.
 */
export async function startTestServer(extraEnv = {}) {
  let mongo;
  try {
    mongo = await resolveMongo();
  } catch (err) {
    const msg = `INTEGRATION TESTS SKIPPED: no MongoDB available (set MONGODB_URI or install mongod). ${err.message}`;
    if (process.env.REQUIRE_MONGO === '1') throw new Error(msg);
    console.error('\n' + '!'.repeat(78) + `\n${msg}\n` + '!'.repeat(78) + '\n');
    // A stalled mongod download can keep the event loop alive; the only test left is the skip marker.
    setTimeout(() => process.exit(0), 3000).unref();
    return null;
  }
  const server = await startServer({ env: { ...BASE_ENV, ...extraEnv, MONGODB_URI: mongo.uri } });
  const api = request(server.url);
  return {
    ...server,
    api,
    async close() {
      await server.stop();
      await mongoose.connect(mongo.uri).then(() => mongoose.connection.dropDatabase()).catch(() => {});
      await mongoose.disconnect().catch(() => {});
      await mongo.stop();
    },
  };
}

let counter = 0;
export async function registerUser(t, over = {}) {
  const email = over.email ?? `user${++counter}_${randomBytes(3).toString('hex')}@example.com`;
  const res = await t.api
    .post('/api/v1/auth/register')
    .send({ email, password: 'correct horse', name: 'Test User', ...over });
  if (res.status !== 201) throw new Error(`register failed: ${res.status} ${JSON.stringify(res.body)}`);
  const auth = (r) => r.set('Authorization', `Bearer ${res.body.accessToken}`);
  return { ...res.body, email, auth, headers: { Authorization: `Bearer ${res.body.accessToken}` } };
}

export const hex24 = () => randomBytes(12).toString('hex');

export function threadBody(spaceId, over = {}) {
  return {
    title: 'Write the report',
    notes: '',
    type: 'task',
    status: 'todo',
    priority: 'medium',
    spaceId,
    updatedAt: new Date().toISOString(),
    ...over,
  };
}

export function connectSocket(t, token, clientOpts = {}) {
  const s = ioClient(t.url, { auth: { token }, transports: ['websocket'], reconnection: false, ...clientOpts });
  return new Promise((resolve, reject) => {
    s.once('connect', () => resolve(s));
    s.once('connect_error', (e) => {
      s.close();
      reject(e);
    });
  });
}

export const nextEvent = (socket, name, ms = 4000) =>
  new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`timeout waiting for ${name}`)), ms);
    socket.once(name, (p) => {
      clearTimeout(timer);
      resolve(p);
    });
  });

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
