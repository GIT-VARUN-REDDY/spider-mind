import mongoose from 'mongoose';
import { allModels } from './models/index.js';

mongoose.set('strictQuery', true);

export async function connectDb(uri, logger) {
  await mongoose.connect(uri, { serverSelectionTimeoutMS: 10_000 });
  // Wait for index builds so TTL/unique guarantees hold before we serve traffic.
  await Promise.all(allModels.map((m) => m.init()));
  logger?.info('mongo connected', { db: mongoose.connection.name });
}

export const disconnectDb = () => mongoose.disconnect();

export async function dbIsUp() {
  if (mongoose.connection.readyState !== 1) return false;
  try {
    await mongoose.connection.db.admin().ping();
    return true;
  } catch {
    return false;
  }
}
