import {ApiError} from './security.mjs';
const fail=(status,code,text)=>{throw new ApiError(status,code,text);};
export const reactionEmojis=['❤️','😂','👍','😮','😢','🔥'];
export function createChatTools({database,thread,lock,sending,notify,id,fields,message,messageJson,messagesSql,threadJson,respond,readJson,limit}){
 async function enrich(rows,viewer){
  if(!rows.length)return [];
  const keys=rows.map(x=>x.id),slots=keys.map(()=>'?').join(',');
  const metas=(await database.query(`SELECT x.*,r.body AS reply_body,r.deleted_at AS reply_deleted,r.image_upload_id AS reply_image,u.display_name AS reply_author FROM tomi_chat_message_meta x LEFT JOIN tomi_chat_messages r ON r.id=x.reply_to_id LEFT JOIN tomi_users u ON u.id=r.sender_id WHERE x.message_id IN (${slots})`,keys)).rows;
  const reactions=(await database.query(`SELECT message_id,emoji,COUNT(*) AS total,MAX(CASE WHEN user_id=? THEN 1 ELSE 0 END) AS mine FROM tomi_chat_reactions WHERE message_id IN (${slots}) GROUP BY message_id,emoji ORDER BY emoji`,[viewer,...keys])).rows;
  const edits=(await database.query(`SELECT * FROM tomi_message_edits WHERE message_id IN (${slots})`,keys)).rows;
  const byId=new Map(metas.map(x=>[x.message_id,x]));
  return rows.map(r=>{const m=byId.get(r.id);return {...r,extra:{editedAt:edits.find(e=>e.message_id===r.id)?.edited_at??null,revision:Number(r.meta_revision??0),reply:m?.reply_to_id?{id:m.reply_to_id,text:m.reply_deleted?'تم حذف الرسالة':m.reply_body||'رسالة وسائط',deleted:!!m.reply_deleted,author:m.reply_author}:null,reactions:r.deleted_at?[]:reactions.filter(x=>x.message_id===r.id).map(x=>({emoji:x.emoji,count:Number(x.total),mine:Number(x.mine)===1}))}};});
 }
 async function bump(db,mid){await db.query('INSERT INTO tomi_chat_message_meta(message_id,revision) VALUES(?,1) ON CONFLICT(message_id) DO UPDATE SET revision=tomi_chat_message_meta.revision+1',[mid]);}
 async function bumpThread(db,tid){await db.query('INSERT INTO tomi_chat_features(thread_id,revision) VALUES(?,1) ON CONFLICT(thread_id) DO UPDATE SET revision=tomi_chat_features.revision+1',[tid]);}
 async function validateReply(db,tid,reply){
  if(!reply)return;
  const r=(await db.query('SELECT id,deleted_at FROM tomi_chat_messages WHERE id=? AND thread_id=?',[reply,tid])).rows[0];
  if(!r||r.deleted_at)fail(400,'REPLY_INVALID','الرسالة التي ترد عليها غير متاحة.');
 }
 async function handle(request,response,url,current){
  const path=url.pathname,method=request.method,viewer=current.id;
  let m=/^\/v1\/chats\/([a-f0-9-]{36})\/requests\/([a-f0-9-]{36})$/.exec(path);
  if(m&&method==='GET'){
   const tid=id(m[1]),nonce=id(m[2]),r=await thread(viewer,tid);
   const found=(await database.query('SELECT id FROM tomi_chat_messages WHERE thread_id=? AND sender_id=? AND request_id=?',[tid,viewer,nonce])).rows[0];
   if(!found)fail(404,'REQUEST_NOT_FOUND','لم يُسجّل هذا الإرسال بعد.');
   respond(response,200,{message:await message(viewer,tid,found.id),conversation:threadJson(r,viewer)});return true;
  }
  m=/^\/v1\/chats\/([a-f0-9-]{36})\/search$/.exec(path);
  if(m&&method==='GET'){
   const tid=id(m[1]),r=await thread(viewer,tid),q=(url.searchParams.get('q')??'').trim(),before=url.searchParams.get('before');
   const kind=url.searchParams.get('kind')??'all',date=url.searchParams.get('date'),offset=Number(url.searchParams.get('tzOffsetMinutes')??0);
   if(!Number.isInteger(offset)||Math.abs(offset)>840)fail(400,'VALIDATION','منطقة زمنية غير صحيحة.');
   if(!['all','image','video','audio','link','file'].includes(kind)||q&&([...q].length<2||[...q].length>80)||!q&&kind==='all'&&!date||date&&(!/^\d{4}-\d{2}-\d{2}$/.test(date)||!Number.isFinite(Date.parse(date)))||before!==null&&(!/^\d{1,16}$/.test(before)||!Number.isSafeInteger(Number(before))||Number(before)<1))fail(400,'VALIDATION','اختر كلمة أو تاريخاً أو نوع وسائط للبحث.');
   await limit('chat-search:'+viewer,60);
   const values=[tid],conditions=['m.thread_id=?','m.deleted_at IS NULL'];
   if(q){conditions.push("LOWER(m.body) LIKE LOWER(?) ESCAPE '!'");values.push('%'+q.replace(/[!%_]/g,'!$&')+'%');}
   if(before!==null){conditions.push('m.sequence<?');values.push(Number(before));}
   if(date){conditions.push('m.created_at>=? AND m.created_at<?');values.push(new Date(Date.parse(date)-offset*60000).toISOString(),new Date(Date.parse(date)-offset*60000+86400000).toISOString());}
   if(kind==='image')conditions.push('m.image_upload_id IS NOT NULL');
   if(kind==='video')conditions.push('video.id IS NOT NULL');
   if(kind==='audio')conditions.push('audio.id IS NOT NULL');
   if(kind==='file')conditions.push('doc.id IS NOT NULL');
   if(kind==='link')conditions.push("(LOWER(m.body) LIKE '%https://%' OR LOWER(m.body) LIKE '%http://%')");
   const rows=(await database.query(messagesSql+'WHERE '+conditions.join(' AND ')+' ORDER BY m.sequence DESC LIMIT 31',values)).rows;
   respond(response,200,{messages:(await enrich(rows.slice(0,30),viewer)).map(x=>messageJson(x,viewer)),nextBefore:rows.length>30?Number(rows[29].sequence):null,conversation:threadJson(r,viewer)});return true;
  }
  m=/^\/v1\/chats\/([a-f0-9-]{36})\/messages\/([a-f0-9-]{36})\/(reaction|pin)$/.exec(path);
  if(!m||method!=='PUT')return false;
  const tid=id(m[1]),mid=id(m[2]),action=m[3],d=await readJson(request);
  await limit('chat-tools:'+viewer,90);
  fields(d,action==='reaction'?['emoji']:['pinned']);
  if(action==='reaction'&&!(d.emoji===null||reactionEmojis.includes(d.emoji))||action==='pin'&&typeof d.pinned!=='boolean')fail(400,'VALIDATION','اختيار التفاعل أو التثبيت غير صحيح.');
  const r=await database.transaction(async db=>{
   const r=await lock(db,viewer,tid);sending(r);
   const row=(await db.query('SELECT id,deleted_at FROM tomi_chat_messages WHERE id=? AND thread_id=?',[mid,tid])).rows[0];
   if(!row)fail(404,'MESSAGE_NOT_FOUND','الرسالة غير موجودة.');if(row.deleted_at)fail(409,'MESSAGE_DELETED','الرسالة محذوفة.');
   if(action==='reaction'){
    if(d.emoji===null)await db.query('DELETE FROM tomi_chat_reactions WHERE message_id=? AND user_id=?',[mid,viewer]);
    else await db.query('INSERT INTO tomi_chat_reactions(message_id,user_id,emoji) VALUES(?,?,?) ON CONFLICT(message_id,user_id) DO UPDATE SET emoji=excluded.emoji',[mid,viewer,d.emoji]);
    await bump(db,mid);
   }else{
    if(d.pinned)await db.query('INSERT INTO tomi_chat_pins(thread_id,message_id,pinned_by,created_at) VALUES(?,?,?,?) ON CONFLICT(thread_id) DO UPDATE SET message_id=excluded.message_id,pinned_by=excluded.pinned_by,created_at=excluded.created_at',[tid,mid,viewer,new Date().toISOString()]);
    else await db.query('DELETE FROM tomi_chat_pins WHERE thread_id=? AND message_id=?',[tid,mid]);
    await bumpThread(db,tid);
   }
   return r;
  });
  notify(r,'chat.updated',{messageId:mid});respond(response,200,{message:await message(viewer,tid,mid),conversation:threadJson(await thread(viewer,tid),viewer)});return true;
 }
 return {enrich,handle,bump,bumpThread,validateReply};
}
