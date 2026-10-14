import {randomUUID} from 'node:crypto';
import {ApiError,digest,isUniqueConflict} from './security.mjs';
import {imageTypes,maxImageBytes} from './images.mjs';
import {createRealtime} from './realtime.mjs';
import {avatarJoins,avatarColumns,avatarFields} from './avatars.mjs';
import {maxAudioBytes,maxAudioDurationMs} from './audio.mjs';
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const now=()=>new Date().toISOString();
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const id=v=>{if(typeof v!=='string'||!uuid.test(v))fail(400,'VALIDATION','معرّف غير صحيح.');return v;};
const fields=(d,allowed)=>{if(Object.keys(d).some(k=>!allowed.includes(k)))fail(400,'VALIDATION','هذا الطلب غير مسموح.');};
const integer=v=>{if(!Number.isSafeInteger(v)||v<0)fail(400,'VALIDATION','رقم الرسالة غير صحيح.');return v;};
function pageNumber(url,key,fallback,max=Number.MAX_SAFE_INTEGER){const v=url.searchParams.get(key);if(v===null)return fallback;if(!/^\d{1,16}$/.test(v)||Number(v)>max)fail(400,'VALIDATION','الصفحة غير صحيحة.');return integer(Number(v));}
const threads=`SELECT t.*,self.last_read_seq,pm.last_read_seq AS peer_read_seq,u.id AS peer_id,u.username,u.display_name,u.avatar_preset${avatarColumns},
 lm.body AS last_body,lm.image_upload_id AS last_image,EXISTS(SELECT 1 FROM tomi_chat_audio a WHERE a.message_id=lm.id) AS last_audio,lm.deleted_at AS last_deleted,lm.created_at AS last_created,lm.sender_id AS last_sender,
 (SELECT COUNT(*) FROM tomi_chat_messages x WHERE x.thread_id=t.id AND x.sender_id<>self.user_id AND x.sequence>self.last_read_seq AND x.deleted_at IS NULL) AS unread_count,
 (SELECT COUNT(*) FROM tomi_user_blocks b WHERE b.blocker_id=self.user_id AND b.blocked_id=u.id) AS blocked_by_me,
 (SELECT COUNT(*) FROM tomi_user_blocks b WHERE b.blocker_id=u.id AND b.blocked_id=self.user_id) AS blocked_by_peer
 FROM tomi_chat_threads t JOIN tomi_chat_members self ON self.thread_id=t.id AND self.user_id=?
 JOIN tomi_chat_members pm ON pm.thread_id=t.id AND pm.user_id<>self.user_id JOIN tomi_users u ON u.id=pm.user_id
 ${avatarJoins} LEFT JOIN tomi_chat_messages lm ON lm.thread_id=t.id AND lm.sequence=t.next_seq `;
const messages=`SELECT m.*,u.username,u.display_name,u.avatar_preset,media.object_key,media.width,media.height,audio.object_key AS audio_key,audio.duration_ms${avatarColumns}
 FROM tomi_chat_messages m JOIN tomi_users u ON u.id=m.sender_id LEFT JOIN tomi_image_uploads media ON media.id=m.image_upload_id LEFT JOIN tomi_chat_audio ca ON ca.message_id=m.id LEFT JOIN tomi_audio_uploads audio ON audio.id=ca.upload_id ${avatarJoins} `;
export function createChat({database,storage,avatarStorage=storage,readJson,respond,limit,userById,enqueuePush=async()=>{}}){
 let realtime;
 const threadJson=(r,viewer)=>({id:r.id,peer:{id:r.peer_id,username:r.username,displayName:r.display_name,avatarPreset:r.avatar_preset,...avatarFields(r,avatarStorage)},updatedAt:r.updated_at,
  unreadCount:Number(r.unread_count),sequence:Number(r.next_seq),myReadSequence:Number(r.last_read_seq),peerReadSequence:Number(r.peer_read_seq),
  lastMessage:r.last_created?(r.last_deleted?'تم حذف الرسالة':r.last_body||(Number(r.last_audio)?'🎤 رسالة صوتية':'📷 صورة')):'',lastMessageAt:r.last_created||null,lastMessageIsMine:r.last_sender===viewer,
  blockedByMe:Number(r.blocked_by_me)>0,blockedByPeer:Number(r.blocked_by_peer)>0,imageUploadEnabled:!!storage,audioUploadEnabled:!!storage});
 const messageJson=(r,viewer)=>({id:r.id,conversationId:r.thread_id,sequence:Number(r.sequence),requestId:r.sender_id===viewer?r.request_id:null,
  text:r.deleted_at?'':r.body,createdAt:r.created_at,deleted:!!r.deleted_at,isMine:r.sender_id===viewer,
  author:{id:r.sender_id,username:r.username,displayName:r.display_name,avatarPreset:r.avatar_preset,...avatarFields(r,avatarStorage)},
  audio:!r.deleted_at&&r.audio_key?{url:storage?.privateReadUrl(r.audio_key)??null,durationMs:Number(r.duration_ms)}:null,
  image:!r.deleted_at&&r.object_key?{url:storage?.privateReadUrl(r.object_key)??null,width:Number(r.width),height:Number(r.height)}:null});
 async function thread(viewer,threadId,db=database){const{rows}=await db.query(threads+'WHERE t.id=?',[viewer,threadId]);if(!rows[0])fail(404,'CHAT_NOT_FOUND','المحادثة غير موجودة.');return rows[0];}
 async function message(viewer,threadId,messageId){const{rows}=await database.query(messages+'WHERE m.thread_id=? AND m.id=?',[threadId,messageId]);if(!rows[0])fail(404,'MESSAGE_NOT_FOUND','الرسالة غير موجودة.');return messageJson(rows[0],viewer);}
 async function pair(db,viewer,target){const[low,high]=[viewer,target].sort(),stamp=now();const{rows}=await db.query(`INSERT INTO tomi_chat_threads(id,low_user_id,high_user_id,created_at,updated_at) VALUES(?,?,?,?,?)
  ON CONFLICT(low_user_id,high_user_id) DO UPDATE SET updated_at=tomi_chat_threads.updated_at RETURNING id`,[randomUUID(),low,high,stamp,stamp]);
  for(const user of [low,high])await db.query('INSERT INTO tomi_chat_members(thread_id,user_id) VALUES(?,?) ON CONFLICT(thread_id,user_id) DO NOTHING',[rows[0].id,user]);return rows[0].id;}
 async function lock(db,viewer,threadId){const r=await db.query('UPDATE tomi_chat_threads SET updated_at=updated_at WHERE id=? AND (low_user_id=? OR high_user_id=?) RETURNING id',[threadId,viewer,viewer]);if(!r.rows[0])fail(404,'CHAT_NOT_FOUND','المحادثة غير موجودة.');return thread(viewer,threadId,db);}
 const sending=r=>{if(Number(r.blocked_by_me)||Number(r.blocked_by_peer))fail(403,'CHAT_BLOCKED','المراسلة غير متاحة مع هذا المستخدم.');};
 const notify=(r,type,extra={})=>realtime?.emit([r.low_user_id,r.high_user_id],{type,conversationId:r.id,...extra});
 async function existing(db,viewer,requestId,hash){const{rows}=await db.query('SELECT id,payload_hash FROM tomi_chat_messages WHERE sender_id=? AND request_id=?',[viewer,requestId]);if(!rows[0])return null;if(rows[0].payload_hash!==hash)fail(409,'REQUEST_CHANGED','محتوى الرسالة تغيّر؛ أرسل رسالة جديدة.');return rows[0].id;}
 async function handle(request,response,url,current){const path=url.pathname,method=request.method,viewer=current.id;
  if(method==='GET'&&path==='/v1/chats'){
   const size=pageNumber(url,'limit',30,50);if(!size)fail(400,'VALIDATION','حجم الصفحة غير صحيح.');
   const values=[viewer],conditions=['self.visible=1'],raw=url.searchParams.get('cursor');
   if(raw){let cursor;try{if(raw.length>200)throw Error();cursor=JSON.parse(Buffer.from(raw,'base64url').toString());if(!uuid.test(cursor.id)||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(cursor.time)||!Number.isFinite(Date.parse(cursor.time)))throw Error();}catch{fail(400,'VALIDATION','الصفحة غير صحيحة.');}
    conditions.push('(t.updated_at<? OR (t.updated_at=? AND t.id<?))');values.push(cursor.time,cursor.time,cursor.id);}
   values.push(size+1);const{rows}=await database.query(threads+'WHERE '+conditions.join(' AND ')+' ORDER BY t.updated_at DESC,t.id DESC LIMIT ?',values),items=rows.slice(0,size),last=items.at(-1);
   const total=await database.query(`SELECT COUNT(*) AS total FROM tomi_chat_messages m JOIN tomi_chat_members member ON member.thread_id=m.thread_id AND member.user_id=?
    WHERE member.visible=1 AND m.sender_id<>? AND m.sequence>member.last_read_seq AND m.deleted_at IS NULL`,[viewer,viewer]);
   respond(response,200,{conversations:items.map(r=>threadJson(r,viewer)),totalUnread:Number(total.rows[0].total),nextCursor:rows.length>size?Buffer.from(JSON.stringify({time:last.updated_at,id:last.id})).toString('base64url'):null});return true;
  }
  if(method==='POST'&&path==='/v1/chats'){
   await limit('chat-open:'+viewer,30);const d=await readJson(request);fields(d,['userId']);const target=id(d.userId);if(target===viewer)fail(400,'SELF_CHAT','اختَر حسابًا آخر.');await userById(target,viewer);
   const threadId=await database.transaction(async db=>{const tid=await pair(db,viewer,target);sending(await thread(viewer,tid,db));await db.query('UPDATE tomi_chat_members SET visible=1 WHERE thread_id=? AND user_id=?',[tid,viewer]);return tid;});
   respond(response,200,{conversation:threadJson(await thread(viewer,threadId),viewer)});return true;
  }
  if(method==='GET'&&path==='/v1/chat/blocks'){
   const{rows}=await database.query('SELECT u.id,u.username,u.display_name,u.avatar_preset FROM tomi_user_blocks b JOIN tomi_users u ON u.id=b.blocked_id WHERE b.blocker_id=? ORDER BY b.created_at DESC LIMIT 200',[viewer]);
   respond(response,200,{users:rows.map(r=>({id:r.id,username:r.username,displayName:r.display_name,avatarPreset:r.avatar_preset,...avatarFields(r,avatarStorage)}))});return true;
  }
  const block=path.match(/^\/v1\/chat\/blocks\/([a-f0-9-]{36})$/);
  if(method==='PUT'&&block){await limit('chat-block:'+viewer,30);const target=id(block[1]),d=await readJson(request);fields(d,['blocked']);if(target===viewer||typeof d.blocked!=='boolean')fail(400,'VALIDATION','حالة الحظر غير صحيحة.');await userById(target,viewer);
   const r=await database.transaction(async db=>{const tid=await pair(db,viewer,target);if(d.blocked)await db.query('INSERT INTO tomi_user_blocks(blocker_id,blocked_id,created_at) VALUES(?,?,?) ON CONFLICT(blocker_id,blocked_id) DO NOTHING',[viewer,target,now()]);else await db.query('DELETE FROM tomi_user_blocks WHERE blocker_id=? AND blocked_id=?',[viewer,target]);return thread(viewer,tid,db);});
   notify(r,'chat.blocked');respond(response,200,{conversation:threadJson(r,viewer)});return true;
  }
  const match=path.match(/^\/v1\/chats\/([a-f0-9-]{36})(\/messages|\/images|\/audio|\/read)?$/);
  if(match){const tid=id(match[1]),action=match[2]||'',row=await thread(viewer,tid);
   if(method==='GET'&&!action){respond(response,200,{conversation:threadJson(row,viewer)});return true;}
   if(method==='GET'&&action==='/messages'){
    const size=pageNumber(url,'limit',40,100),after=pageNumber(url,'after',null),before=pageNumber(url,'before',null);
    if(!size||(after!==null&&before!==null))fail(400,'VALIDATION','الصفحة غير صحيحة.');const values=[tid],conditions=['m.thread_id=?'];
    if(after!==null){conditions.push('m.sequence>?');values.push(after);}if(before!==null){conditions.push('m.sequence<?');values.push(before);}values.push(size+1);
    const{rows}=await database.query(messages+'WHERE '+conditions.join(' AND ')+' ORDER BY m.sequence '+(after===null?'DESC':'ASC')+' LIMIT ?',values),selected=rows.slice(0,size),items=after===null?selected.reverse():selected;
    respond(response,200,{conversation:threadJson(row,viewer),messages:items.map(r=>messageJson(r,viewer)),nextBefore:after===null&&rows.length>size?Number(items[0].sequence):null,nextAfter:after!==null&&rows.length>size?Number(items.at(-1).sequence):null});return true;
   }
   if(method==='POST'&&action==='/audio'){
    if(!storage)fail(503,'AUDIO_DISABLED','إرسال الصوت غير متاح.');sending(row);await limit('audio:'+viewer,10);await limit('daily-audio:'+viewer,100,86400000);const d=await readJson(request);fields(d,['contentType','byteLength','contentMd5','durationMs']);
    if(d.contentType!=='audio/mp4'||!Number.isInteger(d.byteLength)||d.byteLength<32||d.byteLength>maxAudioBytes||!Number.isInteger(d.durationMs)||d.durationMs<100||d.durationMs>maxAudioDurationMs||typeof d.contentMd5!=='string'||!/^[A-Za-z0-9+/]{22}==$/.test(d.contentMd5))fail(400,'INVALID_AUDIO','التسجيل لا يتجاوز 5 دقائق و6 MB.');
    const pending=await database.query("SELECT COUNT(*) AS total FROM tomi_audio_uploads WHERE user_id=? AND state='pending' AND expires_at>?",[viewer,now()]);if(Number(pending.rows[0].total)>=10)fail(429,'RATE_LIMITED','عندك تسجيلات قيد الرفع.');const uploadId=randomUUID(),u={id:uploadId,user_id:viewer,thread_id:tid,object_key:`tomi/chat-audio/${tid}/${viewer}/${uploadId}.m4a`,content_type:d.contentType,byte_length:d.byteLength,content_md5:d.contentMd5,duration_ms:d.durationMs};await database.query('INSERT INTO tomi_audio_uploads(id,user_id,thread_id,object_key,content_type,byte_length,content_md5,duration_ms,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?,?)',[uploadId,viewer,tid,u.object_key,u.content_type,u.byte_length,u.content_md5,u.duration_ms,now(),new Date(Date.now()+86400000).toISOString()]);respond(response,201,{uploadId,...storage.prepare(u)});return true;
   }
   if(method==='POST'&&action==='/images'){
    if(!storage)fail(503,'IMAGES_DISABLED','إرسال الصور غير متاح؛ تگدر ترسل نص.');sending(row);await limit('images:'+viewer,10);await limit('daily-images:'+viewer,100,86400000);
    const d=await readJson(request);fields(d,['contentType','byteLength','contentMd5']);
    if(!Object.hasOwn(imageTypes,d.contentType)||!Number.isInteger(d.byteLength)||d.byteLength<13||d.byteLength>maxImageBytes||typeof d.contentMd5!=='string'||!/^[A-Za-z0-9+/]{22}==$/.test(d.contentMd5))fail(400,'INVALID_IMAGE','اختَر صورة بحجم لا يتجاوز 10 MB.');
    const pending=await database.query("SELECT COUNT(*) AS total FROM tomi_image_uploads WHERE user_id=? AND state='pending' AND expires_at>?",[viewer,now()]);if(Number(pending.rows[0].total)>=10)fail(429,'RATE_LIMITED','عندك صور قيد الرفع.');
    const uploadId=randomUUID(),u={id:uploadId,user_id:viewer,object_key:`tomi/chat-images/${tid}/${viewer}/${uploadId}.${imageTypes[d.contentType]}`,content_type:d.contentType,byte_length:d.byteLength,content_md5:d.contentMd5};
    await database.query('INSERT INTO tomi_image_uploads(id,user_id,object_key,content_type,byte_length,content_md5,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?)',[uploadId,viewer,u.object_key,u.content_type,u.byte_length,u.content_md5,now(),new Date(Date.now()+86400000).toISOString()]);
    respond(response,201,{uploadId,...storage.prepare(u)});return true;
   }
   if(method==='POST'&&action==='/messages'){
    await limit('chat-send:'+viewer,60);const d=await readJson(request);fields(d,['text','requestId','imageUploadId','audioUploadId']);if(d.text!==undefined&&typeof d.text!=='string')fail(400,'VALIDATION','النص غير صحيح.');
    const text=(d.text||'').trim(),requestId=id(d.requestId),uploadId=d.imageUploadId==null?null:id(d.imageUploadId),audioId=d.audioUploadId==null?null:id(d.audioUploadId),hash=digest(JSON.stringify(audioId?[tid,text,uploadId,audioId]:[tid,text,uploadId]));
    if([...text].length>2000||(!text&&!uploadId&&!audioId)||(uploadId&&audioId))fail(400,'VALIDATION','اكتب رسالة أو اختَر صورة؛ الحد 2000 حرف.');
    let previous=await existing(database,viewer,requestId,hash),dimensions,audioInfo;
    if(!previous&&uploadId){sending(row);if(!storage)fail(503,'IMAGES_DISABLED','إرسال الصور غير متاح.');const{rows}=await database.query('SELECT * FROM tomi_image_uploads WHERE id=? AND user_id=?',[uploadId,viewer]);const u=rows[0];
     if(!u||u.state!=='pending'||u.expires_at<=now()||!u.object_key.startsWith(`tomi/chat-images/${tid}/${viewer}/`))fail(400,'UPLOAD_INVALID','الصورة انتهت أو استُخدمت؛ جهّزها مرة ثانية.');dimensions=await storage.verify(u);}
    if(!previous&&audioId){sending(row);if(!storage)fail(503,'AUDIO_DISABLED','إرسال الصوت غير متاح.');const{rows}=await database.query('SELECT * FROM tomi_audio_uploads WHERE id=? AND user_id=? AND thread_id=?',[audioId,viewer,tid]),u=rows[0];if(!u||u.state!=='pending'||u.expires_at<=now())fail(400,'UPLOAD_INVALID','التسجيل انتهى أو استُخدم.');audioInfo=await storage.verifyAudio(u);if(Math.abs(audioInfo.durationMs-Number(u.duration_ms))>2000)fail(400,'INVALID_AUDIO','مدة التسجيل غير صحيحة.');}
    let saved;try{saved=await database.transaction(async db=>{const locked=await lock(db,viewer,tid);previous=await existing(db,viewer,requestId,hash);if(previous)return{id:previous,repeated:true,row:locked};sending(locked);
     const stamp=now(),mid=randomUUID(),changed=await db.query('UPDATE tomi_chat_threads SET next_seq=next_seq+1,updated_at=? WHERE id=? RETURNING next_seq',[stamp,tid]);
     await db.query('INSERT INTO tomi_chat_messages(id,thread_id,sender_id,sequence,request_id,payload_hash,body,image_upload_id,created_at) VALUES(?,?,?,?,?,?,?,?,?)',[mid,tid,viewer,integer(Number(changed.rows[0].next_seq)),requestId,hash,text,uploadId,stamp]);
     if(uploadId){const result=await db.query("UPDATE tomi_image_uploads SET state='attached',width=?,height=? WHERE id=? AND user_id=? AND state='pending' AND expires_at>?",[dimensions.width,dimensions.height,uploadId,viewer,now()]);if(result.changes!==1)fail(409,'UPLOAD_INVALID','الصورة انتهت أو استُخدمت.');}
     if(audioId){const result=await db.query("UPDATE tomi_audio_uploads SET state='attached',duration_ms=? WHERE id=? AND user_id=? AND thread_id=? AND state='pending' AND expires_at>?",[audioInfo.durationMs,audioId,viewer,tid,now()]);if(result.changes!==1)fail(409,'UPLOAD_INVALID','التسجيل انتهى أو استُخدم.');await db.query('INSERT INTO tomi_chat_audio(message_id,upload_id) VALUES(?,?)',[mid,audioId]);}
     await enqueuePush(db,{messageId:mid,recipientId:locked.low_user_id===viewer?locked.high_user_id:locked.low_user_id,threadId:tid});
     await db.query('UPDATE tomi_chat_members SET visible=1 WHERE thread_id=?',[tid]);return{id:mid,repeated:false,row:locked};
    });}catch(error){if(!isUniqueConflict(error))throw error;const mid=await existing(database,viewer,requestId,hash);if(!mid)fail(409,'UPLOAD_INVALID','الصورة استُخدمت.');saved={id:mid,repeated:true,row};}
    if(!saved.repeated)notify(saved.row,'chat.message',{messageId:saved.id});respond(response,saved.repeated?200:201,{message:await message(viewer,tid,saved.id),conversation:threadJson(await thread(viewer,tid),viewer)});return true;
   }
   if(method==='PUT'&&action==='/read'){
    await limit('chat-read:'+viewer,90);const d=await readJson(request);fields(d,['sequence']);const seq=integer(d.sequence);
    const saved=await database.transaction(async db=>{const r=await lock(db,viewer,tid);if(seq>Number(r.next_seq))fail(400,'VALIDATION','رقم القراءة أحدث من الرسائل.');if(seq<=Number(r.last_read_seq))return{row:r,changed:false};
     await db.query('UPDATE tomi_chat_members SET last_read_seq=? WHERE thread_id=? AND user_id=?',[seq,tid,viewer]);return{row:await thread(viewer,tid,db),changed:true};});
    if(saved.changed)notify(saved.row,'chat.read');respond(response,200,{conversation:threadJson(saved.row,viewer)});return true;
   }
  }
  const m=path.match(/^\/v1\/chats\/([a-f0-9-]{36})\/messages\/([a-f0-9-]{36})$/);
  if(m&&method==='GET'){const tid=id(m[1]),mid=id(m[2]),r=await thread(viewer,tid);respond(response,200,{message:await message(viewer,tid,mid),conversation:threadJson(r,viewer)});return true;}
  if(m&&method==='DELETE'){
   await limit('chat-delete:'+viewer,30);const tid=id(m[1]),mid=id(m[2]);
   const row=await database.transaction(async db=>{const r=await lock(db,viewer,tid),{rows}=await db.query('SELECT sender_id,image_upload_id,deleted_at FROM tomi_chat_messages WHERE id=? AND thread_id=?',[mid,tid]);
    if(!rows[0])fail(404,'MESSAGE_NOT_FOUND','الرسالة غير موجودة.');if(rows[0].sender_id!==viewer)fail(403,'FORBIDDEN','تگدر تحذف رسائلك فقط.');
    if(!rows[0].deleted_at){await db.query("UPDATE tomi_chat_messages SET body='',image_upload_id=NULL,deleted_at=? WHERE id=?",[now(),mid]);await db.query('UPDATE tomi_chat_threads SET updated_at=? WHERE id=?',[now(),tid]);if(rows[0].image_upload_id)await db.query("UPDATE tomi_image_uploads SET state='deleting',expires_at=? WHERE id=?",[new Date(Date.now()+1200000).toISOString(),rows[0].image_upload_id]);}const audio=await db.query('SELECT upload_id FROM tomi_chat_audio WHERE message_id=?',[mid]);if(audio.rows[0]){await db.query('DELETE FROM tomi_chat_audio WHERE message_id=?',[mid]);await db.query("UPDATE tomi_audio_uploads SET state='deleting',expires_at=? WHERE id=?",[new Date(Date.now()+1200000).toISOString(),audio.rows[0].upload_id]);}return r;});
   notify(row,'chat.deleted',{messageId:mid});respond(response,200,{message:await message(viewer,tid,mid),conversation:threadJson(await thread(viewer,tid),viewer)});return true;
  }
  return false;
 }
 function attach(server,options){realtime=createRealtime({...options,server,limit,typing:async(viewer,tid,active)=>{const r=await thread(viewer,id(tid));sending(r);realtime.emit([r.low_user_id===viewer?r.high_user_id:r.low_user_id],{type:'chat.typing',conversationId:tid,active,expiresAt:Date.now()+5000});}});}
 let cleaning=false;
 async function cleanup(){if(!storage||cleaning)return;cleaning=true;try{const{rows}=await database.query("SELECT id,object_key FROM tomi_audio_uploads WHERE state<>'attached' AND expires_at<=? ORDER BY expires_at LIMIT 20",[now()]);for(const u of rows)try{await storage.delete(u.object_key);await database.query("DELETE FROM tomi_audio_uploads WHERE id=? AND state<>'attached' AND expires_at<=?",[u.id,now()]);}catch{console.error('Audio cleanup deferred');}}finally{cleaning=false;}}
 return{handle,attach,cleanup,invalidateSession:hash=>realtime?.invalidateSession(hash),invalidateUser:viewer=>realtime?.invalidateUser(viewer)};
}
