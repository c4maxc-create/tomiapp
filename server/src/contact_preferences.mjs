import {ApiError} from './security.mjs';
const kinds={messages:'messages',calls:'calls',roomInvites:'room_invites'};
export async function contactAllowed(db,recipient,sender,kind){
 if(recipient===sender)return true;
 if((await db.query('SELECT 1 FROM tomi_user_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)',[recipient,sender,sender,recipient])).rows.length)return false;
 const exception=(await db.query('SELECT allowed FROM tomi_contact_exceptions WHERE user_id=? AND target_id=? AND kind=?',[recipient,sender,kind])).rows[0];
 if(exception)return Number(exception.allowed)===1;
 const r=(await db.query('SELECT '+kinds[kind]+' AS policy FROM tomi_contact_preferences WHERE user_id=?',[recipient])).rows[0];
 if(!r||r.policy==='everyone')return true;
 if(r.policy==='nobody')return false;
 return (await db.query('SELECT 1 FROM tomi_follows WHERE follower_id=? AND following_id=?',[recipient,sender])).rows.length>0;
}
export async function requireContact(db,recipient,sender,kind){if(!await contactAllowed(db,recipient,sender,kind)){const blocked=(await db.query('SELECT 1 FROM tomi_user_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)',[recipient,sender,sender,recipient])).rows.length;throw new ApiError(403,blocked?'CHAT_BLOCKED':'CONTACT_RESTRICTED','إعدادات الخصوصية لدى هذا المستخدم لا تسمح بهذا التواصل.');}}
export function createContactPreferences({database,readJson,respond,limit}){
 const snapshot=async uid=>{const r=(await database.query('SELECT * FROM tomi_contact_preferences WHERE user_id=?',[uid])).rows[0];return {messages:r?.messages??'everyone',calls:r?.calls??'everyone',roomInvites:r?.room_invites??'everyone'};};
 return {async handle(req,res,url,current){
  if(url.pathname!=='/v1/me/contact-preferences')return false;
  if(req.method==='GET'){respond(res,200,{preferences:await snapshot(current.id)});return true;}
  if(req.method==='PUT'){await limit('contact-preferences:'+current.id,30);const d=await readJson(req);if(!d||Array.isArray(d)||Object.keys(d).length!==3||Object.entries(d).some(([k,v])=>!Object.hasOwn(kinds,k)||!['everyone','following','nobody'].includes(v)))throw new ApiError(400,'VALIDATION','اختَر من الجميع أو من تتابعهم أو لا أحد.');
   await database.query('INSERT INTO tomi_contact_preferences(user_id,messages,calls,room_invites) VALUES(?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET messages=excluded.messages,calls=excluded.calls,room_invites=excluded.room_invites',[current.id,d.messages,d.calls,d.roomInvites]);respond(res,200,{preferences:await snapshot(current.id)});return true;
  }return false;
 }};
}
