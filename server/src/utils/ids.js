import { randomBytes } from 'node:crypto';
import mongoose from 'mongoose';

export const OBJECT_ID_RE = /^[0-9a-fA-F]{24}$/;

export const isObjectId = (v) => typeof v === 'string' && OBJECT_ID_RE.test(v);
export const newId = () => new mongoose.Types.ObjectId().toString();
export const toOid = (v) => new mongoose.Types.ObjectId(v);
export const randomToken = (bytes = 32) => randomBytes(bytes).toString('base64url');
