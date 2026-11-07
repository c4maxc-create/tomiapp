import {requireContact} from './contact_preferences.mjs';
import {randomUUID} from 'node:crypto';
import {ApiError,digest,isUniqueConflict} from './security.mjs';
import {imageTypes,maxImageBytes} from './images.mjs';
import {createRealtime} from './realtime.mjs';
import {avatarJoins,avatarColumns,avatarFields} from './avatars.mjs';
import {maxAudioBytes,maxAudioDurationMs} from './audio.mjs';
import {cleanupVideos,maxVideoBytes} from './video.mjs';
import {abortMultipartUpload,prepareIntent,uploadWithDigest} from './media_intents.mjs';
import {createChatTools} from './chat_tools.mjs';
import {stickerIds} from './chat_extras.mjs';
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const now=()=>new Date().toISOString();
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const id=v=>{if(typeof v!=='string'||!uuid.test(v))fail(400,'VALIDATION','معرّف غير صحيح.');return v;};
const fields=(d,allowed)=>{if(Object.keys(d).some(k=>!allowed.includes(k)))fail(400,'VALIDATION','هذا الطلب غير مسموح.');};
const integer=v=>{if(!Number.isSafeInteger(v)||v<0)fail(400,'VALIDATION','رقم الرسالة غير صحيح.');return v;};
function pageNumber(url,key,fallback,max=Number.MAX_SAFE_INTEGER){const v=url.searchParams.get(key);if(v===null)return fallback;if(!/^\d{1,16}$/.test(v)||Number(v)>max)fail(400,'VALIDATION','الصفحة غير صحيحة.');return integer(Number(v));}
const threads=`SELECT EXISTS(SELECT 1 FROM tomi_e2ee_threads secure WHERE secure.thread_id=t.id) AS secure_enabled,(SELECT pinned FROM tomi_chat_organisation o WHERE o.thread_id=t.id AND o.user_id=self.user_id) AS personal_pinned,(SELECT archived FROM tomi_chat_organisation o WHERE o.thread_id=t.id AND o.user_id=self.user_id) AS personal_archived,(SELECT marked_unread FROM tomi_chat_organisation o WHERE o.thread_id=t.id AND o.user_id=self.user_id) AS marked_unread,t.*,(SELECT p.message_id FROM tomi_chat_pins p WHERE p.thread_id=t.id) AS pinned_message_id,COALESCE((SELECT f.revision FROM tomi_chat_features f WHERE f.thread_id=t.id),0) AS features_revision,self.last_read_seq,pm.last_read_seq AS peer_read_seq,u.id AS peer_id,u.username,u.display_name,u.avatar_preset${avatarColumns},
 EXISTS(SELECT 1 FROM tomi_chat_video v WHERE v.message_id=lm.id) AS last_video,EXISTS(SELECT 1 FROM tomi_chat_stickers st WHERE st.message_id=lm.id) AS last_sticker,EXISTS(SELECT 1 FROM tomi_chat_documents doc WHERE doc.message_id=lm.id) AS last_file,lm.body AS last_body,lm.image_upload_id AS last_image,EXISTS(SELECT 1 FROM tomi_chat_audio a WHERE a.message_id=lm.id) AS last_audio,lm.deleted_at AS last_deleted,lm.created_at AS last_created,lm.sender_id AS last_sender,
 (SELECT COUNT(*) FROM tomi_chat_messages x WHERE x.thread_id=t.id AND x.sender_id<>self.user_id AND x.sequence>self.last_read_seq AND x.deleted_at IS NULL) AS unread_count,
 (SELECT COUNT(*) FROM tomi_user_blocks b WHERE b.blocker_id=self.user_id AND b.blocked_id=u.id) AS blocked_by_me,
 ((SELECT COUNT(*) FROM tomi_user_blocks b WHERE b.blocker_id=u.id AND b.blocked_id=self.user_id)+(SELECT COUNT(*) FROM tomi_deleted_accounts d WHERE d.user_id=u.id)) AS blocked_by_peer
 FROM tomi_chat_threads t JOIN tomi_chat_members self ON self.thread_id=t.id AND self.user_id=?
 JOIN tomi_chat_members pm ON pm.thread_id=t.id AND pm.user_id<>self.user_id JOIN tomi_users u ON u.id=pm.user_id
 ${avatarJoins} LEFT JOIN tomi_chat_messages lm ON lm.thread_id=t.id AND lm.sequence=t.next_seq `;
const messages=`SELECT shared_link.message_id AS shared_message_id,shared_link.post_id AS shared_post_id,sp.id AS shared_available_id,sp.body AS shared_body,m.*,COALESCE(meta.revision,0) AS meta_revision,u.username,u.display_name,u.avatar_preset,doc.file_name AS document_name,doc.byte_length AS document_bytes,doc.object_key AS document_key,sticker.sticker_id,media.object_key,media.width,media.height,audio.object_key AS audio_key,audio.duration_ms,video.object_key AS video_key,(SELECT vr.object_key FROM tomi_video_renditions vr WHERE vr.upload_id=video.id AND vr.height=540) AS video_540_key,(SELECT vr.object_key FROM tomi_video_renditions vr WHERE vr.upload_id=video.id AND vr.height=720) AS video_720_key,(SELECT poster FROM tomi_video_posters vp WHERE vp.upload_id=video.id) AS video_poster,video.width AS video_width,video.height AS video_height,video.duration_ms AS video_duration${avatarColumns}
 FROM tomi_chat_messages m JOIN tomi_users u ON u.id=m.sender_id LEFT JOIN tomi_chat_documents cd ON cd.message_id=m.id LEFT JOIN tomi_private_uploads doc ON doc.id=cd.upload_id LEFT JOIN tomi_chat_stickers sticker ON sticker.message_id=m.id LEFT JOIN tomi_chat_message_meta meta ON meta.message_id=m.id LEFT JOIN tomi_image_uploads media ON media.id=m.image_upload_id LEFT JOIN tomi_chat_audio ca ON ca.message_id=m.id LEFT JOIN tomi_audio_uploads audio ON audio.id=ca.upload_id LEFT JOIN tomi_chat_video cv ON cv.message_id=m.id LEFT JOIN tomi_video_uploads video ON video.id=cv.upload_id LEFT JOIN tomi_post_shares shared_link ON shared_link.message_id=m.id LEFT JOIN tomi_posts sp ON sp.id=shared_link.post_id AND NOT EXISTS(SELECT 1 FROM tomi_content_moderation x WHERE x.target_type='post' AND x.target_id=sp.id AND x.hidden=1) AND NOT EXISTS(SELECT 1 FROM tomi_account_restrictions x WHERE x.user_id=sp.user_id AND x.suspended=1) ${avatarJoins} `;
export function createChat({database,storage,avatarStorage=storage,readJson,respond,limit,userById,enqueuePush=async()=>{},accountGate=async()=>{},groups,privateMedia,shareRequestCount=async()=>0}){
 let realtime;
 const threadJson=(r,viewer)=>({secureEnabled:!!Number(r.secure_enabled),id:r.id,peer:{id:r.peer_id,username:r.username,displayName:r.display_name,avatarPreset:r.avatar_preset,...avatarFields(r,avatarStorage)},updatedAt:r.updated_at,
  personalPinned:!!Number(r.personal_pinned),archived:!!Number(r.personal_archived),markedUnread:!!Number(r.marked_unread),unreadCount:Number(r.unread_count),sequence:Number(r.next_seq),myReadSequence:Number(r.last_read_seq),peerReadSequence:Number(r.peer_read_seq),
  lastMessage:r.last_created?(r.last_deleted?'تم حذف الرسالة':r.last_body||(Number(r.last_sticker)?'ملصق':Number(r.last_file)?'📎 مستند':Number(r.last_audio)?'🎤 رسالة صوتية':Number(r.last_video)?'🎬 فيديو':'📷 صورة')):'',lastMessageAt:r.last_created||null,lastMessageIsMine:r.last_sender===viewer,fileUploadEnabled:!!storage,
  blockedByMe:Number(r.blocked_by_me)>0,blockedByPeer:Number(r.blocked_by_peer)>0,imageUploadEnabled:!!storage,audioUploadEnabled:!!storage,videoUploadEnabled:!!storage,pinnedMessageId:r.pinned_message_id??null,featuresRevision:Number(r.features_revision??0)});
 const messageJson=(r,viewer)=>({id:r.id,conversationId:r.thread_id,sequence:Number(r.sequence),requestId:r.sender_id===viewer?r.request_id:null,
  ...r.extra,sharedPost:!r.deleted_at&&r.shared_message_id?{id:r.shared_post_id??null,available:!!r.shared_available_id,text:r.shared_available_id?r.shared_body:''}:null,stickerId:r.deleted_at?null:r.sticker_id??null,file:!r.deleted_at&&r.document_key?{url:storage?.privateReadUrl(r.document_key)??null,name:r.document_name,byteLength:Number(r.document_bytes)}:null,text:r.deleted_at?'':r.body,createdAt:r.created_at,deleted:!!r.deleted_at,isMine:r.sender_id===viewer,
  author:{id:r.sender_id,username:r.username,displayName:r.display_name,avatarPreset:r.avatar_preset,...avatarFields(r,avatarStorage)},
  video:!r.deleted_at&&r.video_key?{poster:r.video_poster??null,url:storage?.privateReadUrl(r.video_key)??null,width:Number(r.video_width),height:Number(r.video_height),durationMs:Number(r.video_duration)}:null,
  audio:!r.deleted_at&&r.audio_key?{url:storage?.privateReadUrl(r.audio_key)??null,durationMs:Number(r.duration_ms)}:null,
  image:!r.deleted_at&&r.object_key?{url:storage?.privateReadUrl(r.object_key)??null,width:Number(r.width),height:Number(r.height)}:null});
 async function thread(viewer,threadId,db=database){const{rows}=await db.query(threads+'WHERE t.id=?',[viewer,threadId]);if(!rows[0])fail(404,'CHAT_NOT_FOUND','المحادثة غير موجودة.');return rows[0];}
 async function message(viewer,threadId,messageId){const{rows}=await database.query(messages+'WHERE m.thread_id=? AND m.id=?',[threadId,messageId]);if(!rows[0])fail(404,'MESSAGE_NOT_FOUND','الرسالة غير موجودة.');return messageJson((await tools.enrich(rows,viewer))[0],viewer);}
 async function pair(db,viewer,target){await accountGate(db,target);if((await db.query('SELECT 1 FROM tomi_deleted_accounts WHERE user_id=?',[target])).rows.length)fail(410,'ACCOUNT_DELETED','حُذف الحساب ولا يمكن مراسلته.');const[low,high]=[viewer,target].sort(),stamp=now();const{rows}=await db.query(`INSERT INTO tomi_chat_threads(id,low_user_id,high_user_id,created_at,updated_at) VALUES(?,?,?,?,?)
  ON CONFLICT(low_user_id,high_user_id) DO UPDATE SET updated_at=tomi_chat_threads.updated_at RETURNING id`,[randomUUID(),low,high,stamp,stamp]);
  for(const user of [low,high])await db.query('INSERT INTO tomi_chat_members(thread_id,user_id) VALUES(?,?) ON CONFLICT(thread_id,user_id) DO NOTHING',[rows[0].id,user]);return rows[0].id;}
 async function lock(db,viewer,threadId){const r=await db.query('UPDATE tomi_chat_threads SET updated_at=updated_at WHERE id=? AND (low_user_id=? OR high_user_id=?) RETURNING id',[threadId,viewer,viewer]);if(!r.rows[0])fail(404,'CHAT_NOT_FOUND','المحادثة غير موجودة.');return thread(viewer,threadId,db);}
 const sending=(r,secure=false)=>{if(!secure&&Number(r.secure_enabled))fail(409,'SECURE_REQUIRED','هذه المحادثة مشفرة؛ حدّث التطبيق وافتح واجهتها المشفرة.');if(Number(r.blocked_by_me)||Number(r.blocked_by_peer))fail(403,'CHAT_BLOCKED','المراسلة غير متاحة مع هذا المستخدم.');};
 const notify=(r,type,extra={})=>realtime?.emit([r.low_user_id,r.high_user_id],{type,conversationId:r.id,...extra});
 async function existing(db,viewer,requestId,hash){const{rows}=await db.query('SELECT id,payload_hash FROM tomi_chat_messages WHERE sender_id=? AND request_id=?',[viewer,requestId]);if(!rows[0])return null;if(rows[0].payload_hash!==hash)fail(409,'REQUEST_CHANGED','محتوى الرسالة تغيّر؛ أرسل رسالة جديدة.');return rows[0].id;}
 const tools=createChatTools({database,thread,lock,sending,notify,id,fields,message,messageJson,messagesSql:messages,threadJson,respond,readJson,limit});
 async function handle(request,response,url,current){const path=url.pathname,method=request.method,viewer=current.id;
  if(await tools.handle(request,response,url,current))return true;
  const muteRoute=path.match(/^\/v1\/chats\/([a-f0-9-]{36})\/mute$/);
  if(muteRoute&&(method==='GET'||method==='PUT')){const tid=id(muteRoute[1]);await thread(viewer,tid);if(method==='PUT'){await limit('chat-mute:'+viewer,30);const d=await readJson(request);fields(d,['muted']);if(typeof d.muted!=='boolean')fail(400,'VALIDATION','قيمة الكتم غير صحيحة.');if(d.muted)await database.query('INSERT INTO tomi_muted_chats(user_id,thread_id) VALUES(?,?) ON CONFLICT(user_id,thread_id) DO NOTHING',[viewer,tid]);else await database.query('DELETE FROM tomi_muted_chats WHERE user_id=? AND thread_id=?',[viewer,tid]);}respond(response,200,{muted:!!(await database.query('SELECT 1 FROM tomi_muted_chats WHERE user_id=? AND thread_id=?',[viewer,tid])).rows.length});return true;}
  if(method==='GET'&&path==='/v1/chats'){
   const size=pageNumber(url,'limit',30,50);if(!size)fail(400,'VALIDATION','حجم الصفحة غير صحيح.');
   const values=[viewer],conditions=['self.visible=1'],raw=url.searchParams.get('cursor');
   let cursor=null;if(raw){try{if(raw.length>200)throw Error();cursor=JSON.parse(Buffer.from(raw,'base64url').toString());if(!uuid.test(cursor.id)||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(cursor.time)||!Number.isFinite(Date.parse(cursor.time)))throw Error();}catch{fail(400,'VALIDATION','الصفحة غير صحيحة.');}
    conditions.push('(t.updated_at<? OR (t.updated_at=? AND t.id<?))');values.push(cursor.time,cursor.time,cursor.id);}
   values.push(size+1);const{rows}=await database.query(threads+'WHERE '+conditions.join(' AND ')+' ORDER BY t.updated_at DESC,t.id DESC LIMIT ?',values),items=rows.slice(0,size),last=items.at(-1);
   const total=await database.query(`SELECT COUNT(*) AS total FROM tomi_chat_messages m JOIN tomi_chat_members member ON member.thread_id=m.thread_id AND member.user_id=?
    WHERE member.visible=1 AND m.sender_id<>? AND m.sequence>member.last_read_seq AND m.deleted_at IS NULL`,[viewer,viewer]);
   const combined=[...items.map(r=>threadJson(r,viewer)),...await groups.list(viewer,cursor,size+1)].sort((a,b)=>b.updatedAt.localeCompare(a.updatedAt)||b.id.localeCompare(a.id)),page=combined.slice(0,size),tail=page.at(-1);respond(response,200,{shareRequestsCount:await shareRequestCount(viewer),removedConversationIds:await groups.removed(viewer),conversations:page,totalUnread:Number(total.rows[0].total)+await groups.unread(viewer),nextCursor:combined.length>size||rows.length>size?Buffer.from(JSON.stringify({time:tail.updatedAt,id:tail.id})).toString('base64url'):null});return true;
  }
  if(method==='POST'&&path==='/v1/chats'){
   await limit('chat-open:'+viewer,30);const d=await readJson(request);fields(d,['userId']);const target=id(d.userId);if(target===viewer)fail(400,'SELF_CHAT','اختَر حسابًا آخر.');await userById(target,viewer);
   const threadId=await database.transaction(async db=>{await requireContact(db,target,viewer,'messages');const tid=await pair(db,viewer,target);sending(await thread(viewer,tid,db),true);await db.query('UPDATE tomi_chat_members SET visible=1 WHERE thread_id=? AND user_id=?',[tid,viewer]);return tid;});
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
  const documentRoute=path.match(/^\/v1\/chats\/([a-f0-9-]{36})\/files$/);
  if(method==='POST'&&documentRoute){const tid=id(documentRoute[1]),r=await thread(viewer,tid);sending(r);await limit('chat-media:'+viewer,10);await limit('daily-chat-media:'+viewer,100,86400000);respond(response,201,await privateMedia.prepare(viewer,tid,'file',await readJson(request)));return true;}
  const match=path.match(/^\/v1\/chats\/([a-f0-9-]{36})(\/messages|\/images|\/audio|\/videos|\/read)?$/);
  if(match){const tid=id(match[1]),action=match[2]||'',row=await thread(viewer,tid);
   if(method==='GET'&&!action){respond(response,200,{conversation:threadJson(row,viewer)});return true;}
   if(method==='GET'&&action==='/messages'){
    const size=pageNumber(url,'limit',40,100),after=pageNumber(url,'after',null),before=pageNumber(url,'before',null);
    if(!size||(after!==null&&before!==null))fail(400,'VALIDATION','الصفحة غير صحيحة.');const values=[tid],conditions=['m.thread_id=?'];
    if(after!==null){conditions.push('m.sequence>?');values.push(after);}if(before!==null){conditions.push('m.sequence<?');values.push(before);}values.push(size+1);
    const{rows}=await database.query(messages+'WHERE '+conditions.join(' AND ')+' ORDER BY m.sequence '+(after===null?'DESC':'ASC')+' LIMIT ?',values),selected=rows.slice(0,size),items=after===null?selected.reverse():selected;
    respond(response,200,{conversation:threadJson(row,viewer),messages:(await tools.enrich(items,viewer)).map(r=>messageJson(r,viewer)),nextBefore:after===null&&rows.length>size?Number(items[0].sequence):null,nextAfter:after!==null&&rows.length>size?Number(items.at(-1).sequence):null});return true;
   }
   if(method==='POST'&&['/audio','/images','/videos'].includes(action)){
    if(!storage)fail(503,'MEDIA_DISABLED','إرسال الوسائط غير متاح.');sending(row);
    await limit('chat-media:'+viewer,10);await limit('daily-chat-media:'+viewer,100,86400000);
    const d=await readJson(request);fields(d,['contentType','byteLength','contentMd5','durationMs','requestId','contentSha256']);
    const audio=action==='/audio',video=action==='/videos',cap=audio?maxAudioBytes:video?maxVideoBytes:maxImageBytes;
    if(!Number.isInteger(d.byteLength)||d.byteLength<13||d.byteLength>cap||typeof d.contentMd5!=='string'||!/^[A-Za-z0-9+/]{22}==$/.test(d.contentMd5)||
      (audio?d.contentType!=='audio/mp4'||!Number.isInteger(d.durationMs)||d.durationMs<100||d.durationMs>maxAudioDurationMs:video?d.contentType!=='video/mp4':!Object.hasOwn(imageTypes,d.contentType)))fail(400,'INVALID_MEDIA','اختَر صورة حتى10 MB، أو صوت حتى6 MB وخمس دقائق، أو فيديو MP4 حتى25 MB وثلاث دقائق.');
    const table=audio?'tomi_audio_uploads':video?'tomi_video_uploads':'tomi_image_uploads';
    const prepared=await prepareIntent({database,viewer,scope:action+':'+tid,table,d,storage,create:async db=>{
     const count=(await db.query("SELECT COUNT(*) AS total FROM "+table+" WHERE user_id=? AND state='pending' AND expires_at>?",[viewer,now()])).rows[0];
     if(Number(count.total)>=10)fail(429,'RATE_LIMITED','عندك ملفات قيد الرفع؛ أكملها أولًا.');
     const uid=randomUUID(),u={id:uid,user_id:viewer,thread_id:tid,object_key:`tomi/chat-${audio?'audio':video?'videos':'images'}/${tid}/${viewer}/${uid}.${audio?'m4a':video?'mp4':imageTypes[d.contentType]}`,content_type:d.contentType,byte_length:d.byteLength,content_md5:d.contentMd5,duration_ms:d.durationMs};
     const cols=audio?'id,user_id,thread_id,object_key,content_type,byte_length,content_md5,duration_ms,created_at,expires_at':video?'id,user_id,thread_id,object_key,content_type,byte_length,content_md5,created_at,expires_at':'id,user_id,object_key,content_type,byte_length,content_md5,created_at,expires_at';
     const values=[uid,viewer,...(audio||video?[tid]:[]),u.object_key,d.contentType,d.byteLength,d.contentMd5,...(audio?[d.durationMs]:[]),now(),new Date(Date.now()+86400000).toISOString()];
     await db.query('INSERT INTO '+table+'('+cols+') VALUES('+values.map(()=>'?').join(',')+')',values);return u;
    }});respond(response,201,prepared);return true;
   }
   if(method==='POST'&&action==='/messages'){
    await limit('chat-send:'+viewer,60);const d=await readJson(request);fields(d,['text','requestId','imageUploadId','audioUploadId','videoUploadId','replyToId','attachmentSha256','fileUploadId','stickerId']);if(d.text!==undefined&&typeof d.text!=='string')fail(400,'VALIDATION','النص غير صحيح.');
    const text=(d.text||'').trim(),requestId=id(d.requestId),uploadId=d.imageUploadId==null?null:id(d.imageUploadId),audioId=d.audioUploadId==null?null:id(d.audioUploadId),videoId=d.videoUploadId==null?null:id(d.videoUploadId),replyId=d.replyToId==null?null:id(d.replyToId),sha=d.attachmentSha256??null,fileId=d.fileUploadId==null?null:id(d.fileUploadId),stickerId=d.stickerId??null;
    if(stickerId!==null&&!stickerIds.includes(stickerId))fail(400,'VALIDATION','الملصق غير صحيح.');
    const kind=uploadId?'image':audioId?'audio':videoId?'video':fileId?'file':null;
    if(sha!==null&&(typeof sha!=='string'||!/^[a-f0-9]{64}$/.test(sha))||sha&&!kind||(videoId||fileId)&&!sha)fail(400,'VALIDATION','بصمة ملف الإرسال غير صحيحة.');
    const hash=digest(JSON.stringify(stickerId||fileId?['v3',tid,text,kind,sha,replyId,stickerId]:sha||replyId||videoId?['v2',tid,text,kind,sha,replyId]:audioId?[tid,text,uploadId,audioId]:[tid,text,uploadId]));
    if([...text].length>2000||(!text&&!kind&&!stickerId)||[uploadId,audioId,videoId,fileId,stickerId].filter(Boolean).length>1)fail(400,'VALIDATION','اختَر نصًا أو ملفًا واحدًا؛ النص حتى2000 حرف.');
    let previous=await existing(database,viewer,requestId,hash),dimensions,audioInfo,videoInfo,fileInfo;
    try{
    if(!previous&&fileId){sending(row);fileInfo=await privateMedia.verify(viewer,tid,fileId,sha);if(fileInfo.kind!=='file')fail(400,'VALIDATION','نوع الملف غير صحيح.');}
    if(!previous&&uploadId){sending(row);if(!storage)fail(503,'IMAGES_DISABLED','إرسال الصور غير متاح.');const{rows}=await database.query('SELECT * FROM tomi_image_uploads WHERE id=? AND user_id=?',[uploadId,viewer]);const u=rows[0];
     if(!u||u.state!=='pending'||u.expires_at<=now()||!u.object_key.startsWith(`tomi/chat-images/${tid}/${viewer}/`))fail(400,'UPLOAD_INVALID','الصورة انتهت أو استُخدمت؛ جهّزها مرة ثانية.');dimensions=await storage.verify(await uploadWithDigest(database,u,sha));}
    if(!previous&&audioId){sending(row);if(!storage)fail(503,'AUDIO_DISABLED','إرسال الصوت غير متاح.');const{rows}=await database.query('SELECT * FROM tomi_audio_uploads WHERE id=? AND user_id=? AND thread_id=?',[audioId,viewer,tid]),u=rows[0];if(!u||u.state!=='pending'||u.expires_at<=now())fail(400,'UPLOAD_INVALID','التسجيل انتهى أو استُخدم.');audioInfo=await storage.verifyAudio(await uploadWithDigest(database,u,sha));if(Math.abs(audioInfo.durationMs-Number(u.duration_ms))>2000)fail(400,'INVALID_AUDIO','مدة التسجيل غير صحيحة.');}
    if(!previous&&videoId){sending(row);if(!storage)fail(503,'VIDEO_DISABLED','إرسال الفيديو غير متاح.');const u=(await database.query('SELECT * FROM tomi_video_uploads WHERE id=? AND user_id=? AND thread_id=?',[videoId,viewer,tid])).rows[0];if(!u||u.state!=='pending'||u.expires_at<=now())fail(400,'UPLOAD_INVALID','الفيديو انتهى أو استُخدم.');videoInfo=await storage.verifyVideo(await uploadWithDigest(database,u,sha));}
    }catch(error){
     if(error.code!=='UPLOAD_INVALID')throw error;
     // Its twin can commit between our receipt lookup and media validation.
     // Reconcile only this actor's matching nonce; all other errors stay errors.
     previous=await existing(database,viewer,requestId,hash);if(!previous)throw error;
    }
    let saved;try{saved=await database.transaction(async db=>{const locked=await lock(db,viewer,tid);previous=await existing(db,viewer,requestId,hash);if(previous)return{id:previous,repeated:true,row:locked};await requireContact(db,locked.low_user_id===viewer?locked.high_user_id:locked.low_user_id,viewer,'messages');sending(locked);
     await tools.validateReply(db,tid,replyId);
     const stamp=now(),mid=randomUUID(),changed=await db.query('UPDATE tomi_chat_threads SET next_seq=next_seq+1,updated_at=? WHERE id=? RETURNING next_seq',[stamp,tid]);
     await db.query('INSERT INTO tomi_chat_messages(id,thread_id,sender_id,sequence,request_id,payload_hash,body,image_upload_id,created_at) VALUES(?,?,?,?,?,?,?,?,?)',[mid,tid,viewer,integer(Number(changed.rows[0].next_seq)),requestId,hash,text,uploadId,stamp]);
     if(stickerId)await db.query('INSERT INTO tomi_chat_stickers(message_id,sticker_id) VALUES(?,?)',[mid,stickerId]);
     if(fileId){await privateMedia.attach(db,fileInfo);await db.query('INSERT INTO tomi_chat_documents(message_id,upload_id) VALUES(?,?)',[mid,fileId]);}
     if(uploadId){const result=await db.query("UPDATE tomi_image_uploads SET state='attached',width=?,height=? WHERE id=? AND user_id=? AND state='pending' AND expires_at>?",[dimensions.width,dimensions.height,uploadId,viewer,now()]);if(result.changes!==1)fail(409,'UPLOAD_INVALID','الصورة انتهت أو استُخدمت.');}
     if(audioId){const result=await db.query("UPDATE tomi_audio_uploads SET state='attached',duration_ms=? WHERE id=? AND user_id=? AND thread_id=? AND state='pending' AND expires_at>?",[audioInfo.durationMs,audioId,viewer,tid,now()]);if(result.changes!==1)fail(409,'UPLOAD_INVALID','التسجيل انتهى أو استُخدم.');await db.query('INSERT INTO tomi_chat_audio(message_id,upload_id) VALUES(?,?)',[mid,audioId]);}
     if(videoId){const changed=await db.query("UPDATE tomi_video_uploads SET state='attached',width=?,height=?,duration_ms=? WHERE id=? AND user_id=? AND thread_id=? AND state='pending' AND expires_at>?",[videoInfo.width,videoInfo.height,videoInfo.durationMs,videoId,viewer,tid,now()]);if(changed.changes!==1)fail(409,'UPLOAD_INVALID','الفيديو انتهى أو استُخدم.');await db.query('INSERT INTO tomi_chat_video(message_id,upload_id) VALUES(?,?)',[mid,videoId]);}
     await db.query('INSERT INTO tomi_chat_message_meta(message_id,reply_to_id,media_sha256) VALUES(?,?,?)',[mid,replyId,sha]);
     if(!(await db.query('SELECT 1 FROM tomi_muted_chats WHERE user_id=? AND thread_id=?',[locked.low_user_id===viewer?locked.high_user_id:locked.low_user_id,tid])).rows.length)await enqueuePush(db,{messageId:mid,recipientId:locked.low_user_id===viewer?locked.high_user_id:locked.low_user_id,threadId:tid});
     await db.query('UPDATE tomi_chat_members SET visible=1 WHERE thread_id=?',[tid]);return{id:mid,repeated:false,row:locked};
    });}catch(error){if(!isUniqueConflict(error))throw error;const mid=await existing(database,viewer,requestId,hash);if(!mid)fail(409,'UPLOAD_INVALID','الصورة استُخدمت.');saved={id:mid,repeated:true,row};}
    const delivered=await message(viewer,tid,saved.id);
    if(!saved.repeated){
     realtime?.emit([viewer],{type:'chat.message',conversationId:tid,messageId:saved.id,message:delivered});
     realtime?.emit([saved.row.low_user_id===viewer?saved.row.high_user_id:saved.row.low_user_id],{type:'chat.message',conversationId:tid,messageId:saved.id,message:{...delivered,isMine:false,requestId:null}});
    }
    respond(response,saved.repeated?200:201,{message:delivered,conversation:threadJson(await thread(viewer,tid),viewer)});return true;
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
    if(!rows[0].deleted_at){await db.query("UPDATE tomi_chat_messages SET body='',image_upload_id=NULL,deleted_at=? WHERE id=?",[now(),mid]);await db.query('UPDATE tomi_chat_threads SET updated_at=? WHERE id=?',[now(),tid]);if(rows[0].image_upload_id)await db.query("UPDATE tomi_image_uploads SET state='deleting',expires_at=? WHERE id=?",[new Date(Date.now()+1200000).toISOString(),rows[0].image_upload_id]);}const audio=await db.query('SELECT upload_id FROM tomi_chat_audio WHERE message_id=?',[mid]);if(audio.rows[0]){await db.query('DELETE FROM tomi_chat_audio WHERE message_id=?',[mid]);await db.query("UPDATE tomi_audio_uploads SET state='deleting',expires_at=? WHERE id=?",[new Date(Date.now()+1200000).toISOString(),audio.rows[0].upload_id]);}const video=(await db.query('SELECT upload_id FROM tomi_chat_video WHERE message_id=?',[mid])).rows[0];if(video){await db.query('DELETE FROM tomi_chat_video WHERE message_id=?',[mid]);await db.query("UPDATE tomi_video_uploads SET state='deleting',expires_at=? WHERE id=?",[new Date(Date.now()+1200000).toISOString(),video.upload_id]);}
    const document=(await db.query('SELECT upload_id FROM tomi_chat_documents WHERE message_id=?',[mid])).rows[0];if(document){await db.query('DELETE FROM tomi_chat_documents WHERE message_id=?',[mid]);await db.query("UPDATE tomi_private_uploads SET state='deleting',expires_at=? WHERE id=?",[new Date(Date.now()+1200000).toISOString(),document.upload_id]);}await db.query('DELETE FROM tomi_e2ee_envelopes WHERE message_id=?',[mid]);await db.query("UPDATE tomi_e2ee_uploads SET state='deleting',expires_at=? WHERE message_id=?",[new Date(Date.now()+1200000).toISOString(),mid]);await db.query('DELETE FROM tomi_chat_stickers WHERE message_id=?',[mid]);
    await db.query('DELETE FROM tomi_chat_reactions WHERE message_id=?',[mid]);await db.query('DELETE FROM tomi_chat_pins WHERE thread_id=? AND message_id=?',[tid,mid]);await tools.bump(db,mid);await tools.bumpThread(db,tid);return r;});
   notify(row,'chat.deleted',{messageId:mid});respond(response,200,{message:await message(viewer,tid,mid),conversation:threadJson(await thread(viewer,tid),viewer)});return true;
  }
  return false;
 }
 async function prepareShared(db,sender,target){await requireContact(db,target,sender,'messages');const tid=await pair(db,sender,target),r=await lock(db,sender,tid);sending(r);return tid;}
 async function deliverShared(db,sender,target,postId,nonce){
  const tid=await prepareShared(db,sender,target),hash=digest(JSON.stringify(['shared-post',postId,target])),old=await existing(db,sender,nonce,hash);if(old)return{threadId:tid,messageId:old,replayed:true};
  const stamp=now(),mid=randomUUID(),r=(await db.query('UPDATE tomi_chat_threads SET next_seq=next_seq+1,updated_at=? WHERE id=? RETURNING next_seq',[stamp,tid])).rows[0];
  await db.query('INSERT INTO tomi_chat_messages(id,thread_id,sender_id,sequence,request_id,payload_hash,body,created_at) VALUES(?,?,?,?,?,?,?,?)',[mid,tid,sender,Number(r.next_seq),nonce,hash,'📎 منشور',stamp]);
  await db.query('INSERT INTO tomi_chat_message_meta(message_id) VALUES(?)',[mid]);
  await db.query('INSERT INTO tomi_post_shares(message_id,post_id) VALUES(?,?)',[mid,postId]);
  await db.query('UPDATE tomi_chat_members SET visible=1 WHERE thread_id=?',[tid]);
  if(!(await db.query('SELECT 1 FROM tomi_muted_chats WHERE user_id=? AND thread_id=?',[target,tid])).rows.length)await enqueuePush(db,{messageId:mid,recipientId:target,threadId:tid});return{threadId:tid,messageId:mid};
 }
 async function blockShared(db,viewer,target){const tid=await pair(db,viewer,target);await lock(db,viewer,tid);await db.query('INSERT INTO tomi_user_blocks(blocker_id,blocked_id,created_at) VALUES(?,?,?) ON CONFLICT(blocker_id,blocked_id) DO NOTHING',[viewer,target,now()]);return tid;}
 function attach(server,options){realtime=createRealtime({...options,server,limit,typing:async(viewer,tid,active,activity='typing')=>{if(await groups.typing(viewer,tid,active,activity))return;const r=await thread(viewer,id(tid));sending(r);realtime.emit([r.low_user_id===viewer?r.high_user_id:r.low_user_id],{type:'chat.typing',conversationId:tid,active,activity,userId:viewer,expiresAt:Date.now()+5000});}});}
 let cleaning=false;
 async function cleanup(){if(!storage||cleaning)return;cleaning=true;try{const{rows}=await database.query("SELECT id,object_key FROM tomi_audio_uploads WHERE state<>'attached' AND expires_at<=? ORDER BY expires_at LIMIT 20",[now()]);for(const u of rows)try{await abortMultipartUpload(database,storage,u.id,u.object_key);await storage.delete(u.object_key);await database.query("DELETE FROM tomi_audio_uploads WHERE id=? AND state<>'attached' AND expires_at<=?",[u.id,now()]);}catch{console.error('Audio cleanup deferred');}}finally{cleaning=false;}}
 return{secureAccess:async(viewer,tid,db=database)=>{const r=await thread(viewer,tid,db);return{blocked:!!(Number(r.blocked_by_me)||Number(r.blocked_by_peer)),low:r.low_user_id,high:r.high_user_id,other:r.low_user_id===viewer?r.high_user_id:r.low_user_id};},securePush:async(db,sender,tid,mid)=>{const r=await thread(sender,tid,db);const peer=r.low_user_id===sender?r.high_user_id:r.low_user_id;if(!(await db.query('SELECT 1 FROM tomi_muted_chats WHERE user_id=? AND thread_id=?',[peer,tid])).rows.length)await enqueuePush(db,{messageId:mid,recipientId:peer,threadId:tid});},handle,attach,prepareShared,deliverShared,blockShared,cleanup:async()=>{await privateMedia.cleanup();await cleanup();await cleanupVideos(database,storage,'tomi/chat-videos/');},emit:(ids,event)=>realtime?.emit(ids,event),invalidateSession:hash=>realtime?.invalidateSession(hash),invalidateUser:viewer=>realtime?.invalidateUser(viewer)};
}
