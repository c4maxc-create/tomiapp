import {verifyDocumentSignature} from './document_security.mjs';
import {randomUUID,createHash} from 'node:crypto';
import {ApiError} from './security.mjs';
import {cleanupVideoDerivatives,abortMultipartUpload,prepareIntent,uploadWithDigest} from './media_intents.mjs';
import {maxImageBytes,imageTypes} from './images.mjs';
import {maxAudioBytes,maxAudioDurationMs} from './audio.mjs';
import {maxVideoBytes} from './video.mjs';
export const stickerIds=['hello','love','laugh','thanks','wow','sad','sleep','party','angry','cool','coffee','hug','gif_heart','gif_wave','gif_party'];
export const documentExtensions=['pdf','txt','csv','json','md','doc','docx','xls','xlsx','ppt','pptx','zip','rar','7z'];
export const maxDocumentBytes=25*1024*1024;
const stamp=()=>new Date().toISOString();
const fail=(code,text,status=400)=>{throw new ApiError(status,code,text);};
export function documentName(v){
 if(typeof v!=='string'||v.length>120||!v.trim()||/[\x00-\x1f\x7f/\\]/.test(v)||!documentExtensions.includes(v.split('.').at(-1).toLowerCase()))fail('FILE_NAME','اختَر مستندًا أو ملفًا مضغوطًا باسم صحيح.');
 return v.trim();
}
export function createPrivateMedia({database,storage}){
 async function prepare(viewer,tid,kind,d){
  if(!storage)fail('MEDIA_DISABLED','إرسال المرفقات غير متاح.',503);
  const allowed=['requestId','contentType','byteLength','contentMd5','contentSha256',...kind==='audio'?['durationMs']:[],...kind==='file'?['fileName']:[]];
  if(Object.keys(d).some(k=>!allowed.includes(k)))fail('VALIDATION','طلب المرفق غير صحيح.');
  const size=kind==='image'?maxImageBytes:kind==='audio'?maxAudioBytes:maxDocumentBytes;
  if(!Number.isSafeInteger(d.byteLength)||d.byteLength<1||d.byteLength>size||typeof d.contentMd5!=='string'||!/^[A-Za-z0-9+/]{22}==$/.test(d.contentMd5)||!/^[a-f0-9]{64}$/.test(d.contentSha256??''))fail('VALIDATION','حجم المرفق أو بصمته غير صحيح.');
  if(kind==='image'&&!imageTypes[d.contentType]||kind==='audio'&&(d.contentType!=='audio/mp4'||!Number.isSafeInteger(d.durationMs)||d.durationMs<250||d.durationMs>maxAudioDurationMs)||kind==='video'&&(d.contentType!=='video/mp4'||d.byteLength>maxVideoBytes)||kind==='file'&&d.contentType!=='application/octet-stream')fail('VALIDATION','نوع المرفق غير صحيح.');
  const name=kind==='file'?documentName(d.fileName):null;
  return prepareIntent({database,viewer,scope:`private:${tid}:${kind}`,table:'tomi_private_uploads',d:{...d,...name?{fileName:name}:{}},storage,create:async db=>{
   const u={id:randomUUID(),user_id:viewer,thread_id:tid,kind,object_key:`tomi/chat-private/${tid}/${viewer}/${randomUUID()}.${kind==='file'?name.split('.').at(-1):kind==='image'?imageTypes[d.contentType]:'mp4'}`,content_type:d.contentType,byte_length:d.byteLength,content_md5:d.contentMd5,file_name:name,duration_ms:d.durationMs??null,created_at:stamp(),expires_at:new Date(Date.now()+900000).toISOString()};
   await db.query('INSERT INTO tomi_private_uploads(id,user_id,thread_id,kind,object_key,content_type,byte_length,content_md5,file_name,duration_ms,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',Object.values(u));return u;
  }});
 }
 async function verify(viewer,tid,uploadId,sha){
  const u=(await database.query('SELECT * FROM tomi_private_uploads WHERE id=? AND user_id=? AND thread_id=?',[uploadId,viewer,tid])).rows[0];
  if(!u||u.state!=='pending'||u.expires_at<=stamp())fail('UPLOAD_INVALID','المرفق انتهى أو استُخدم؛ جهّزه مرة ثانية.',409);
  const verified=await uploadWithDigest(database,u,sha);
  const info=u.kind==='file'?await verifyDocument(storage,verified):u.kind==='image'?await storage.verify(verified):u.kind==='audio'?await storage.verifyAudio(verified):await storage.verifyVideo(verified);
  if(u.kind==='audio'&&Math.abs(info.durationMs-Number(u.duration_ms))>2000)fail('INVALID_AUDIO','مدة التسجيل غير صحيحة.');
  return{...u,width:info.width??null,height:info.height??null,duration_ms:info.durationMs??null};
 }
 async function attach(db,u){
  const r=await db.query("UPDATE tomi_private_uploads SET state='attached',width=?,height=?,duration_ms=? WHERE id=? AND user_id=? AND thread_id=? AND state='pending' AND expires_at>?",[u.width,u.height,u.duration_ms,u.id,u.user_id,u.thread_id,stamp()]);
  if(r.changes!==1)fail('UPLOAD_INVALID','المرفق انتهى أو استُخدم.',409);
 }
 async function cleanup(){if(!storage)return;for(const u of (await database.query("SELECT id,object_key FROM tomi_private_uploads WHERE state<>'attached' AND expires_at<=? LIMIT 20",[stamp()])).rows){try{await cleanupVideoDerivatives(database,storage,u.id,u.object_key);await abortMultipartUpload(database,storage,u.id,u.object_key);await storage.delete(u.object_key);await database.query("DELETE FROM tomi_private_uploads WHERE id=? AND state<>'attached'",[u.id]);await database.query('DELETE FROM tomi_upload_digests WHERE upload_id=?',[u.id]);}catch{console.error('Private attachment cleanup deferred');}}}
 return{prepare,verify,attach,cleanup};
}
async function verifyDocument(storage,u){
 let scan;
 if(storage.active>=2)fail('MEDIA_BUSY','المرفقات قيد المعالجة؛ جرّب بعد قليل.',503);
 storage.active=(storage.active??0)+1;const abort=new AbortController(),timer=setTimeout(()=>abort.abort(),45000);
 try{scan=await storage.scanner?.begin();const r=await storage.fetcher(storage.url('GET',u.object_key),{signal:abort.signal,redirect:'error'});
  if(!r.ok){await r.body?.cancel();fail(r.status===404?'UPLOAD_INCOMPLETE':'MEDIA_UNAVAILABLE','تعذّر التحقق من الملف.',r.status===404?409:503);}
  if(Number(r.headers.get('content-length'))!==Number(u.byte_length)||(r.headers.get('content-type')??'').split(';')[0]!=='application/octet-stream'){await r.body?.cancel();fail('INVALID_FILE','حجم الملف أو نوعه تغيّر.');}
  let length=0;const prefixes=[];let prefixSize=0;const decoder=['txt','csv','json','md'].includes(u.file_name.split('.').at(-1).toLowerCase())?new TextDecoder('utf-8',{fatal:true}):null;const md5=createHash('md5'),sha=createHash('sha256');for await(const part of r.body){await scan?.write(part);if(decoder&&part.includes(0))fail('INVALID_FILE','الملف النصي يحتوي بيانات غير مسموحة.');decoder?.decode(part,{stream:true});if(prefixSize<1024){const head=Buffer.from(part.subarray(0,1024-prefixSize));prefixes.push(head);prefixSize+=head.length;}length+=part.length;if(length>Number(u.byte_length)||length>maxDocumentBytes){abort.abort();fail('INVALID_FILE','الملف أكبر من المسموح.');}md5.update(part);sha.update(part);}
  if(length!==Number(u.byte_length)||md5.digest('base64')!==u.content_md5||sha.digest('hex')!==u.content_sha256)fail('INVALID_FILE','الملف غير مكتمل أو تغيّر.');decoder?.decode();verifyDocumentSignature(Buffer.concat(prefixes),u.file_name);await scan?.finish();return{};
 }catch(e){if(e instanceof ApiError)throw e;fail('MEDIA_UNAVAILABLE','تعذّر التحقق من الملف؛ جرّب مرة ثانية.',503);}finally{await scan?.abort();clearTimeout(timer);storage.active--;}
}

// The existing durable erasure outbox owns object deletion even after rows vanish.
export async function eraseChatExtras(db,uid,now){
 const groups=(await db.query('SELECT DISTINCT g.id FROM tomi_groups g JOIN tomi_group_members gm ON gm.group_id=g.id WHERE gm.user_id=? ORDER BY g.id',[uid])).rows;
 for(const g of groups)await db.query('UPDATE tomi_groups SET revision=revision+1 WHERE id=?',[g.id]);
 await db.query("INSERT INTO tomi_erasure_media(id,user_id,media_type,upload_id,scope,object_key,final_after,next_at) SELECT 'private:'||id,user_id,'image',id,'private',object_key,?,? FROM tomi_private_uploads WHERE user_id=? ON CONFLICT(scope,object_key) DO NOTHING",[now(16*60000),now(),uid]);
 await db.query('DELETE FROM tomi_chat_documents WHERE upload_id IN(SELECT id FROM tomi_private_uploads WHERE user_id=?)',[uid]);
 await db.query('DELETE FROM tomi_chat_stickers WHERE message_id IN(SELECT id FROM tomi_chat_messages WHERE sender_id=?)',[uid]);
 await db.query('DELETE FROM tomi_group_reactions WHERE user_id=? OR message_id IN(SELECT id FROM tomi_group_messages WHERE sender_id=?)',[uid,uid]);
 await db.query('UPDATE tomi_groups SET pinned_message_id=NULL WHERE pinned_message_id IN(SELECT id FROM tomi_group_messages WHERE sender_id=?)',[uid]);
 await db.query("UPDATE tomi_group_messages SET body='',upload_id=NULL,sticker_id=NULL,reply_to_id=NULL,payload_hash='',deleted_at=COALESCE(deleted_at,?),revision=revision+1 WHERE sender_id=?",[now(),uid]);
 await db.query('DELETE FROM tomi_group_push WHERE recipient_id=? OR message_id IN(SELECT id FROM tomi_group_messages WHERE sender_id=?)',[uid,uid]);
 await db.query('DELETE FROM tomi_upload_digests WHERE upload_id IN(SELECT id FROM tomi_private_uploads WHERE user_id=?)',[uid]);
 await db.query('DELETE FROM tomi_private_uploads WHERE user_id=?',[uid]);
 await db.query('UPDATE tomi_group_members SET left_at=COALESCE(left_at,?),last_read_seq=0 WHERE user_id=?',[now(),uid]);
 for(const g of (await db.query('SELECT id FROM tomi_groups WHERE owner_id=?',[uid])).rows){const next=(await db.query('SELECT user_id FROM tomi_group_members WHERE group_id=? AND left_at IS NULL ORDER BY joined_at,user_id LIMIT 1',[g.id])).rows[0];if(next)await db.query("UPDATE tomi_groups SET owner_id=?,title='مجموعة',revision=revision+1 WHERE id=?",[next.user_id,g.id]);else{await db.query("UPDATE tomi_private_uploads SET state='deleting',expires_at=? WHERE id IN(SELECT upload_id FROM tomi_group_messages WHERE group_id=?)",[now(),g.id]);await db.query('DELETE FROM tomi_groups WHERE id=?',[g.id]);}}
}
