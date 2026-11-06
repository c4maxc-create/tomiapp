import {ApiError} from './security.mjs';
import {recordNotice} from './notices.mjs';
const fail=(code,message)=>{throw new ApiError(403,code,message);};
export async function contentAllowed(db,recipient,actor,kind,gate=async()=>{}){
 if(recipient===actor)return true;
 await gate(db,recipient);
 if((await db.query('SELECT 1 FROM tomi_deleted_accounts WHERE user_id=?',[recipient])).rows.length)return false;
 if((await db.query('SELECT 1 FROM tomi_user_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)',[recipient,actor,actor,recipient])).rows.length)return false;
 const row=(await db.query('SELECT * FROM tomi_content_preferences WHERE user_id=?',[recipient])).rows[0],policy=row?.[kind]??'everyone';
 if(policy==='everyone')return true;if(policy==='nobody')return false;
 return (await db.query('SELECT 1 FROM tomi_follows WHERE follower_id=? AND following_id=?',[recipient,actor])).rows.length>0;
}
export async function allowComment(db,owner,actor,text,gate){
 if(!await contentAllowed(db,owner,actor,'comments',gate))fail('COMMENTS_RESTRICTED','إعدادات صاحب المنشور لا تسمح بهذا التعليق.');
 if(owner===actor)return;
 const row=(await db.query('SELECT words FROM tomi_content_preferences WHERE user_id=?',[owner])).rows[0],words=JSON.parse(row?.words??'[]'),value=text.normalize('NFKC').toLowerCase();
 if(words.some(word=>value.includes(word.normalize('NFKC').toLowerCase())))fail('CONTENT_FILTER','التعليق يحتوي كلمة يستبعدها صاحب المنشور؛ عدّل النص.');
}
export async function recordMentions(db,{actor,text,kind,targetId,sourceKey=kind+':'+targetId,audience='public',gate=async()=>{}}){
 const names=[...new Set([...text.matchAll(/(?:^|[^a-zA-Z0-9_@])@([a-zA-Z0-9_]{3,20})(?![a-zA-Z0-9_])/g)].map(m=>m[1].toLowerCase()))];
 if(names.length>10)throw new ApiError(400,'MENTION_LIMIT','يمكن الإشارة إلى10 أشخاص في النص.');
 for(const name of names){const row=(await db.query('SELECT id FROM tomi_users WHERE username=?',[name])).rows[0];if(!row||row.id===actor)continue;
  if(!await contentAllowed(db,row.id,actor,'mentions',gate))fail('MENTIONS_RESTRICTED','أحد الأشخاص لا يسمح بهذه الإشارة؛ احذف اليوزر من النص.');
  if(kind==='mention_story'&&audience==='followers'&&!(await db.query('SELECT 1 FROM tomi_follows WHERE follower_id=? AND following_id=?',[row.id,actor])).rows.length)fail('MENTION_AUDIENCE','الشخص المذكور لا يتابعك ولا يستطيع مشاهدة ستوري المتابعين؛ راجع الجمهور أو الإشارة.');
  await recordNotice(db,{recipientId:row.id,actorId:actor,kind,targetId,sourceKey:sourceKey+':mention:'+row.id});
 }
}
export function createContentPreferences({database,readJson,respond,limit}){
 async function snapshot(id){const r=(await database.query('SELECT * FROM tomi_content_preferences WHERE user_id=?',[id])).rows[0];return {comments:r?.comments??'everyone',mentions:r?.mentions??'everyone',words:JSON.parse(r?.words??'[]')};}
 return {async handle(req,res,url,c){if(url.pathname!=='/v1/me/content-preferences')return false;if(req.method==='GET'){respond(res,200,await snapshot(c.id));return true;}if(req.method!=='PUT')return false;
  await limit('content-preferences:'+c.id,30);const d=await readJson(req);if(!d||Object.keys(d).length!==3||Object.keys(d).some(k=>!['comments','mentions','words'].includes(k))||!['everyone','following','nobody'].includes(d.comments)||!['everyone','following','nobody'].includes(d.mentions)||!Array.isArray(d.words)||d.words.length>30||d.words.some(v=>typeof v!=='string'||!v.trim()||[...v.trim()].length>40))throw new ApiError(400,'VALIDATION','راجع سياسات التعليقات والإشارات وقائمة الكلمات.');const words=[...new Set(d.words.map(w=>w.trim()))];await database.query('INSERT INTO tomi_content_preferences(user_id,comments,mentions,words) VALUES(?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET comments=excluded.comments,mentions=excluded.mentions,words=excluded.words',[c.id,d.comments,d.mentions,JSON.stringify(words)]);respond(res,200,await snapshot(c.id));return true;
 }};
}
