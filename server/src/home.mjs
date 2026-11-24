import {recordMentions} from './content_preferences.mjs';
import {randomUUID} from 'node:crypto';
import {ApiError,digest,isUniqueConflict,validateUsername} from './security.mjs';
import {uploadWithDigest,validUuid} from './media_intents.mjs';
import {avatarFields,avatarJoins,avatarColumns} from './avatars.mjs';
const stamp=(delta=0)=>new Date(Date.now()+delta).toISOString();
const visible=`NOT EXISTS(SELECT 1 FROM tomi_account_restrictions a WHERE a.user_id=s.user_id AND a.suspended=1)
 AND NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts d WHERE d.user_id=s.user_id)
 AND NOT EXISTS(SELECT 1 FROM tomi_user_blocks b WHERE (b.blocker_id=? AND b.blocked_id=s.user_id) OR (b.blocker_id=s.user_id AND b.blocked_id=?))
 AND (NOT EXISTS(SELECT 1 FROM tomi_story_options o WHERE o.story_id=s.id AND o.audience='followers') OR s.user_id=? OR EXISTS(SELECT 1 FROM tomi_follows f WHERE f.follower_id=? AND f.following_id=s.user_id))`;
const select=`SELECT s.*,u.username,u.display_name,u.avatar_preset${avatarColumns},m.object_key,m.width,m.height,
 v.object_key video_key,(SELECT vr.object_key FROM tomi_video_renditions vr WHERE vr.upload_id=v.id AND vr.height=540) AS video_540_key,(SELECT vr.object_key FROM tomi_video_renditions vr WHERE vr.upload_id=v.id AND vr.height=720) AS video_720_key,(SELECT poster FROM tomi_video_posters vp WHERE vp.upload_id=v.id) AS video_poster,v.width video_width,v.height video_height,v.duration_ms,
 (SELECT COUNT(*) FROM tomi_story_views z WHERE z.story_id=s.id AND z.user_id=?) seen,
 (SELECT COUNT(*) FROM tomi_story_views z WHERE z.story_id=s.id) views_count
 FROM tomi_stories s JOIN tomi_users u ON u.id=s.user_id
 LEFT JOIN tomi_image_uploads m ON m.id=s.image_upload_id LEFT JOIN tomi_video_uploads v ON v.id=s.video_upload_id ${avatarJoins}`;
export const activityVisible=`NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts d WHERE d.user_id=n.actor_id)
 AND NOT EXISTS(SELECT 1 FROM tomi_account_restrictions r WHERE r.user_id=n.actor_id AND r.suspended=1)
 AND NOT EXISTS(SELECT 1 FROM tomi_user_blocks b WHERE (b.blocker_id=n.recipient_id AND b.blocked_id=n.actor_id) OR (b.blocker_id=n.actor_id AND b.blocked_id=n.recipient_id))
 AND (n.kind='follow' OR EXISTS(SELECT 1 FROM tomi_posts p WHERE p.id=n.target_id
 AND NOT EXISTS(SELECT 1 FROM tomi_content_moderation m WHERE m.target_type='post' AND m.target_id=p.id AND m.hidden=1)))`;
export async function recordActivity(db,{recipientId,actorId,kind,targetId,sourceKey},accountGate) {
 if(recipientId===actorId)return;
 if(accountGate)await accountGate(db,recipientId);
 if((await db.query('SELECT 1 FROM tomi_deleted_accounts WHERE user_id IN (?,?)',[recipientId,actorId])).rows.length)return;
 if((await db.query('SELECT 1 FROM tomi_user_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)',[recipientId,actorId,actorId,recipientId])).rows.length)return;
 await db.query(`INSERT INTO tomi_activity(id,recipient_id,actor_id,kind,target_id,dedupe_key,created_at,next_at)
 VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(dedupe_key) DO NOTHING`,[randomUUID(),recipientId,actorId,kind,targetId,sourceKey,stamp(),stamp()]);
}
function fields(d,allowed){if(Object.keys(d).some(k=>!allowed.includes(k)))throw new ApiError(400,'VALIDATION','طلب غير صحيح.');}
function size(url){const raw=url.searchParams.get('limit')??'24';if(!/^\d{1,2}$/.test(raw)||+raw<1||+raw>50)throw new ApiError(400,'VALIDATION','حجم الصفحة غير صحيح.');return +raw;}
export function createHome({database,storage,accountGate,readJson,respond,limit,userById}) {
 function story(r,viewer){return {id:r.id,text:r.body,createdAt:r.created_at,expiresAt:r.expires_at,
 author:{id:r.user_id,username:r.username,displayName:r.display_name,avatarPreset:r.avatar_preset,...avatarFields(r,storage)},
 image:r.object_key?{url:storage?.readUrl(r.object_key)??null,width:Number(r.width),height:Number(r.height)}:null,
 video:r.video_key?{renditions:[540,720].filter(h=>r['video_'+h+'_key']).map(h=>({height:h,url:storage?.readUrl(r['video_'+h+'_key'])??null})),poster:r.video_poster??null,url:storage?.readUrl(r.video_key)??null,width:Number(r.video_width),height:Number(r.video_height),durationMs:Number(r.duration_ms)}:null,
 seen:Number(r.seen)>0,isMine:r.user_id===viewer,viewsCount:r.user_id===viewer?Number(r.views_count):null};}
 async function one(id,viewer,db=database){const r=(await db.query(select+' WHERE s.id=? AND s.expires_at>? AND '+visible,[viewer,id,stamp(),viewer,viewer,viewer,viewer])).rows[0];if(!r)throw new ApiError(404,'STORY_NOT_FOUND','انتهت الستوري أو لم تعد متاحة.');return story(r,viewer);}
 async function remove(db,r){if(!r)return;await db.query('DELETE FROM tomi_stories WHERE id=?',[r.id]);for(const [id,table] of [[r.image_upload_id,'tomi_image_uploads'],[r.video_upload_id,'tomi_video_uploads']])if(id)await db.query("UPDATE "+table+" SET state='deleting',expires_at=? WHERE id=?",[stamp(20*60000),id]);}
 async function handle(request,response,url,current){const path=url.pathname,method=request.method,viewer=current.id;
 const storyReceipt=path.match(/^\/v1\/stories\/requests\/([a-f0-9-]{36})$/);
 if(method==='GET'&&storyReceipt){const r=(await database.query('SELECT story_id FROM tomi_story_receipts WHERE user_id=? AND request_id=?',[viewer,storyReceipt[1]])).rows[0];if(!r)throw new ApiError(404,'REQUEST_NOT_FOUND','لا يوجد نشر بهذا الطلب.');try{respond(response,200,{story:await one(r.story_id,viewer)});}catch(e){if(e.code==='STORY_NOT_FOUND')throw new ApiError(410,'REQUEST_REMOVED','الستوري السابقة انتهت أو حُذفت.');throw e;}return true;}
 if(method==='GET'&&path==='/v1/stories'){
  const userId=url.searchParams.get('userId');if(userId&&!validUuid(userId))throw new ApiError(400,'VALIDATION','الحساب غير صحيح.');
  const users=userId?[{user_id:userId}]:(await database.query(`SELECT s.user_id,MAX(s.created_at) latest FROM tomi_stories s WHERE s.expires_at>? AND ${visible}
   AND (EXISTS(SELECT 1 FROM tomi_story_options o WHERE o.story_id=s.id AND o.audience='public') OR s.user_id=? OR EXISTS(SELECT 1 FROM tomi_follows f WHERE f.follower_id=? AND f.following_id=s.user_id)) GROUP BY s.user_id ORDER BY latest DESC,s.user_id LIMIT 100`,[stamp(),viewer,viewer,viewer,viewer,viewer,viewer])).rows;
  const groups=[];for(const u of users){const rows=(await database.query(select+' WHERE s.user_id=? AND s.expires_at>? AND '+visible+(userId?'':" AND (EXISTS(SELECT 1 FROM tomi_story_options o WHERE o.story_id=s.id AND o.audience='public') OR s.user_id=? OR EXISTS(SELECT 1 FROM tomi_follows f WHERE f.follower_id=? AND f.following_id=s.user_id))")+' ORDER BY s.created_at,s.id LIMIT 50',[viewer,u.user_id,stamp(),viewer,viewer,viewer,viewer,...(userId?[]:[viewer,viewer])])).rows;if(rows.length)groups.push({author:story(rows[0],viewer).author,stories:rows.map(r=>story(r,viewer))});}
  groups.sort((a,b)=>Number(b.author.id===viewer)-Number(a.author.id===viewer)||Number(a.stories.every(s=>s.seen))-Number(b.stories.every(s=>s.seen)));
  respond(response,200,{groups,imageUploadEnabled:!!storage,videoUploadEnabled:!!storage});return true;
 }
 if(method==='POST'&&path==='/v1/stories'){
  await limit('stories:'+viewer,30);const d=await readJson(request);fields(d,['requestId','text','imageUploadId','videoUploadId','attachmentSha256','audience']);
  const audience=d.audience??'followers';if(!['public','followers'].includes(audience))throw new ApiError(400,'VALIDATION','الجمهور غير صحيح.');
  const text=(typeof d.text==='string'?d.text:'').trim(),image=d.imageUploadId??null,video=d.videoUploadId??null,sha=d.attachmentSha256??null;
  if(!validUuid(d.requestId)||d.text!==undefined&&typeof d.text!=='string'||[...text].length>500||image!==null&&!validUuid(image)||video!==null&&!validUuid(video)||image&&video||!text&&!image&&!video||!!(image||video)!==!!sha||sha&&!/^[a-f0-9]{64}$/.test(sha))throw new ApiError(400,'VALIDATION','اختَر صورة أو فيديو أو نصًا حتى500 حرف.');
  const hash=digest(JSON.stringify([text,image,video,sha,...(audience==='public'?['public']:[])]));
  async function prior(db=database){const r=(await db.query('SELECT * FROM tomi_story_receipts WHERE user_id=? AND request_id=?',[viewer,d.requestId])).rows[0];if(!r)return null;if(r.payload_hash!==hash)throw new ApiError(409,'REQUEST_CHANGED','تغيّر محتوى الطلب؛ استخدم طلبًا جديدًا.');return one(r.story_id,viewer,db);}
  const old=await prior();if(old){respond(response,200,{story:old});return true;}
  const media=image||video,table=video?'tomi_video_uploads':'tomi_image_uploads';let dimensions;
  if(media){if(!storage)throw new ApiError(503,'MEDIA_DISABLED','رفع الوسائط غير متاح حاليًا.');const row=(await database.query('SELECT * FROM '+table+' WHERE id=? AND user_id=?',[media,viewer])).rows[0];if(!row||row.state!=='pending'||row.expires_at<=stamp()||!row.object_key.startsWith('tomi/posts/'+viewer+'/')){
    // A concurrent copy may have committed its receipt after the first lookup
    // and before this upload read. Attached media and receipt commit together.
    const replay=await prior();if(replay){respond(response,200,{story:replay});return true;}
    throw new ApiError(400,'UPLOAD_INVALID','الملف منتهي أو استُخدم؛ اختَره مجددًا.');
   }const checked=await uploadWithDigest(database,row,sha);dimensions=video?await storage.verifyVideo(checked):await storage.verify(checked);if(video&&dimensions.durationMs>60000)throw new ApiError(400,'STORY_DURATION','فيديو الستوري حتى60 ثانية.');}
  let id=randomUUID();try{await database.transaction(async db=>{
   await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=?',[viewer]);
   const replay=await prior(db);if(replay){id=replay.id;return;}
   const count=(await db.query('SELECT COUNT(*) n FROM tomi_stories WHERE user_id=? AND expires_at>?',[viewer,stamp()])).rows[0];if(Number(count.n)>=50)throw new ApiError(429,'STORY_LIMIT','عندك50 ستوري فعّالة؛ احذف واحدة أو انتظر انتهاءها.');
   if(media){const changed=await db.query("UPDATE "+table+" SET state='attached',width=?,height=?"+(video?',duration_ms=?':'')+" WHERE id=? AND user_id=? AND state='pending' AND expires_at>? RETURNING id",[dimensions.width,dimensions.height,...(video?[dimensions.durationMs]:[]),media,viewer,stamp()]);if(!changed.rows.length)throw new ApiError(409,'UPLOAD_INVALID','الملف سبق استعماله.');}
   const createdAt=stamp(),expiresAt=new Date(Date.parse(createdAt)+86400000).toISOString();
   await db.query('INSERT INTO tomi_stories(id,user_id,request_id,body,image_upload_id,video_upload_id,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?)',[id,viewer,d.requestId,text,image,video,createdAt,expiresAt]);
   await recordMentions(db,{actor:viewer,text,kind:'mention_story',targetId:id,audience,gate:accountGate});
   await db.query('INSERT INTO tomi_story_options(story_id,audience) VALUES(?,?)',[id,audience]);
   await db.query('INSERT INTO tomi_story_receipts(user_id,request_id,story_id,payload_hash,created_at) VALUES(?,?,?,?,?)',[viewer,d.requestId,id,hash,stamp()]);
  });}catch(e){if(!isUniqueConflict(e)&&e.code!=='UPLOAD_INVALID')throw e;const replay=await prior();if(!replay)throw e;id=replay.id;}
  respond(response,201,{story:await one(id,viewer)});return true;
 }
 const sm=/^\/v1\/stories\/([a-f0-9-]{36})(\/view|\/viewers)?$/.exec(path);
 if(sm&&validUuid(sm[1])){const item=await one(sm[1],viewer);
  if(method==='GET'&&!sm[2]){respond(response,200,{story:item});return true;}
  if(method==='PUT'&&sm[2]==='/view'){if(!item.isMine)await database.query('INSERT INTO tomi_story_views(story_id,user_id,viewed_at) VALUES(?,?,?) ON CONFLICT(story_id,user_id) DO NOTHING',[item.id,viewer,stamp()]);respond(response,200,{ok:true});return true;}
  if(method==='GET'&&sm[2]==='/viewers'){if(!item.isMine)throw new ApiError(403,'FORBIDDEN','المشاهدات لصاحب الستوري فقط.');const cursor=url.searchParams.get('cursor');if(cursor&&!validUuid(cursor))throw new ApiError(400,'VALIDATION','الصفحة غير صحيحة.');const n=size(url),rows=(await database.query('SELECT user_id FROM tomi_story_views WHERE story_id=? AND user_id>? ORDER BY user_id LIMIT ?',[item.id,cursor??'',n+1])).rows;const users=[];for(const r of rows.slice(0,n))try{users.push(await userById(r.user_id,viewer));}catch{}respond(response,200,{users,nextCursor:rows.length>n?rows[n-1].user_id:null});return true;}
  if(method==='DELETE'&&!sm[2]){if(!item.isMine)throw new ApiError(403,'FORBIDDEN','تگدر تحذف ستورياتك فقط.');await database.transaction(async db=>remove(db,(await db.query('SELECT * FROM tomi_stories WHERE id=?',[item.id])).rows[0]));respond(response,200,{ok:true});return true;}
 }
 const fm=/^\/v1\/users\/([a-f0-9-]{36})\/(followers|following)$/.exec(path);
 if(method==='GET'&&fm&&validUuid(fm[1])){
  await userById(fm[1],viewer);const n=size(url),cursor=url.searchParams.get('cursor');if(cursor&&!validUuid(cursor))throw new ApiError(400,'VALIDATION','الصفحة غير صحيحة.');
  if((await database.query('SELECT 1 FROM tomi_user_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)',[viewer,fm[1],fm[1],viewer])).rows.length)throw new ApiError(403,'BLOCKED','هذا الحساب غير متاح.');
  const peer=fm[2]==='followers'?'f.follower_id':'f.following_id',owner=fm[2]==='followers'?'f.following_id':'f.follower_id';
  const rows=(await database.query(`SELECT ${peer} user_id FROM tomi_follows f WHERE ${owner}=? AND ${peer}>?
   AND NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts d WHERE d.user_id=${peer}) AND NOT EXISTS(SELECT 1 FROM tomi_account_restrictions r WHERE r.user_id=${peer} AND r.suspended=1)
   AND NOT EXISTS(SELECT 1 FROM tomi_user_blocks b WHERE (b.blocker_id=? AND b.blocked_id=${peer}) OR (b.blocker_id=${peer} AND b.blocked_id=?)) ORDER BY ${peer} LIMIT ?`,[fm[1],cursor??'',viewer,viewer,n+1])).rows;
  const users=[];for(const r of rows.slice(0,n))users.push(await userById(r.user_id,viewer));respond(response,200,{users,nextCursor:rows.length>n?rows[n-1].user_id:null});return true;
 }
 const singleActivity=/^\/v1\/activity\/([a-f0-9-]{36})$/.exec(path);
 if(method==='GET'&&singleActivity){const r=(await database.query('SELECT n.* FROM tomi_activity n WHERE n.id=? AND n.recipient_id=? AND '+activityVisible,[singleActivity[1],viewer])).rows[0];if(!r)throw new ApiError(404,'ACTIVITY_NOT_FOUND','الإشعار لم يعد متاحاً.');respond(response,200,{item:{id:r.id,kind:r.kind,targetId:r.target_id,createdAt:r.created_at,read:r.read_at!==null,actor:await userById(r.actor_id,viewer)}});return true;}
 if(method==='GET'&&path==='/v1/activity'){
  const n=size(url),cursor=url.searchParams.get('cursor');if(cursor&&!validUuid(cursor))throw new ApiError(400,'VALIDATION','الصفحة غير صحيحة.');let condition='';const values=[viewer];
  if(cursor){const r=(await database.query('SELECT created_at,id FROM tomi_activity WHERE id=? AND recipient_id=?',[cursor,viewer])).rows[0];if(!r)throw new ApiError(400,'VALIDATION','حدّث الإشعارات.');condition=' AND (n.created_at<? OR (n.created_at=? AND n.id<?))';values.push(r.created_at,r.created_at,r.id);}values.push(n+1);
  const rows=(await database.query('SELECT n.* FROM tomi_activity n WHERE n.recipient_id=? AND '+activityVisible+condition+' ORDER BY n.created_at DESC,n.id DESC LIMIT ?',values)).rows;
  const items=[];for(const r of rows.slice(0,n))items.push({id:r.id,kind:r.kind,targetId:r.target_id,createdAt:r.created_at,read:r.read_at!==null,actor:await userById(r.actor_id,viewer)});
  const unread=(await database.query('SELECT COUNT(*) n FROM tomi_activity n WHERE n.recipient_id=? AND n.read_at IS NULL AND '+activityVisible,[viewer])).rows[0];respond(response,200,{items,unreadCount:Number(unread.n),nextCursor:rows.length>n?rows[n-1].id:null});return true;
 }
 if(method==='PUT'&&path==='/v1/activity/read'){const d=await readJson(request);fields(d,['ids']);if(!Array.isArray(d.ids)||d.ids.length>50||d.ids.some(x=>!validUuid(x)))throw new ApiError(400,'VALIDATION','قائمة الإشعارات غير صحيحة.');await database.transaction(async db=>{for(const id of d.ids)await db.query('UPDATE tomi_activity SET read_at=COALESCE(read_at,?) WHERE id=? AND recipient_id=?',[stamp(),id,viewer]);});respond(response,200,{ok:true});return true;}
 if(method==='GET'&&path==='/v1/subscriptions/catalog'){respond(response,200,{services:[{id:'vip',name:'VIP'},{id:'monthly',name:'الباقة الشهرية'},{id:'tumble',name:'تومبل'},{id:'username',name:'يوزر مميز'}].map(x=>({...x,available:false,price:null,description:'التفاصيل والأسعار تُعلن عند إطلاق الخدمة.'})),purchasesEnabled:false});return true;}
 if(method==='GET'&&path==='/v1/subscriptions/usernames'){const username=validateUsername(url.searchParams.get('username'));const taken=(await database.query('SELECT id FROM tomi_users WHERE username=?',[username])).rows.length>0;respond(response,200,{username,available:!taken,purchasable:false,message:taken?'هذا اليوزر مستخدم.':'اليوزر غير مستخدم حاليًا؛ الشراء والحجز يتاحان عند إطلاق الخدمة.'});return true;}
 return false;
 }
 let cleaning=false;
 async function cleanup(){if(cleaning)return;cleaning=true;try{const rows=(await database.query('SELECT * FROM tomi_stories WHERE expires_at<=? ORDER BY expires_at LIMIT 100',[stamp()])).rows;for(const r of rows)await database.transaction(async db=>{const live=(await db.query('SELECT * FROM tomi_stories WHERE id=? AND expires_at<=?',[r.id,stamp()])).rows[0];if(live)await remove(db,live);});await database.query('DELETE FROM tomi_story_receipts WHERE created_at<?',[stamp(-30*86400000)]);await database.query('DELETE FROM tomi_activity WHERE created_at<?',[stamp(-90*86400000)]);}finally{cleaning=false;}}
 return {handle,cleanup};
}
