import {randomUUID} from 'node:crypto';
import {ApiError,isUniqueConflict} from './security.mjs';
import {imageTypes,maxImageBytes} from './images.mjs';
import {avatarFields,avatarJoins,avatarColumns} from './avatars.mjs';
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const now=()=>new Date().toISOString();
const posts='SELECT p.*,u.username,u.display_name,u.avatar_preset'+avatarColumns+',m.object_key,m.width,m.height,'+
 '(SELECT COUNT(*) FROM tomi_post_likes l WHERE l.post_id=p.id) AS likes_count,'+
 '(SELECT COUNT(*) FROM tomi_comments c WHERE c.post_id=p.id) AS comments_count,'+
 '(SELECT COUNT(*) FROM tomi_post_likes l WHERE l.post_id=p.id AND l.user_id=?) AS is_liked '+
 'FROM tomi_posts p JOIN tomi_users u ON u.id=p.user_id LEFT JOIN tomi_image_uploads m ON m.id=p.image_upload_id '+avatarJoins;
const comments='SELECT c.*,u.username,u.display_name,u.avatar_preset'+avatarColumns+' FROM tomi_comments c JOIN tomi_users u ON u.id=c.user_id '+avatarJoins;
function fields(data,allowed){if(Object.keys(data).some(k=>!allowed.includes(k)))throw new ApiError(400,'VALIDATION','هذا التعديل غير مسموح.');}
function reqId(v){if(typeof v!=='string'||!uuid.test(v))throw new ApiError(400,'VALIDATION','معرّف الطلب غير صحيح.');return v;}
function textBody(v,max){if(v!==undefined&&typeof v!=='string')throw new ApiError(400,'VALIDATION','النص غير صحيح.');const s=(v||'').trim();if([...s].length>max)throw new ApiError(400,'VALIDATION','النص أطول من المسموح.');return s;}
function page(url){const v=url.searchParams.get('limit')||'20';if(!/^\d{1,2}$/.test(v)||Number(v)<1||Number(v)>30)throw new ApiError(400,'VALIDATION','حجم الصفحة غير صحيح.');let cursor;const raw=url.searchParams.get('cursor');
 if(raw)try{if(raw.length>200)throw new Error();cursor=JSON.parse(Buffer.from(raw,'base64url').toString());if(!uuid.test(cursor.id)||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(cursor.time)||!Number.isFinite(Date.parse(cursor.time)))throw new Error();}catch{throw new ApiError(400,'VALIDATION','الصفحة غير صحيحة؛ حدّث القائمة.');}return{size:Number(v),cursor};}
const cursorFor=r=>Buffer.from(JSON.stringify({time:r.created_at,id:r.id})).toString('base64url');
const author=(r,storage)=>({id:r.user_id,username:r.username,displayName:r.display_name,avatarPreset:r.avatar_preset,...avatarFields(r,storage)});
export function createSocial({database,storage,readJson,respond,limit,userById,cleanupPrefix='tomi/'}){
 const postJson=(r,viewer)=>({id:r.id,text:r.body,createdAt:r.created_at,author:author(r,storage),image:r.object_key?{url:storage?.readUrl(r.object_key)??null,width:Number(r.width),height:Number(r.height)}:null,likesCount:Number(r.likes_count),commentsCount:Number(r.comments_count),liked:Number(r.is_liked)>0,isMine:r.user_id===viewer});
 const commentJson=(r,viewer)=>({id:r.id,text:r.body,createdAt:r.created_at,author:author(r,storage),isMine:r.user_id===viewer});
 async function getPost(id,viewer,db=database){const{rows}=await db.query(posts+'WHERE p.id=?',[viewer,id]);if(!rows[0])throw new ApiError(404,'POST_NOT_FOUND','المنشور غير موجود أو انحذف.');return postJson(rows[0],viewer);}
 async function existing(viewer,key,text,image){const{rows}=await database.query('SELECT * FROM tomi_posts WHERE user_id=? AND request_id=?',[viewer,key]);if(!rows[0])return null;if(rows[0].body!==text||(rows[0].image_upload_id||null)!==image)throw new ApiError(409,'REQUEST_CHANGED','محتوى الطلب تغيّر؛ استخدم طلب جديد.');return rows[0].id;}
 async function handle(request,response,url,current){const path=url.pathname,method=request.method,viewer=current.id;
  if(method==='GET'&&path==='/v1/media/status'){respond(response,200,{imageUploadEnabled:!!storage,maxImageBytes,contentTypes:Object.keys(imageTypes)});return true;}
  if(method==='POST'&&path==='/v1/media/images'){
   if(!storage)throw new ApiError(503,'IMAGES_DISABLED','نشر الصور غير متاح حاليًا؛ تگدر تنشر نص.');await limit('images:'+viewer,10);await limit('daily-images:'+viewer,100,86400000);
   const d=await readJson(request);fields(d,['contentType','byteLength','contentMd5']);
   if(!Object.hasOwn(imageTypes,d.contentType)||!Number.isInteger(d.byteLength)||d.byteLength<13||d.byteLength>maxImageBytes||typeof d.contentMd5!=='string'||!/^[A-Za-z0-9+/]{22}==$/.test(d.contentMd5))throw new ApiError(400,'INVALID_IMAGE','اختَر JPG أو PNG أو WebP أو GIF، بحجم لا يتجاوز 10 MB.');
   const pending=await database.query("SELECT COUNT(*) AS total FROM tomi_image_uploads WHERE user_id=? AND state='pending' AND expires_at>?",[viewer,now()]);if(Number(pending.rows[0].total)>=10)throw new ApiError(429,'RATE_LIMITED','عندك صور كثيرة قيد الرفع؛ جرّب لاحقًا.');
   const id=randomUUID(),created=now(),u={id,user_id:viewer,object_key:'tomi/posts/'+viewer+'/'+id+'.'+imageTypes[d.contentType],content_type:d.contentType,byte_length:d.byteLength,content_md5:d.contentMd5};
   await database.query('INSERT INTO tomi_image_uploads (id,user_id,object_key,content_type,byte_length,content_md5,created_at,expires_at) VALUES (?,?,?,?,?,?,?,?)',[id,viewer,u.object_key,u.content_type,u.byte_length,u.content_md5,created,new Date(Date.now()+86400000).toISOString()]);
   respond(response,201,{uploadId:id,...storage.prepare(u)});return true;
  }
  if(method==='GET'&&path==='/v1/posts'){
   const scope=url.searchParams.get('scope')||'all',userId=url.searchParams.get('userId');if(!['all','following','mine'].includes(scope)||(userId&&!uuid.test(userId)))throw new ApiError(400,'VALIDATION','قائمة المنشورات غير صحيحة.');
   const{size,cursor}=page(url),values=[viewer],conditions=[];
   if(userId||scope==='mine'){conditions.push('p.user_id=?');values.push(userId||viewer);}else if(scope==='following'){conditions.push('(p.user_id=? OR EXISTS(SELECT 1 FROM tomi_follows f WHERE f.follower_id=? AND f.following_id=p.user_id))');values.push(viewer,viewer);}
   if(cursor){conditions.push('(p.created_at<? OR (p.created_at=? AND p.id<?))');values.push(cursor.time,cursor.time,cursor.id);}values.push(size+1);
   const{rows}=await database.query(posts+(conditions.length?'WHERE '+conditions.join(' AND '):'')+' ORDER BY p.created_at DESC,p.id DESC LIMIT ?',values),items=rows.slice(0,size);
   respond(response,200,{posts:items.map(r=>postJson(r,viewer)),nextCursor:rows.length>size?cursorFor(items.at(-1)):null,imageUploadEnabled:!!storage});return true;
  }
  if(method==='POST'&&path==='/v1/posts'){
   await limit('posts:'+viewer,20);const d=await readJson(request);fields(d,['text','imageUploadId','requestId']);const text=textBody(d.text,2000),key=reqId(d.requestId),image=d.imageUploadId??null;
   if(image!==null&&(typeof image!=='string'||!uuid.test(image)))throw new ApiError(400,'INVALID_IMAGE','الصورة غير صحيحة.');if(!text&&!image)throw new ApiError(400,'VALIDATION','اكتب نص أو اختَر صورة.');
   let id=await existing(viewer,key,text,image),dimensions;const repeated=!!id;
   if(!id&&image){if(!storage)throw new ApiError(503,'IMAGES_DISABLED','نشر الصور غير متاح حاليًا؛ تگدر تنشر نص.');const{rows}=await database.query('SELECT * FROM tomi_image_uploads WHERE id=? AND user_id=?',[image,viewer]);const u=rows[0];if(!u||u.state!=='pending'||u.expires_at<=now()||!u.object_key.startsWith('tomi/posts/'+viewer+'/'))throw new ApiError(400,'UPLOAD_INVALID','رفع الصورة انتهى أو استُخدم؛ اختَرها مرة ثانية.');dimensions=await storage.verify(u);}
   if(!id){id=randomUUID();try{await database.transaction(async db=>{
    await db.query('INSERT INTO tomi_posts (id,user_id,request_id,body,image_upload_id,created_at) VALUES (?,?,?,?,?,?)',[id,viewer,key,text,image,now()]);
    if(image){const changed=await db.query("UPDATE tomi_image_uploads SET state='attached',width=?,height=? WHERE id=? AND user_id=? AND state='pending' AND expires_at>?",[dimensions.width,dimensions.height,image,viewer,now()]);if(changed.changes!==1)throw new ApiError(409,'UPLOAD_INVALID','الصورة انتهت أو استُخدمت؛ اختَرها مرة ثانية.');}
   });}catch(e){if(!isUniqueConflict(e))throw e;id=await existing(viewer,key,text,image);if(!id)throw new ApiError(409,'UPLOAD_INVALID','الصورة استُخدمت بمنشور سابق؛ اختَرها مرة ثانية.');}}
   respond(response,repeated?200:201,{post:await getPost(id,viewer),user:await userById(viewer,viewer)});return true;
  }
  const match=path.match(/^\/v1\/posts\/([a-f0-9-]{36})(\/like|\/comments)?$/);
  if(match&&uuid.test(match[1])){const id=match[1],action=match[2]||'';
   if(method==='GET'&&!action){respond(response,200,{post:await getPost(id,viewer)});return true;}
   if(method==='DELETE'&&!action){await database.transaction(async db=>{const{rows}=await db.query('SELECT user_id,image_upload_id FROM tomi_posts WHERE id=?',[id]);if(!rows[0])throw new ApiError(404,'POST_NOT_FOUND','المنشور غير موجود.');if(rows[0].user_id!==viewer)throw new ApiError(403,'FORBIDDEN','تگدر تحذف منشوراتك فقط.');await db.query('DELETE FROM tomi_posts WHERE id=? AND user_id=?',[id,viewer]);if(rows[0].image_upload_id)await db.query("UPDATE tomi_image_uploads SET state='deleting',expires_at=? WHERE id=?",[new Date(Date.now()+1200000).toISOString(),rows[0].image_upload_id]);});respond(response,200,{user:await userById(viewer,viewer)});return true;}
   if(method==='PUT'&&action==='/like'){await limit('likes:'+viewer,60);const d=await readJson(request);fields(d,['liked']);if(typeof d.liked!=='boolean')throw new ApiError(400,'VALIDATION','حدّد حالة الإعجاب.');await database.transaction(async db=>{await getPost(id,viewer,db);if(d.liked)await db.query('INSERT INTO tomi_post_likes (post_id,user_id,created_at) VALUES (?,?,?) ON CONFLICT(post_id,user_id) DO NOTHING',[id,viewer,now()]);else await db.query('DELETE FROM tomi_post_likes WHERE post_id=? AND user_id=?',[id,viewer]);});respond(response,200,{post:await getPost(id,viewer)});return true;}
   if(method==='GET'&&action==='/comments'){await getPost(id,viewer);const{size,cursor}=page(url),conditions=['c.post_id=?'],values=[id];if(cursor){conditions.push('(c.created_at<? OR (c.created_at=? AND c.id<?))');values.push(cursor.time,cursor.time,cursor.id);}values.push(size+1);const{rows}=await database.query(comments+'WHERE '+conditions.join(' AND ')+' ORDER BY c.created_at DESC,c.id DESC LIMIT ?',values),items=rows.slice(0,size);respond(response,200,{comments:items.map(r=>commentJson(r,viewer)),nextCursor:rows.length>size?cursorFor(items.at(-1)):null});return true;}
   if(method==='POST'&&action==='/comments'){await limit('comments:'+viewer,30);const d=await readJson(request);fields(d,['text','requestId']);const text=textBody(d.text,500),key=reqId(d.requestId);if(!text)throw new ApiError(400,'VALIDATION','اكتب تعليقك.');await getPost(id,viewer);await database.query('INSERT INTO tomi_comments (id,post_id,user_id,request_id,body,created_at) VALUES (?,?,?,?,?,?) ON CONFLICT(user_id,request_id) DO NOTHING',[randomUUID(),id,viewer,key,text,now()]);const{rows}=await database.query(comments+'WHERE c.user_id=? AND c.request_id=?',[viewer,key]);if(rows[0].body!==text||rows[0].post_id!==id)throw new ApiError(409,'REQUEST_CHANGED','محتوى التعليق تغيّر؛ استخدم طلب جديد.');respond(response,201,{comment:commentJson(rows[0],viewer),post:await getPost(id,viewer)});return true;}
  }
  const cm=path.match(/^\/v1\/comments\/([a-f0-9-]{36})$/);
  if(method==='DELETE'&&cm&&uuid.test(cm[1])){let postId;await database.transaction(async db=>{const{rows}=await db.query('SELECT c.post_id,c.user_id,p.user_id AS post_owner FROM tomi_comments c JOIN tomi_posts p ON p.id=c.post_id WHERE c.id=?',[cm[1]]);if(!rows[0])throw new ApiError(404,'COMMENT_NOT_FOUND','التعليق غير موجود.');if(rows[0].user_id!==viewer&&rows[0].post_owner!==viewer)throw new ApiError(403,'FORBIDDEN','ما عندك صلاحية حذف هذا التعليق.');postId=rows[0].post_id;await db.query('DELETE FROM tomi_comments WHERE id=?',[cm[1]]);});respond(response,200,{post:await getPost(postId,viewer)});return true;}
  return false;
 }
 let cleaning=false;
 async function cleanup(){if(!storage||cleaning)return;cleaning=true;try{const{rows}=await database.query("SELECT id,object_key FROM tomi_image_uploads WHERE state<>'attached' AND expires_at<=? AND object_key LIKE ? ORDER BY expires_at LIMIT 20",[now(),cleanupPrefix+'%']);for(const r of rows)try{await storage.delete(r.object_key);await database.query("DELETE FROM tomi_image_uploads WHERE id=? AND state<>'attached' AND expires_at<=?",[r.id,now()]);}catch{console.error('Media cleanup deferred');}}finally{cleaning=false;}}
 return {handle,cleanup};
}
