import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { createSocial } from './social.mjs';
import { createChat } from './chat.mjs';
import {createAvatars,avatarJoins,avatarColumns,avatarFields} from './avatars.mjs';
import {createPush} from './push.mjs';
import {createCalls} from './calls.mjs';
import {
  ApiError, digest, hashPassword, verifyPassword, newToken, newRecoveryCode,
  normalizeRecoveryCode, validateUsername, validatePassword, validateProfile, isUniqueConflict,
} from './security.mjs';

const sessionLifetime = 30 * 24 * 60 * 60 * 1000;
const nowText = () => new Date().toISOString();

async function readJson(request, maximum = 16384) {
  if (!(request.headers['content-type'] || '').toLowerCase().startsWith('application/json')) {
    throw new ApiError(415, 'CONTENT_TYPE', 'صيغة الطلب غير مدعومة.');
  }
  let size = 0;
  const chunks = [];
  for await (const chunk of request) {
    size += chunk.length;
    if (size > maximum) throw new ApiError(413, 'TOO_LARGE', 'الطلب أكبر من المسموح.');
    chunks.push(chunk);
  }
  try {
    const value = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (value && !Array.isArray(value) && typeof value === 'object') return value;
  } catch {}
  throw new ApiError(400, 'BAD_JSON', 'تعذّر قراءة الطلب.');
}

function json(response, status, data, headers = {}) {
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'no-referrer',
    ...headers,
  });
  response.end(JSON.stringify(data));
}

const userSelect = `SELECT u.id, u.username, u.display_name, u.bio, u.avatar_preset, u.created_at${avatarColumns},
  (SELECT COUNT(*) FROM tomi_follows f WHERE f.following_id = u.id) AS followers_count,
  (SELECT COUNT(*) FROM tomi_follows f WHERE f.follower_id = u.id) AS following_count,
  (SELECT COUNT(*) FROM tomi_posts p WHERE p.user_id = u.id) AS posts_count,
  (SELECT COUNT(*) FROM tomi_follows f WHERE f.follower_id = ? AND f.following_id = u.id) AS is_following
  FROM tomi_users u ${avatarJoins}`;

function publicUser(row,storage) {
  return {
    id: row.id, username: row.username, displayName: row.display_name, bio: row.bio,
    avatarPreset: row.avatar_preset, ...avatarFields(row,storage), createdAt: row.created_at,
    followersCount: Number(row.followers_count), followingCount: Number(row.following_count),
    postsCount: Number(row.posts_count), isFollowing: Number(row.is_following) > 0,
  };
}

export async function createApp({ database, trustProxy = false, origins = [], rateLimitMultiplier = 1, storage = null, chatStorage = storage, pushSender=null, pushAutoFlush=true, iceProvider=null, callAutoSweep=true }) {
  // Equal-cost verification for unknown users avoids a cheap username timing oracle.
  const dummyHash = await hashPassword(newToken());
  const userById = async (id, viewer, db = database) => {
    const result = await db.query(`${userSelect} WHERE u.id = ?`, [viewer, id]);
    if (!result.rows[0]) throw new ApiError(404, 'NOT_FOUND', 'الحساب غير موجود.');
    return publicUser(result.rows[0],storage);
  };

  async function limit(key, maximum, period = 60000) {
    const start = Date.now() - (Date.now() % period);
    const result = await database.query(`INSERT INTO tomi_rate_limits (bucket_key, window_started, hits)
      VALUES (?, ?, 1) ON CONFLICT (bucket_key) DO UPDATE SET
      hits = CASE WHEN tomi_rate_limits.window_started = excluded.window_started THEN tomi_rate_limits.hits + 1 ELSE 1 END,
      window_started = excluded.window_started RETURNING hits`, [digest(key), start]);
    if (Number(result.rows[0].hits) > maximum * rateLimitMultiplier) {
      throw new ApiError(429, 'RATE_LIMITED', 'محاولات كثيرة؛ انتظر قليلًا وجرّب مرة ثانية.');
    }
  }

  async function session(request) {
    const authorization = request.headers.authorization || '';
    if (!/^Bearer [a-zA-Z0-9_-]{43}$/.test(authorization)) {
      throw new ApiError(401, 'UNAUTHORIZED', 'سجّل دخولك حتى تكمل.');
    }
    const tokenHash = digest(authorization.slice(7));
    const result = await database.query(`SELECT s.user_id, s.token_hash FROM tomi_sessions s
      JOIN tomi_users u ON u.id = s.user_id AND u.auth_version = s.auth_version
      WHERE s.token_hash = ? AND s.expires_at > ?`, [tokenHash, nowText()]);
    if (!result.rows[0]) throw new ApiError(401, 'UNAUTHORIZED', 'انتهت الجلسة؛ سجّل دخولك مرة ثانية.');
    return { id: result.rows[0].user_id, tokenHash };
  }

  async function grant(db, userId, version) {
    const token = newToken();
    const created = nowText();
    const expires = new Date(Date.now() + sessionLifetime).toISOString();
    await db.query(`INSERT INTO tomi_sessions (token_hash, user_id, auth_version, created_at, expires_at)
      VALUES (?, ?, ?, ?, ?)`, [digest(token), userId, version, created, expires]);
    return { token, expiresAt: expires };
  }

  const social = createSocial({database, storage, readJson, respond: json, limit, userById, cleanupPrefix:chatStorage===storage?'tomi/':'tomi/posts/'});
  const chatMedia=chatStorage===storage?null:createSocial({database,storage:chatStorage,readJson,respond:json,limit,userById,cleanupPrefix:'tomi/chat-images/'});
  const avatars=createAvatars({database,storage,readJson,respond:json,limit,userById});
  const avatarMedia=chatStorage===storage?null:createSocial({database,storage,readJson,respond:json,limit,userById,cleanupPrefix:'tomi/avatars/'});
  const push=createPush({database,sender:pushSender,autoFlush:pushAutoFlush,readJson,respond:json,limit});
  const chat=createChat({database,storage:chatStorage,avatarStorage:storage,readJson,respond:json,limit,userById,enqueuePush:push.enqueue});
  const calls=createCalls({database,iceProvider,readJson,respond:json,limit,userById,emit:chat.emit,enqueuePush:push.enqueueCall,autoSweep:callAutoSweep});
  const server = createServer(async (request, response) => {
    try {
      const origin = request.headers.origin;
      if (origin && !origins.includes(origin)) throw new ApiError(403, 'ORIGIN', 'مصدر الطلب غير مسموح.');
      if (origin) {
        response.setHeader('access-control-allow-origin', origin);
        response.setHeader('vary', 'Origin');
      }
      if (request.method === 'OPTIONS') {
        response.writeHead(204, {
          'access-control-allow-methods': 'GET, POST, PATCH, PUT, DELETE, OPTIONS',
          'access-control-allow-headers': 'Content-Type, Authorization',
          'access-control-max-age': '600',
        });
        response.end();
        return;
      }
      const url = new URL(request.url, 'http://tomi.internal');
      const path = url.pathname;
      const method = request.method;
      let ip = request.socket.remoteAddress || 'unknown';
      if (trustProxy && request.headers['x-forwarded-for']) {
        ip = String(request.headers['x-forwarded-for']).split(',').at(-1).trim();
      }
      if (method === 'GET' && (path === '/health' || path === '/')) {
        await database.query('SELECT 1 AS ready');
        json(response, 200, { status: 'ok', service: 'TOMI API', version: '0.6.0' });
        return;
      }

      if (method === 'POST' && path === '/v1/auth/register') {
        await limit(`register:ip:${ip}`, 5, 3600000);
        const data = await readJson(request);
        const password = validatePassword(data.password);
        const profile = validateProfile({ username: data.username, displayName: data.displayName, bio: '', avatarPreset: 'initials' });
        const recoveryCode = newRecoveryCode();
        const passwordHash = await hashPassword(password);
        const id = randomUUID();
        const created = nowText();
        try {
          const result = await database.transaction(async (db) => {
            await db.query(`INSERT INTO tomi_users (id, username, display_name, bio, avatar_preset,
              password_hash, recovery_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
              [id, profile.username, profile.name, '', 'initials', passwordHash,
                digest(normalizeRecoveryCode(recoveryCode)), created, created]);
            return { ...(await grant(db, id, 1)), user: await userById(id, id, db), recoveryCode };
          });
          json(response, 201, result);
        } catch (error) {
          if (isUniqueConflict(error)) throw new ApiError(409, 'USERNAME_TAKEN', 'هذا اليوزر مستخدم؛ اختَر غيره.', 'username');
          throw error;
        }
        return;
      }

      if (method === 'POST' && path === '/v1/auth/login') {
        await limit(`login:ip:${ip}`, 50, 900000);
        const data = await readJson(request);
        const username = validateUsername(data.username);
        await limit(`login:username:${username}`, 10, 900000);
        const password = typeof data.password === 'string' && [...data.password].length <= 128 ? data.password : '';
        const { rows } = await database.query('SELECT id, password_hash, auth_version FROM tomi_users WHERE username = ?', [username]);
        const row = rows[0];
        const matches = await verifyPassword(password, row?.password_hash || dummyHash);
        if (!row || !matches) throw new ApiError(401, 'BAD_CREDENTIALS', 'اليوزر أو كلمة المرور غير صحيحة.');
        const result = await database.transaction(async (db) => ({
          ...(await grant(db, row.id, row.auth_version)), user: await userById(row.id, row.id, db),
        }));
        json(response, 200, result);
        return;
      }

      if (method === 'POST' && path === '/v1/auth/recover') {
        await limit(`recover:ip:${ip}`, 20, 900000);
        const data = await readJson(request);
        const username = validateUsername(data.username);
        await limit(`recover:username:${username}`, 5, 900000);
        const password = validatePassword(data.password);
        const code = typeof data.recoveryCode === 'string' ? normalizeRecoveryCode(data.recoveryCode) : '';
        if (!/^[A-F0-9]{40}$/.test(code)) throw new ApiError(400, 'BAD_RECOVERY', 'اليوزر أو رمز الاسترجاع غير صحيح.');
        const { rows } = await database.query('SELECT id, recovery_hash, auth_version FROM tomi_users WHERE username = ?', [username]);
        const row = rows[0];
        if (!row || row.recovery_hash !== digest(code)) throw new ApiError(400, 'BAD_RECOVERY', 'اليوزر أو رمز الاسترجاع غير صحيح.');
        const passwordHash = await hashPassword(password);
        const recoveryCode = newRecoveryCode();
        const result = await database.transaction(async (db) => {
          const updated = await db.query(`UPDATE tomi_users SET password_hash = ?, recovery_hash = ?,
            auth_version = auth_version + 1, updated_at = ? WHERE id = ? AND recovery_hash = ?`,
            [passwordHash, digest(normalizeRecoveryCode(recoveryCode)), nowText(), row.id, digest(code)]);
          if (updated.changes !== 1) throw new ApiError(400, 'BAD_RECOVERY', 'رمز الاسترجاع استُخدم؛ استخدم الرمز الجديد.');
          await db.query('DELETE FROM tomi_sessions WHERE user_id = ?', [row.id]);
          return { ...(await grant(db, row.id, row.auth_version + 1)),
            user: await userById(row.id, row.id, db), recoveryCode };
        });
        chat.invalidateUser(row.id);
        await calls.sweep();
        json(response, 200, result);
        return;
      }

      const current = await session(request);
      await limit(`requests:user:${current.id}`, 300);
      if (await calls.handle(request,response,url,current)) return;
      if (await avatars.handle(request,response,url,current)) return;
      if (await push.handle(request,response,url,current)) return;
      if (await chat.handle(request,response,url,current)) return;
      if (await social.handle(request,response,url,current)) return;

      if (method === 'POST' && path === '/v1/auth/logout') {
        await database.query('DELETE FROM tomi_sessions WHERE token_hash = ?', [current.tokenHash]);
        chat.invalidateSession(current.tokenHash);
        await calls.invalidateSession(current.tokenHash);
        json(response, 200, { ok: true });
        return;
      }

      if (method === 'GET' && path === '/v1/me') {
        json(response, 200, { user: await userById(current.id, current.id) });
        return;
      }

      if (method === 'PATCH' && path === '/v1/me') {
        await limit(`profile:user:${current.id}`, 30);
        const data = await readJson(request);
        const profile = validateProfile(data);
        try {
          await database.query(`UPDATE tomi_users SET username = ?, display_name = ?, bio = ?, avatar_preset = ?,
            updated_at = ? WHERE id = ?`, [profile.username, profile.name, profile.bio, profile.avatarPreset, nowText(), current.id]);
        } catch (error) {
          if (isUniqueConflict(error)) throw new ApiError(409, 'USERNAME_TAKEN', 'هذا اليوزر مستخدم؛ اختَر غيره.', 'username');
          throw error;
        }
        json(response, 200, { user: await userById(current.id, current.id) });
        return;
      }

      if (method === 'POST' && path === '/v1/auth/password') {
        await limit(`password:user:${current.id}`, 5, 900000);
        const data = await readJson(request);
        const newPassword = validatePassword(data.newPassword);
        const oldPassword = typeof data.currentPassword === 'string' && [...data.currentPassword].length <= 128 ? data.currentPassword : '';
        const { rows } = await database.query('SELECT password_hash, auth_version FROM tomi_users WHERE id = ?', [current.id]);
        const row = rows[0];
        if (!row || !(await verifyPassword(oldPassword, row.password_hash))) {
          throw new ApiError(400, 'BAD_PASSWORD', 'كلمة المرور الحالية غير صحيحة.', 'currentPassword');
        }
        const passwordHash = await hashPassword(newPassword);
        const recoveryCode = newRecoveryCode();
        const result = await database.transaction(async (db) => {
          const changed = await db.query(`UPDATE tomi_users SET password_hash = ?, recovery_hash = ?,
            auth_version = auth_version + 1, updated_at = ? WHERE id = ? AND auth_version = ?`,
            [passwordHash, digest(normalizeRecoveryCode(recoveryCode)), nowText(), current.id, row.auth_version]);
          if (changed.changes !== 1) throw new ApiError(409, 'RETRY', 'الحساب تغيّر؛ سجّل دخولك مرة ثانية.');
          await db.query('DELETE FROM tomi_sessions WHERE user_id = ?', [current.id]);
          return { ...(await grant(db, current.id, row.auth_version + 1)),
            user: await userById(current.id, current.id, db), recoveryCode };
        });
        chat.invalidateUser(current.id);
        await calls.sweep();
        json(response, 200, result);
        return;
      }

      if (method === 'GET' && path === '/v1/users') {
        const q = (url.searchParams.get('q') || '').trim().replace(/^@/, '').toLowerCase();
        if ([...q].length < 2) { json(response, 200, { users: [] }); return; }
        if ([...q].length > 40) throw new ApiError(400, 'VALIDATION', 'نص البحث طويل.');
        const escaped = q.replace(/[\\%_]/g, (character) => `\\${character}`);
        const pattern = `%${escaped}%`;
        const result = await database.query(`${userSelect}
          WHERE (u.username LIKE ? ESCAPE '\\' OR LOWER(u.display_name) LIKE ? ESCAPE '\\')
          AND u.id <> ? ORDER BY u.username LIMIT 20`, [current.id, pattern, pattern, current.id]);
        json(response, 200, { users: result.rows.map(row=>publicUser(row,storage)) });
        return;
      }

      const userMatch = path.match(/^\/v1\/users\/([a-f0-9-]{36})(\/follow)?$/);
      if (userMatch && method === 'GET' && !userMatch[2]) {
        json(response, 200, { user: await userById(userMatch[1], current.id) });
        return;
      }
      if (userMatch && method === 'PUT' && userMatch[2]) {
        const target = userMatch[1];
        if (target === current.id) throw new ApiError(400, 'SELF_FOLLOW', 'ما تگدر تتابع نفسك.');
        const data = await readJson(request);
        if (typeof data.follow !== 'boolean') throw new ApiError(400, 'VALIDATION', 'حدّد حالة المتابعة.');
        const result = await database.transaction(async (db) => {
          await userById(target, current.id, db);
          if (data.follow) {
            await db.query(`INSERT INTO tomi_follows (follower_id, following_id, created_at)
              VALUES (?, ?, ?) ON CONFLICT (follower_id, following_id) DO NOTHING`, [current.id, target, nowText()]);
          } else {
            await db.query('DELETE FROM tomi_follows WHERE follower_id = ? AND following_id = ?', [current.id, target]);
          }
          return { user: await userById(target, current.id, db), me: await userById(current.id, current.id, db) };
        });
        json(response, 200, result);
        return;
      }
      throw new ApiError(404, 'NOT_FOUND', 'المسار غير موجود.');
    } catch (error) {
      if (response.headersSent) { response.destroy(); return; }
      if (error instanceof ApiError) {
        json(response, error.status, { error: { code: error.code, message: error.message,
          ...(error.field ? { field: error.field } : {}) } }, error.status === 429 ? { 'retry-after': '60' } : {});
      } else {
        // Never log request bodies, authorization headers, database URLs or profile data.
        console.error('Request failed:', error.code || error.name);
        json(response, 503, { error: { code: 'UNAVAILABLE', message: 'الخدمة غير متاحة حاليًا؛ جرّب مرة ثانية.' } });
      }
    }
  });
  server.cleanupMedia = async()=>{await social.cleanup();if(chatMedia)await chatMedia.cleanup();if(avatarMedia)await avatarMedia.cleanup();await chat.cleanup();await push.cleanup();await calls.cleanup();};
  server.flushPush=push.flush;
  server.sweepCalls=calls.sweep;
  server.on('close',()=>{push.close();calls.close();});
  chat.attach(server,{origins,authenticate:token=>session({headers:{authorization:'Bearer '+token}}),validSessions:async hashes=>{
    if(!hashes.length)return new Set();
    const{rows}=await database.query(`SELECT s.token_hash FROM tomi_sessions s JOIN tomi_users u ON u.id=s.user_id AND u.auth_version=s.auth_version WHERE s.expires_at>? AND s.token_hash IN (${hashes.map(()=>'?').join(',')})`,[nowText(),...hashes]);return new Set(rows.map(r=>r.token_hash));
  }});
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  server.keepAliveTimeout = 5000;
  server.maxRequestsPerSocket = 100;
  return server;
}
