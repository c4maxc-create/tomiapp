import { randomBytes, createHash, scrypt, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';

const derive = promisify(scrypt);
const options = { N: 131072, r: 8, p: 1, maxmem: 160 * 1024 * 1024 };

export class ApiError extends Error {
  constructor(status, code, message, field) {
    super(message);
    this.status = status;
    this.code = code;
    this.field = field;
  }
}

// Bound memory-heavy work to one running hash and eight waiting requests.
let active = false;
const waiting = [];
async function oneHash(work) {
  if (active) {
    if (waiting.length >= 8) throw new ApiError(503, 'BUSY', 'الخدمة مشغولة، جرّب بعد قليل.');
    await new Promise((resolve) => waiting.push(resolve));
  } else {
    active = true;
  }
  try { return await work(); }
  finally {
    const next = waiting.shift();
    if (next) next(); else active = false;
  }
}

export async function hashPassword(password) {
  const salt = randomBytes(16).toString('hex');
  const key = await oneHash(() => derive(password, salt, 64, options));
  return `scrypt$131072$8$1$${salt}$${key.toString('hex')}`;
}

export async function verifyPassword(password, encoded) {
  const [algorithm, n, r, p, salt, hex] = encoded.split('$');
  if (algorithm !== 'scrypt' || n !== '131072' || r !== '8' || p !== '1' ||
      !/^[a-f0-9]{32}$/.test(salt || '') || !/^[a-f0-9]{128}$/.test(hex || '')) return false;
  const key = await oneHash(() => derive(password, salt, 64, options));
  return timingSafeEqual(key, Buffer.from(hex, 'hex'));
}

export const digest = (value) => createHash('sha256').update(value).digest('hex');
export const newToken = () => randomBytes(32).toString('base64url');
export const newRecoveryCode = () => randomBytes(20).toString('hex').toUpperCase().match(/.{8}/g).join('-');
export const normalizeRecoveryCode = (code) => code.replace(/[\s-]/g, '').toUpperCase();

export function validateUsername(value) {
  if (typeof value !== 'string') throw new ApiError(400, 'VALIDATION', 'اكتب اليوزر.', 'username');
  const username = value.trim().toLowerCase();
  if (!/^[a-z0-9_]{3,20}$/.test(username)) {
    throw new ApiError(400, 'VALIDATION', 'اليوزر من 3 إلى 20 حرفًا إنكليزيًا أو رقمًا أو _.', 'username');
  }
  return username;
}

export function validatePassword(value) {
  if (typeof value !== 'string' || [...value].length < 15 || [...value].length > 128) {
    throw new ApiError(400, 'VALIDATION', 'استخدم كلمة مرور من 15 إلى 128 حرفًا؛ تگدر تكتب عبارة طويلة.', 'password');
  }
  return value;
}

export function validateProfile(data) {
  const fields = ['username', 'displayName', 'bio', 'avatarPreset'];
  if (Object.keys(data).some((key) => !fields.includes(key))) {
    throw new ApiError(400, 'VALIDATION', 'هذا التعديل غير مسموح.');
  }
  const username = validateUsername(data.username);
  const name = typeof data.displayName === 'string' ? data.displayName.trim() : '';
  if ([...name].length < 2 || [...name].length > 30) {
    throw new ApiError(400, 'VALIDATION', 'الاسم من حرفين إلى 30 حرفًا.', 'displayName');
  }
  const bio = typeof data.bio === 'string' ? data.bio.trim() : '';
  if ([...bio].length > 140) throw new ApiError(400, 'VALIDATION', 'النبذة بحد أقصى 140 حرفًا.', 'bio');
  const avatarPreset = data.avatarPreset || 'initials';
  if (!['initials', 'moon', 'cat', 'fox', 'panda', 'robot', 'flower', 'star'].includes(avatarPreset)) {
    throw new ApiError(400, 'VALIDATION', 'اختَر صورة من الخيارات المتاحة.', 'avatarPreset');
  }
  return { username, name, bio, avatarPreset };
}

export function isUniqueConflict(error) {
  return error.code === '23505' || error.code === 'SQLITE_CONSTRAINT_UNIQUE' ||
    (error.code === 'ERR_SQLITE_ERROR' && /UNIQUE constraint failed/i.test(error.message));
}
