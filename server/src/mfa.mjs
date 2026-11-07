import {createHmac,randomBytes,randomUUID,timingSafeEqual,createCipheriv,createDecipheriv} from 'node:crypto';
import {ApiError,digest,verifyPassword} from './security.mjs';
const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
export function base32(bytes){let bits=0,value=0,out='';for(const b of bytes){value=(value<<8)|b;bits+=8;while(bits>=5){out+=alphabet[(value>>>(bits-5))&31];bits-=5;}}if(bits)out+=alphabet[(value<<(5-bits))&31];return out;}
export function decode32(text){let bits=0,value=0,out=[];for(const c of text){const n=alphabet.indexOf(c);if(n<0)throw Error('Invalid TOTP secret');value=(value<<5)|n;bits+=5;if(bits>=8){out.push((value>>>(bits-8))&255);bits-=8;}}return Buffer.from(out);}
export function totp(secret,step,{digits=6,algorithm='sha1'}={}){const counter=Buffer.alloc(8);counter.writeBigUInt64BE(BigInt(step));const hash=createHmac(algorithm,decode32(secret)).update(counter).digest(),offset=hash.at(-1)&15;return ((hash.readUInt32BE(offset)&0x7fffffff)%10**digits).toString().padStart(digits,'0');}
export function mfaKey(value){if(!value)return null;const b=Buffer.from(value,'base64');if(b.length!==32||b.toString('base64')!==value)throw Error('TOMI_MFA_KEY must be 32 random base64 bytes');return b;}
export function seal(secret,key,user){const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key,iv);cipher.setAAD(Buffer.from(user));return Buffer.concat([iv,cipher.update(secret),cipher.final(),cipher.getAuthTag()]).toString('base64');}
export function unseal(value,key,user){if(!key)throw new ApiError(503,'MFA_UNAVAILABLE','خدمة التحقق بخطوتين تحتاج إعداد الخادم.');const b=Buffer.from(value,'base64'),d=createDecipheriv('aes-256-gcm',key,b.subarray(0,12));d.setAAD(Buffer.from(user));d.setAuthTag(b.subarray(-16));return Buffer.concat([d.update(b.subarray(12,-16)),d.final()]).toString();}
const fail=()=>{throw new ApiError(401,'MFA_REQUIRED','أدخل رمز تطبيق المصادقة أو أحد رموز الاحتياط.');};
export function createMfa({database,readJson,respond,limit,key=null,clock=Date.now,emit=()=>{},invalidateSession=()=>{},afterRevoke=async()=>{},confirmCredential=null}){
 const now=()=>new Date(clock()).toISOString();
 async function event(db,user,kind){await db.query('INSERT INTO tomi_security_events(id,user_id,kind,created_at) VALUES(?,?,?,?)',[randomUUID(),user,kind,now()]);}
 async function check(db,user,code,row){
  if(typeof code!=='string')fail();
  if(/^[A-F0-9]{16}$/.test(code.replaceAll('-','').toUpperCase())){
   const result=await db.query('DELETE FROM tomi_mfa_recovery WHERE user_id=? AND code_hash=? RETURNING code_hash',[user,digest(code.replaceAll('-','').toUpperCase())]);if(result.rows.length)return;fail();
  }
  if(!/^\d{6}$/.test(code))fail();
  const secret=unseal(row.secret,key,user),step=Math.floor(clock()/30000);
  for(const s of [step-1,step,step+1]){
   if(s<=Number(row.last_step))continue;
   if(timingSafeEqual(Buffer.from(totp(secret,s)),Buffer.from(code))){const result=await db.query('UPDATE tomi_mfa SET last_step=? WHERE user_id=? AND last_step<? RETURNING user_id',[s,user,s]);if(result.rows.length)return;}
  }fail();
 }
 async function loginAttempt(user,code){
  if(!(await database.query('SELECT 1 FROM tomi_mfa WHERE user_id=? AND enabled=1',[user])).rows.length)return;
  const normalized=typeof code==='string'?code.replaceAll('-','').toUpperCase():'';
  if(/^[A-F0-9]{16}$/.test(normalized)&&(await database.query('SELECT 1 FROM tomi_mfa_recovery WHERE user_id=? AND code_hash=?',[user,digest(normalized)])).rows.length)return;
  await limit('mfa-login:'+user,10,300000);
 }
 async function verifyLogin(db,user,code){const row=(await db.query('SELECT * FROM tomi_mfa WHERE user_id=? AND enabled=1',[user])).rows[0];if(!row)return false;await check(db,user,code,row);return true;}
 async function password(db,user,value){const row=(await db.query('SELECT password_hash FROM tomi_users WHERE id=?',[user])).rows[0];if(typeof value!=='string'||value.length>512||!await verifyPassword(value,row?.password_hash??''))throw new ApiError(400,'BAD_CREDENTIALS','كلمة المرور غير صحيحة.');}
 async function recent(current){const row=(await database.query('SELECT verified_at FROM tomi_mfa_sessions WHERE session_hash=?',[current.tokenHash])).rows[0];return !!row&&Date.parse(row.verified_at)>clock()-15*60000;}
 async function mark(db,hash){await db.query('INSERT INTO tomi_mfa_sessions(session_hash,verified_at) VALUES(?,?) ON CONFLICT(session_hash) DO UPDATE SET verified_at=excluded.verified_at',[hash,now()]);}
 async function guard(current,{required=false}={}){const enabled=(await database.query('SELECT enabled FROM tomi_mfa WHERE user_id=?',[current.id])).rows[0]?.enabled;if(!Number(enabled)){if(required)throw new ApiError(403,'MFA_ENROLL_REQUIRED','فعّل التحقق بخطوتين من الأجهزة وأمان الحساب قبل استخدام الإدارة.');return;}if(!await recent(current))throw new ApiError(403,'MFA_STEP_UP','أكد رمز المصادقة من الأجهزة وأمان الحساب قبل الإجراء.');}
 async function handle(req,res,url,c){const path=url.pathname;if(!path.startsWith('/v1/me/security'))return false;
  if(req.method==='GET'&&path==='/v1/me/security'){const row=(await database.query('SELECT enabled FROM tomi_mfa WHERE user_id=?',[c.id])).rows[0];respond(res,200,{available:!!key,enabled:!!Number(row?.enabled),recent:await recent(c),events:(await database.query('SELECT id,kind,created_at FROM tomi_security_events WHERE user_id=? ORDER BY created_at DESC,id DESC LIMIT 50',[c.id])).rows});return true;}
  if(req.method!=='POST')return false;
  if(!['setup','enable','verify','disable'].some(x=>path==='/v1/me/security/'+x))return false;
  await limit('mfa:'+c.id,8,60000);const d=await readJson(req);
  let revoked=[];let payload;try{payload=await database.transaction(async db=>{
   // Serialize enrollment, verification and disable across PostgreSQL workers.
   await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING id',[c.id]);
   const row=(await db.query('SELECT * FROM tomi_mfa WHERE user_id=?',[c.id])).rows[0];
   if(path.endsWith('/setup')){
    if(!key)throw new ApiError(503,'MFA_UNAVAILABLE','إعداد مفتاح المصادقة بالخادم مطلوب أولاً.');if(confirmCredential)await confirmCredential(c,d,db);else await password(db,c.id,d.password);
    if(Number(row?.enabled))throw new ApiError(409,'MFA_ENABLED','المصادقة مفعّلة مسبقاً.');
    const secret=base32(randomBytes(20));await db.query('INSERT INTO tomi_mfa(user_id,secret,enabled,last_step,pending_until) VALUES(?,?,0,-1,?) ON CONFLICT(user_id) DO UPDATE SET secret=excluded.secret,last_step=-1,pending_until=excluded.pending_until',[c.id,seal(secret,key,c.id),new Date(clock()+10*60000).toISOString()]);
    return {secret,uri:'otpauth://totp/TOMI:'+c.id+'?secret='+secret+'&issuer=TOMI&algorithm=SHA1&digits=6&period=30'};
   }
   if(!row)fail();
   if(path.endsWith('/enable')){
    if(Number(row.enabled)||row.pending_until<now())throw new ApiError(409,'MFA_SETUP_EXPIRED','أعد بدء إعداد المصادقة.');await check(db,c.id,d.code,row);
    await db.query('UPDATE tomi_mfa SET enabled=1 WHERE user_id=?',[c.id]);const codes=Array.from({length:10},()=>randomBytes(8).toString('hex').toUpperCase());
    await db.query('DELETE FROM tomi_mfa_recovery WHERE user_id=?',[c.id]);for(const code of codes)await db.query('INSERT INTO tomi_mfa_recovery(user_id,code_hash) VALUES(?,?)',[c.id,digest(code)]);
    revoked=(await db.query('DELETE FROM tomi_sessions WHERE user_id=? AND token_hash<>? RETURNING token_hash',[c.id,c.tokenHash])).rows;await mark(db,c.tokenHash);await event(db,c.id,'mfa_enabled');return {enabled:true,recoveryCodes:codes};
   }
   if(!Number(row.enabled))fail();
   if(path.endsWith('/disable'))if(confirmCredential)await confirmCredential(c,d,db);else await password(db,c.id,d.password);
   await check(db,c.id,d.code,row);
   if(path.endsWith('/disable')){await db.query('DELETE FROM tomi_mfa WHERE user_id=?',[c.id]);await db.query('DELETE FROM tomi_mfa_sessions WHERE session_hash IN(SELECT token_hash FROM tomi_sessions WHERE user_id=?)',[c.id]);await event(db,c.id,'mfa_disabled');revoked=(await db.query('DELETE FROM tomi_sessions WHERE user_id=? AND token_hash<>? RETURNING token_hash',[c.id,c.tokenHash])).rows;}
   else {await mark(db,c.tokenHash);await event(db,c.id,'mfa_verified');}
   return {ok:true};
  });}catch(error){if(error instanceof ApiError&&error.code==='MFA_REQUIRED')throw new ApiError(400,'MFA_INVALID','رمز المصادقة غير صحيح أو استُخدم؛ جرّب رمزاً جديداً.');throw error;}for(const row of revoked)invalidateSession(row.token_hash);if(revoked.length)await afterRevoke();respond(res,200,payload);emit([c.id],{type:'security.updated'});return true;
 }
 return {handle,guard,loginAttempt,verifyLogin,mark,event};
}
