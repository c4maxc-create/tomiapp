import {policyVersion} from './privacy.mjs';
import {randomUUID,randomBytes} from 'node:crypto';
import {ApiError,digest,hashPassword,newToken,verifyPassword,isUniqueConflict} from './security.mjs';
const now=()=>new Date().toISOString();
export function createFederatedAuth({database,verifier,readJson,respond,limit,grant,userById,mfa,active,emit}){
 const unavailable=()=>{throw new ApiError(503,'IDENTITY_DISABLED','طرق الدخول الخارجية تحتاج تفعيل Firebase لدى الإدارة.');};
 async function proof(token){if(!verifier)unavailable();return verifier.verify(token);}
 async function hasPassword(uid,db=database){const r=(await db.query('SELECT password_enabled FROM tomi_account_auth WHERE user_id=?',[uid])).rows[0];return r?!!Number(r.password_enabled):true;}
 async function confirm(c,d,{db=database,skipMfa=false}={}){
  if(!skipMfa)await mfa.guard(c);
  if(await hasPassword(c.id,db)){const row=(await db.query('SELECT password_hash FROM tomi_users WHERE id=?',[c.id])).rows[0];if(typeof d.password!=='string'||d.password.length>512||!await verifyPassword(d.password,row?.password_hash??''))throw new ApiError(400,'BAD_PASSWORD','كلمة المرور الحالية غير صحيحة.');}
  else{const p=await proof(d.identityToken),r=(await db.query('SELECT user_id FROM tomi_external_identities WHERE project_id=? AND subject=?',[p.projectId,p.subject])).rows[0];if(r?.user_id!==c.id)throw new ApiError(403,'IDENTITY_MISMATCH','أكد طريقة الدخول المرتبطة بنفس حساب TOMI.');}
 }
 async function handlePublic(req,res,url,ip){
  if(url.pathname==='/v1/auth/providers'&&req.method==='GET'){respond(res,200,{projectId:verifier?.projectId??null,providers:verifier?.providers??[]});return true;}
  if(url.pathname!=='/v1/auth/federated'||req.method!=='POST')return false;
  await limit('external-login:'+ip,30,900000);const d=await readJson(req);if(Object.keys(d).some(k=>!['identityToken','mfaCode','policyVersion'].includes(k)))throw new ApiError(400,'VALIDATION','طلب الدخول غير صحيح.');const p=await proof(d.identityToken);await limit('external-subject:'+p.projectId+':'+p.subject,20,900000);
  // Hashing outside the transaction keeps lock duration bounded. No generated password is shown or enabled.
  const passwordHash=await hashPassword(newToken());let result;
  const execute=()=>database.transaction(async db=>{
   let row=(await db.query('SELECT user_id FROM tomi_external_identities WHERE project_id=? AND subject=?',[p.projectId,p.subject])).rows[0],uid=row?.user_id;
   if(!uid){uid=randomUUID();const username='u_'+randomBytes(7).toString('hex'),name=[...(p.displayName??'مستخدم TOMI').replace(/[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]/g,'').trim()].slice(0,30).join('');await db.query('INSERT INTO tomi_users(id,username,display_name,bio,avatar_preset,password_hash,recovery_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)',[uid,username,name.length>=2?name:'مستخدم TOMI','','initials',passwordHash,digest(newToken()),now(),now()]);await db.query('INSERT INTO tomi_account_auth(user_id,password_enabled) VALUES(?,0)',[uid]);if(d.policyVersion===policyVersion)await db.query('INSERT INTO tomi_policy_acceptances(user_id,policy_version,accepted_at) VALUES(?,?,?)',[uid,policyVersion,now()]);await db.query('INSERT INTO tomi_external_identities(project_id,subject,user_id,created_at) VALUES(?,?,?,?)',[p.projectId,p.subject,uid,now()]);}
   await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING id',[uid]);await active(db,uid);
   const version=Number((await db.query('SELECT auth_version FROM tomi_users WHERE id=?',[uid])).rows[0].auth_version);const verified=await mfa.verifyLogin(db,uid,d.mfaCode),g=await grant(db,uid,version);if(verified)await mfa.mark(db,digest(g.token));await mfa.event(db,uid,'external_login');return {...g,user:await userById(uid,uid,db)};
  });
  const prior=(await database.query('SELECT user_id FROM tomi_external_identities WHERE project_id=? AND subject=?',[p.projectId,p.subject])).rows[0];if(prior)await mfa.loginAttempt(prior.user_id,d.mfaCode);
  try{result=await execute();}catch(e){if(!isUniqueConflict(e))throw e;result=await execute();}emit([result.user.id],{type:'security.new-login',sessionId:result.sessionId,at:now()});respond(res,200,result);return true;
 }
 async function handle(req,res,url,c){
  if(url.pathname==='/v1/me/auth/methods'&&req.method==='GET'){await limit('auth-methods:'+c.id,90);const rows=(await database.query('SELECT project_id,created_at FROM tomi_external_identities WHERE user_id=?',[c.id])).rows;respond(res,200,{hasPassword:await hasPassword(c.id),externalLinked:rows.length>0,projectId:verifier?.projectId??null});return true;}
  if(url.pathname==='/v1/me/auth/confirm'&&req.method==='POST'){await limit('auth-confirm:'+c.id,5,900000);const d=await readJson(req);if(Object.keys(d).some(k=>!['password','identityToken'].includes(k)))throw new ApiError(400,'VALIDATION','طلب تأكيد غير صحيح.');await confirm(c,d);respond(res,200,{confirmed:true});return true;}
  if(url.pathname==='/v1/me/auth/link'&&req.method==='POST'){await limit('external-link:'+c.id,5,900000);const d=await readJson(req);if(Object.keys(d).some(k=>!['password','currentIdentityToken','identityToken'].includes(k)))throw new ApiError(400,'VALIDATION','طلب الربط غير صحيح.');await confirm(c,{password:d.password,identityToken:d.currentIdentityToken});const p=await proof(d.identityToken);await database.transaction(async db=>{await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING id',[c.id]);const old=(await db.query('SELECT user_id FROM tomi_external_identities WHERE project_id=? AND subject=?',[p.projectId,p.subject])).rows[0];if(old&&old.user_id!==c.id)throw new ApiError(409,'IDENTITY_ALREADY_LINKED','طريقة الدخول مرتبطة بحساب TOMI آخر؛ لن ندمج الحسابين تلقائياً.');await db.query('INSERT INTO tomi_external_identities(project_id,subject,user_id,created_at) VALUES(?,?,?,?) ON CONFLICT(project_id,subject) DO NOTHING',[p.projectId,p.subject,c.id,now()]);const linked=(await db.query('SELECT user_id FROM tomi_external_identities WHERE project_id=? AND subject=?',[p.projectId,p.subject])).rows[0];if(linked?.user_id!==c.id)throw new ApiError(409,'IDENTITY_ALREADY_LINKED','طريقة الدخول مرتبطة بحساب TOMI آخر؛ لن ندمج الحسابين تلقائياً.');await mfa.event(db,c.id,'identity_linked');});respond(res,200,{linked:true});return true;}
  return false;
 }
 return {confirm,hasPassword,handlePublic,handle};
}
