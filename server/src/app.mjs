import {createFederatedAuth} from './federated_auth.mjs';
import {createE2ee} from './e2ee.mjs';
import {createMfa} from './mfa.mjs';
import {clientIp,validateJsonShape,verifyEdge} from './request_security.mjs';
import {createContentPreferences} from './content_preferences.mjs';
import {createNotices} from './notices.mjs';
import {createResumable} from './resumable.mjs';
import {adminPage} from './admin_page.mts';
import {createCommunity} from './community.mts';
import {createExperience} from './experience.mts';
import {createVideoPosters} from './video_posters.mjs';
import {createContactPreferences} from './contact_preferences.mjs';
import {createPostShares} from './post_shares.mjs';
import {createGames} from './games.mjs';
import {createLiveRoulette} from './live_roulette.mjs';
import {createRoulette} from './roulette.mjs';
import {createHome,recordActivity} from './home.mjs';
import {createIdentity} from './identity.mjs';
import {createModeration} from './moderation.mjs';
import {createOperations} from './operations.mjs';
import {createAccountGuard} from './account_guard.mjs';
import {createAccountDeletion} from './account_deletion.mjs';
import {createPrivacy,policyVersion} from './privacy.mjs';
import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { createSocial } from './social.mjs';
import {createLives} from './lives.mjs';
import {createContentTools} from './content_tools.mjs';
import { createChat } from './chat.mjs';
import {createGroups} from './groups.mjs';
import {createPrivateMedia} from './chat_extras.mjs';
import {createAvatars,avatarJoins,avatarColumns,avatarFields} from './avatars.mjs';
import {createPush} from './push.mjs';
import {createCalls} from './calls.mjs';
import {createVoiceRooms} from './voice_rooms.mjs';
import {
  ApiError, digest, hashPassword, verifyPassword, newToken, newRecoveryCode,
  normalizeRecoveryCode, validateUsername, validatePassword, validateProfile, isUniqueConflict,
} from './security.mjs';

const sessionSeen = new Map();
const sessionLifetime = 30 * 24 * 60 * 60 * 1000;
const nowText = () => new Date().toISOString();

async function readJson(request, maximum = 16384) {
  if (!/^application\/json(?:\s*;|$)/i.test(request.headers['content-type'] || '')) {
    throw new ApiError(415, 'CONTENT_TYPE', 'صيغة الطلب غير مدعومة.');
  }
  const declared=request.headers['content-length'];
  if(declared && (!/^\d+$/.test(declared)||Number(declared)>maximum))throw new ApiError(413,'TOO_LARGE','الطلب أكبر من المسموح.');
  if(request.headers['content-encoding'] && request.headers['content-encoding']!=='identity')throw new ApiError(415,'CONTENT_ENCODING','ترميز الطلب غير مدعوم.');
  let size = 0;
  const chunks = [];
  for await (const chunk of request) {
    size += chunk.length;
    if (size > maximum) throw new ApiError(413, 'TOO_LARGE', 'الطلب أكبر من المسموح.');
    chunks.push(chunk);
  }
  try {
    const value = validateJsonShape(JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks))));
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
 (SELECT MAX(s.expires_at) FROM tomi_stories s WHERE s.user_id=u.id AND s.expires_at>'1970-01-01T00:00:00.000Z') AS story_expires_at,
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
    storyExpiresAt: row.story_expires_at, hasStory: !!row.story_expires_at && row.story_expires_at>nowText(),
    postsCount: Number(row.posts_count), isFollowing: Number(row.is_following) > 0,
  };
}

export async function createApp({ database, trustProxy = false, origins = [], rateLimitMultiplier = 1, mfaEncryptionKey=null, requireAdminMfa=false, edgeSecret=null, firebaseVerifier=null, storage = null, chatStorage = storage, pushSender=null, pushAutoFlush=true, iceProvider=null, callAutoSweep=true, roomProvider=null, liveProvider=null, liveClock, liveAutoTick=true, roomAutoSweep=true,ownerUserId=null,deletionAutoSweep=true,deletionClock,privacyConfig,liveRouletteClock,liveRouletteAutoTick=true,gamesClock,gamesAutoTick=true }) {
  if(requireAdminMfa&&!mfaEncryptionKey)throw Error('TOMI_REQUIRE_ADMIN_MFA requires TOMI_MFA_KEY');
  const requestGuard=createAccountGuard(database);database=requestGuard.database;
  if(ownerUserId){
    if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(ownerUserId))throw Error('Invalid TOMI_OWNER_USER_ID');
    const configured=(await database.query('SELECT u.id,COALESCE(a.suspended,0) suspended FROM tomi_users u LEFT JOIN tomi_account_restrictions a ON a.user_id=u.id WHERE u.id=?',[ownerUserId])).rows[0];
    if(!configured||Number(configured.suspended))throw Error('TOMI_OWNER_USER_ID must identify an existing active account');
  }
  // Equal-cost verification for unknown users avoids a cheap username timing oracle.
  const dummyHash = await hashPassword(newToken());
  const userById = async (id, viewer, db = database) => {
    const result = await db.query(`${userSelect} WHERE u.id = ?`, [viewer, id]);
    if (!result.rows[0]) throw new ApiError(404, 'NOT_FOUND', 'الحساب غير موجود.');
    return publicUser(result.rows[0],storage);
  };
  const usersByIds=async(ids,viewer,db=database)=>{
    if(!ids.length)return new Map();
    const result=await db.query(`${userSelect} WHERE u.id IN (${ids.map(()=>'?').join(',')})`,[viewer,...ids]);
    return new Map(result.rows.map(row=>[row.id,publicUser(row,storage)]));
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
    await moderation.active(database,result.rows[0].user_id);
    if ((sessionSeen.get(tokenHash)??0)<Date.now()-60000) {await database.query('UPDATE tomi_session_devices SET last_seen_at=? WHERE session_hash=?',[nowText(),tokenHash]);sessionSeen.set(tokenHash,Date.now());if(sessionSeen.size>5000)sessionSeen.delete(sessionSeen.keys().next().value);}
    return { id: result.rows[0].user_id, tokenHash };
  }

  async function grant(db, userId, version) {
    const token = newToken();
    const created = nowText();
    const expires = new Date(Date.now() + sessionLifetime).toISOString();
    await db.query(`INSERT INTO tomi_sessions (token_hash, user_id, auth_version, created_at, expires_at)
      VALUES (?, ?, ?, ?, ?)`, [digest(token), userId, version, created, expires]);
    const sessionId=randomUUID();
    await db.query('INSERT INTO tomi_session_devices(id,session_hash,user_id,label,platform,last_seen_at) VALUES(?,?,?,?,?,?)',[sessionId,digest(token),userId,'جهاز TOMI','unknown',created]);
    return { token, expiresAt: expires,sessionId };
  }

  const videoPosters=createVideoPosters({database,readJson,respond:json,limit});
  const contactPreferences=createContactPreferences({database,readJson,respond:json,limit});
  const identity=createIdentity({database,readJson,respond:json,limit,userById,usersByIds});
  const home=createHome({database,storage,accountGate:requestGuard.gate,readJson,respond:json,limit,userById});
  const social = createSocial({database, storage, readJson, respond: json, limit, userById, cleanupPrefix:chatStorage===storage?'tomi/':'tomi/posts/',accountGate:requestGuard.gate});
  const chatMedia=chatStorage===storage?null:createSocial({database,storage:chatStorage,readJson,respond:json,limit,userById,cleanupPrefix:'tomi/chat-images/'});
  const avatars=createAvatars({database,storage,readJson,respond:json,limit,userById});
  const avatarMedia=chatStorage===storage?null:createSocial({database,storage,readJson,respond:json,limit,userById,cleanupPrefix:'tomi/avatars/'});
  const push=createPush({database,sender:pushSender,autoFlush:pushAutoFlush,readJson,respond:json,limit});
  const privateMedia=createPrivateMedia({database,storage:chatStorage});
  const groups=createGroups({database,storage:chatStorage,avatarStorage:storage,media:privateMedia,readJson,respond:json,limit,accountGate:requestGuard.gate,emit:(...args)=>chat.emit(...args),enqueuePush:push.enqueueGroup});
  const chat=createChat({groups,privateMedia,database,storage:chatStorage,avatarStorage:storage,readJson,respond:json,limit,userById,enqueuePush:push.enqueue,accountGate:requestGuard.gate,shareRequestCount:uid=>postShares.pendingCount(uid)});
  const postShares=createPostShares({database,readJson,respond:json,limit,userById,usersByIds,accountGate:requestGuard.gate,chat,social});
  const rooms=createVoiceRooms({database,provider:roomProvider,storage,readJson,respond:json,limit,usersByIds,autoSweep:roomAutoSweep,emit:chat.emit});
  const lives=createLives({database,provider:liveProvider,readJson,respond:json,limit,usersByIds,clock:liveClock,autoTick:liveAutoTick,emit:chat.emit});
  const contentTools=createContentTools({database,accountGate:requestGuard.gate,readJson,respond:json,limit,social,emit:chat.emit});
  const calls=createCalls({database,iceProvider,readJson,respond:json,limit,userById,emit:chat.emit,enqueuePush:push.enqueueCall,autoSweep:callAutoSweep});
  const operations=createOperations();
  const experience=createExperience({database,readJson,respond:json,limit,usersByIds,getPost:social.getPost,invalidateSession:chat.invalidateSession,afterRevoke:()=>requestGuard.unbound(async()=>{await calls.sweep();await rooms.sweep();})});
  const moderation=createModeration({database,ownerUserId,storage,readJson,respond:json,limit,userById,usersByIds,rooms,calls,chat,operations,accountGate:requestGuard.gate});
  const roulette=createRoulette({database,ownerUserId,readJson,respond:json,limit,accountGate:requestGuard.gate});
  const liveRoulette=createLiveRoulette({database,ownerUserId,readJson,respond:json,limit,usersByIds,emit:chat.emit,clock:liveRouletteClock,autoTick:liveRouletteAutoTick,unbound:requestGuard.unbound});
  const games=createGames({database,readJson,respond:json,limit,usersByIds,emit:chat.emit,accountGate:requestGuard.gate,clock:gamesClock,autoTick:gamesAutoTick,unbound:requestGuard.unbound});
  const deletion=createAccountDeletion({database,guard:requestGuard,ownerUserId,storage,chatStorage,readJson,respond:json,limit,session,rooms,calls,chat,dummyHash,confirmCredential:(row,d)=>external.confirm({id:row.id},{password:d.password,identityToken:d.identityToken},{skipMfa:true}),authorizeSecurity:async(row,d,current)=>{if(current)await mfa.guard(current);else {await mfa.loginAttempt(row.id,d.mfaCode);await database.transaction(db=>mfa.verifyLogin(db,row.id,d.mfaCode));}},autoSweep:deletionAutoSweep,clock:deletionClock});
  const privacy=createPrivacy(privacyConfig);
  const resumable=createResumable({database,storage,chatStorage,readJson,respond:json,limit});
  const contentPreferences=createContentPreferences({database,readJson,respond:json,limit});
  const notices=createNotices({database,readJson,respond:json,limit});
  const community=createCommunity({database,readJson,respond:json,limit,role:moderation.role,configured:{calls:!!iceProvider,rooms:!!roomProvider,live:!!liveProvider,media:!!storage}});
  const mfa=createMfa({database,readJson,respond:json,limit,key:mfaEncryptionKey,emit:chat.emit,invalidateSession:chat.invalidateSession,afterRevoke:()=>requestGuard.unbound(async()=>{await calls.sweep();await rooms.sweep();}),confirmCredential:(c,d,db)=>external.confirm(c,d,{db,skipMfa:true})});
  const external=createFederatedAuth({database,verifier:firebaseVerifier,readJson,respond:json,limit,grant,userById,mfa,active:moderation.active,emit:chat.emit});
  const e2ee=createE2ee({database,readJson,respond:json,limit,chat,storage:chatStorage,accountGate:requestGuard.gate,mfa,confirmCredential:external.confirm});
  const server = createServer(async (request, response) => {
    response.setHeader('x-frame-options','DENY');
    response.setHeader('strict-transport-security','max-age=31536000');
    response.setHeader('permissions-policy','camera=(), microphone=(), geolocation=()');
    operations.track(request,response);
    try {
      if(request.url!=='/health'&&request.url!=='/')verifyEdge(request,edgeSecret);
      const origin = request.headers.origin;
      if (origin && !origins.includes(origin)&&!privacy.sameOrigin(request,origin)) throw new ApiError(403, 'ORIGIN', 'مصدر الطلب غير مسموح.');
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
      const ip=clientIp(request,trustProxy,edgeSecret);
      if(await adminPage(request,response,url))return;
      if(privacy.handle(request,response,url))return;
      if (method === 'GET' && (path === '/health' || path === '/')) {
        await database.query('SELECT 1 AS ready');
        json(response, 200, { status: 'ok', service: 'TOMI API', version: '1.7.0-beta.1', features: { phoneNotifications: push.configured, voiceRooms: !!roomProvider, phoneCalls: !!iceProvider, liveBroadcasts: !!liveProvider, realPayments: false } });
        return;
      }

      if(await external.handlePublic(request,response,url,ip))return;
      if (method === 'POST' && path === '/v1/auth/register') {
        await limit(`register:ip:${ip}`, 5, 3600000);
        const data = await readJson(request);
        if(data.policyVersion!==undefined&&data.policyVersion!==policyVersion)throw new ApiError(400,'POLICY_CHANGED','راجع نسخة الشروط والخصوصية الحالية قبل إنشاء الحساب.');
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
            if(data.policyVersion===policyVersion)await db.query('INSERT INTO tomi_policy_acceptances(user_id,policy_version,accepted_at) VALUES(?,?,?)',[id,policyVersion,created]);
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
        await limit(`login:pair:${ip}:${username}`, 10, 900000);
        const password = typeof data.password === 'string' && [...data.password].length <= 128 ? data.password : '';
        const { rows } = await database.query('SELECT id, password_hash, auth_version FROM tomi_users WHERE username = ?', [username]);
        const row = rows[0];
        const matches = await verifyPassword(password, row?.password_hash || dummyHash);
        if (!row || !matches) {await limit(`login:failed:${username}`,100,900000);throw new ApiError(401, 'BAD_CREDENTIALS', 'اليوزر أو كلمة المرور غير صحيحة.');}
        await mfa.loginAttempt(row.id,data.mfaCode);
        const result = await database.transaction(async db=>{
          const fresh=(await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING auth_version',[row.id])).rows[0];
          if(Number(fresh.auth_version)!==Number(row.auth_version))throw new ApiError(401,'BAD_CREDENTIALS','تغيّرت بيانات الدخول؛ حاول مرة ثانية.');
          await moderation.active(db,row.id);
          const verified=await mfa.verifyLogin(db,row.id,data.mfaCode);const grantResult=await grant(db,row.id,fresh.auth_version);if(verified)await mfa.mark(db,digest(grantResult.token));await mfa.event(db,row.id,'login');return {...grantResult,user:await userById(row.id,row.id,db)};
        });
        chat.emit([row.id],{type:'security.new-login',sessionId:result.sessionId,at:nowText()});
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
        await mfa.loginAttempt(row.id,data.mfaCode);
        const passwordHash = await hashPassword(password);
        const recoveryCode = newRecoveryCode();
        const result = await database.transaction(async (db) => {
          await mfa.verifyLogin(db,row.id,data.mfaCode);
          const updated = await db.query(`UPDATE tomi_users SET password_hash = ?, recovery_hash = ?,
            auth_version = auth_version + 1, updated_at = ? WHERE id = ? AND recovery_hash = ?`,
            [passwordHash, digest(normalizeRecoveryCode(recoveryCode)), nowText(), row.id, digest(code)]);
          if (updated.changes !== 1) throw new ApiError(400, 'BAD_RECOVERY', 'رمز الاسترجاع استُخدم؛ استخدم الرمز الجديد.');
          await moderation.active(db,row.id);
          await db.query('DELETE FROM tomi_sessions WHERE user_id = ?', [row.id]);
          await mfa.event(db,row.id,'account_recovered');
          return { ...(await grant(db, row.id, row.auth_version + 1)),
            user: await userById(row.id, row.id, db), recoveryCode };
        });
        chat.invalidateUser(row.id);
        await calls.sweep();
        await rooms.sweep();
        json(response, 200, result);
        return;
      }

      if(await deletion.handle(request,response,url,{ip}))return;
      const current = await session(request);
      await requestGuard.run(current,async()=>{
      if(await mfa.handle(request,response,url,current))return;
      if(await external.handle(request,response,url,current))return;
      if((method==='DELETE'&&/^\/v1\/me\/sessions\//.test(path))||path==='/v1/me/sessions/revoke-others')await mfa.guard(current);
      if(path.startsWith('/v1/admin/')||path==='/v1/admin') {const staffRole=await moderation.role(database,current.id);if(staffRole!=='member')await mfa.guard(current,{required:requireAdminMfa});}
      if(await resumable.handle(request,response,url,current))return;
      if(await contentPreferences.handle(request,response,url,current))return;
      if(await notices.handle(request,response,url,current))return;
      if(await community.handle(request,response,url,current))return;
      if(await experience.handle(request,response,url,current))return;
      if(await videoPosters.handle(request,response,url,current))return;
      if(await contactPreferences.handle(request,response,url,current))return;
      if(await moderation.handle(request,response,url,current))return;
      await limit(`requests:user:${current.id}`, 300);
      if(await e2ee.handle(request,response,url,current))return;
      if(await liveRoulette.handle(request,response,url,current))return;
      if(await games.handle(request,response,url,current))return;
      if(await roulette.handle(request,response,url,current))return;
      if(await identity.handle(request,response,url,current))return;
      if (await rooms.handle(request,response,url,current)) return;
      if (await calls.handle(request,response,url,current)) return;
      if (await avatars.handle(request,response,url,current)) return;
      if (await push.handle(request,response,url,current)) return;
      if (await groups.handle(request,response,url,current)) return;
      if(await postShares.handle(request,response,url,current))return;
      if (await lives.handle(request,response,url,current)) return;
      if (await contentTools.handle(request,response,url,current)) return;
      if (await chat.handle(request,response,url,current)) return;
      if (await home.handle(request,response,url,current)) return;
      if (await social.handle(request,response,url,current)) return;

      if (method === 'POST' && path === '/v1/auth/logout') {
        await database.transaction(async db=>{
          await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING id',[current.id]);
          await db.query('DELETE FROM tomi_sessions WHERE token_hash = ?', [current.tokenHash]);
        });
        chat.invalidateSession(current.tokenHash);
        await requestGuard.unbound(async()=>{await calls.invalidateSession(current.tokenHash);await rooms.invalidateSession(current.tokenHash);});
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
          await database.transaction(async db => {
            const {rows} = await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING avatar_preset', [current.id]);
            if (rows[0].avatar_preset !== profile.avatarPreset) {
              await db.query("UPDATE tomi_user_identity SET portrait_id='none',revision=revision+1 WHERE user_id=? AND portrait_id<>'none'", [current.id]);
            }
            await db.query(`UPDATE tomi_users SET username = ?, display_name = ?, bio = ?, avatar_preset = ?,
              updated_at = ? WHERE id = ?`, [profile.username, profile.name, profile.bio, profile.avatarPreset, nowText(), current.id]);
          });
        } catch (error) {
          if (isUniqueConflict(error)) throw new ApiError(409, 'USERNAME_TAKEN', 'هذا اليوزر مستخدم؛ اختَر غيره.', 'username');
          throw error;
        }
        json(response, 200, { user: await userById(current.id, current.id) });
        return;
      }

      if (method === 'POST' && path === '/v1/auth/password') {
        await mfa.guard(current);
        await limit(`password:user:${current.id}`, 5, 900000);
        const data = await readJson(request);
        const newPassword = validatePassword(data.newPassword);
        const oldPassword = typeof data.currentPassword === 'string' && [...data.currentPassword].length <= 128 ? data.currentPassword : '';
        const { rows } = await database.query('SELECT password_hash, auth_version FROM tomi_users WHERE id = ?', [current.id]);
        const row = rows[0];
        await external.confirm(current,{password:oldPassword,identityToken:data.identityToken});
        const passwordHash = await hashPassword(newPassword);
        const recoveryCode = newRecoveryCode();
        const result = await database.transaction(async (db) => {
          const changed = await db.query(`UPDATE tomi_users SET password_hash = ?, recovery_hash = ?,
            auth_version = auth_version + 1, updated_at = ? WHERE id = ? AND auth_version = ?`,
            [passwordHash, digest(normalizeRecoveryCode(recoveryCode)), nowText(), current.id, row.auth_version]);
          if (changed.changes !== 1) throw new ApiError(409, 'RETRY', 'الحساب تغيّر؛ سجّل دخولك مرة ثانية.');
          await db.query('DELETE FROM tomi_sessions WHERE user_id = ?', [current.id]);
          await mfa.event(db,current.id,'password_changed');await db.query('INSERT INTO tomi_account_auth(user_id,password_enabled) VALUES(?,1) ON CONFLICT(user_id) DO UPDATE SET password_enabled=1',[current.id]);
          return { ...(await grant(db, current.id, row.auth_version + 1)),
            user: await userById(current.id, current.id, db), recoveryCode };
        });
        chat.invalidateUser(current.id);
        await requestGuard.unbound(async()=>{await calls.sweep();await rooms.sweep();});
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
          AND u.id <> ? AND NOT EXISTS(SELECT 1 FROM tomi_account_restrictions a WHERE a.user_id=u.id AND a.suspended=1) ORDER BY u.username LIMIT 20`, [current.id, pattern, pattern, current.id]);
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
          await requestGuard.gate(db,target);
          if((await db.query('SELECT 1 FROM tomi_deleted_accounts WHERE user_id=?',[target])).rows.length)throw new ApiError(410,'ACCOUNT_DELETED','حُذف الحساب ولا يمكن متابعته.');
          await userById(target, current.id, db);
          if (data.follow) {
            const inserted=await db.query(`INSERT INTO tomi_follows (follower_id, following_id, created_at)
              VALUES (?, ?, ?) ON CONFLICT (follower_id, following_id) DO NOTHING RETURNING follower_id`, [current.id, target, nowText()]);
            if(inserted.rows.length)await recordActivity(db,{recipientId:target,actorId:current.id,kind:'follow',targetId:current.id,sourceKey:'follow:'+current.id+':'+target},requestGuard.gate);
          } else {
            await db.query('DELETE FROM tomi_follows WHERE follower_id = ? AND following_id = ?', [current.id, target]);
          }
          return { user: await userById(target, current.id, db), me: await userById(current.id, current.id, db) };
        });
        json(response, 200, result);
        return;
      }
      throw new ApiError(404, 'NOT_FOUND', 'المسار غير موجود.');
      });
    } catch (error) {
      if (response.headersSent) { response.destroy(); return; }
      if (error instanceof ApiError) {
        if([400,413,415].includes(error.status)&&!request.complete)response.setHeader('connection','close');
        json(response, error.status, { error: { code: error.code, message: error.message,
          ...(error.field ? { field: error.field } : {}) } }, error.status === 429 ? { 'retry-after': '60' } : {});
      } else {
        // Never log request bodies, authorization headers, database URLs or profile data.
        console.error('Request failed:', error.code || error.name);
        json(response, 503, { error: { code: 'UNAVAILABLE', message: 'الخدمة غير متاحة حاليًا؛ جرّب مرة ثانية.' } });
      }
    }
  });
  server.cleanupMedia = async()=>{await e2ee.cleanup();await home.cleanup();await social.cleanup();if(chatMedia)await chatMedia.cleanup();if(avatarMedia)await avatarMedia.cleanup();await chat.cleanup();await push.cleanup();await calls.cleanup();};
  server.flushPush=push.flush;
  server.sweepLiveRoulette=()=>requestGuard.unbound(liveRoulette.advance);
  server.sweepGames=()=>requestGuard.unbound(games.sweep);
  server.sweepDeletions=deletion.sweep;
  server.sweepCalls=calls.sweep;
  server.sweepRooms=rooms.sweep;server.flushRooms=rooms.flush;
  server.on('close',()=>{lives.close();games.close();liveRoulette.close();push.close();calls.close();rooms.close();operations.close();deletion.close();});
  chat.attach(server,{origins,edgeSecret,clientIp:req=>clientIp(req,trustProxy,edgeSecret),authenticate:token=>session({headers:{authorization:'Bearer '+token}}),validSessions:async hashes=>{
    if(!hashes.length)return new Set();
    const{rows}=await database.query(`SELECT s.token_hash FROM tomi_sessions s JOIN tomi_users u ON u.id=s.user_id AND u.auth_version=s.auth_version WHERE s.expires_at>? AND s.token_hash IN (${hashes.map(()=>'?').join(',')})`,[nowText(),...hashes]);return new Set(rows.map(r=>r.token_hash));
  }});
  server.maxHeadersCount = 64;
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  server.keepAliveTimeout = 5000;
  server.maxRequestsPerSocket = 100;
  return server;
}
