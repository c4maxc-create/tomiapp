import {randomUUID} from 'node:crypto';
import {ApiError,digest} from './security.mjs';
const uuid=v=>typeof v==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(v);
const now=()=>new Date().toISOString(),fail=(s,c,m)=>{throw new ApiError(s,c,m);};
const visible="p.id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tomi_content_moderation x WHERE x.target_type='post' AND x.target_id=p.id AND x.hidden=1) AND NOT EXISTS(SELECT 1 FROM tomi_account_restrictions x WHERE x.user_id=p.user_id AND x.suspended=1)";
const pending="r.recipient_id=? AND r.state='pending' AND NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts a WHERE a.user_id=r.sender_id) AND NOT EXISTS(SELECT 1 FROM tomi_account_restrictions a WHERE a.user_id=r.sender_id AND a.suspended=1) AND NOT EXISTS(SELECT 1 FROM tomi_user_blocks b WHERE (b.blocker_id=r.sender_id AND b.blocked_id=r.recipient_id) OR (b.blocker_id=r.recipient_id AND b.blocked_id=r.sender_id))";
function fields(d,keys){if(Object.keys(d).some(k=>!keys.includes(k)))fail(400,'VALIDATION','حقل مشاركة غير مسموح.');}
export function createPostShares({database,readJson,respond,limit,usersByIds,userById,accountGate,chat,social}){
 async function pendingCount(uid,db=database){return Number((await db.query('SELECT COUNT(*) n FROM tomi_post_share_requests r WHERE '+pending,[uid])).rows[0].n);}
 async function allowedPair(db,a,b){if((await db.query('SELECT 1 FROM tomi_user_blocks WHERE (blocker_id=? AND blocked_id=?) OR(blocker_id=? AND blocked_id=?)',[a,b,b,a])).rows.length)fail(403,'CHAT_BLOCKED','المشاركة غير متاحة مع هذا الحساب.');
  if((await db.query('SELECT 1 FROM tomi_deleted_accounts WHERE user_id IN(?,?)',[a,b])).rows.length)fail(410,'ACCOUNT_DELETED','هذا الحساب محذوف.');if((await db.query('SELECT 1 FROM tomi_account_restrictions WHERE user_id IN(?,?) AND suspended=1',[a,b])).rows.length)fail(403,'ACCOUNT_SUSPENDED','هذا الحساب موقوف.');}
 async function lockUsers(db,ids){for(const id of [...new Set(ids)].sort())await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=?',[id]);}
 async function lockPost(db,id,viewer){await db.query('UPDATE tomi_posts SET body=body WHERE id=?',[id]);return social.getPost(id,viewer,db);}
 async function share(c,pid,d){fields(d,['requestId','userId']);if(!uuid(d.requestId)||!uuid(d.userId)||d.userId===c.id)fail(400,'VALIDATION','اختَر شخصًا آخر ومعرّف طلب صحيحًا.');await userById(d.userId,c.id);const fp=digest(JSON.stringify([pid,d.userId]));
  return database.transaction(async db=>{await accountGate(db,d.userId);await lockUsers(db,[c.id,d.userId]);await allowedPair(db,c.id,d.userId);
   // Sorted pair/thread locks are acquired by deliverShared before message writes.
   const old=(await db.query('SELECT * FROM tomi_post_share_receipts WHERE sender_id=? AND request_id=?',[c.id,d.requestId])).rows[0];
   if(old){if(old.fingerprint!==fp)fail(409,'REQUEST_CHANGED','تغيّر المنشور أو الشخص في طلب معلّق.');return {...JSON.parse(old.result),replayed:true};}
   if((await db.query('SELECT 1 FROM tomi_chat_messages WHERE sender_id=? AND request_id=?',[c.id,d.requestId])).rows.length)fail(409,'REQUEST_CHANGED','هذا المعرّف مستخدم لرسالة أخرى.');
   const friend=(await db.query('SELECT 1 FROM tomi_follows WHERE (follower_id=? AND following_id=?) OR(follower_id=? AND following_id=?)',[c.id,d.userId,d.userId,c.id])).rows.length||(await db.query('SELECT 1 FROM tomi_post_share_pairs WHERE sender_id=? AND recipient_id=?',[c.id,d.userId])).rows.length;
   if(friend)await chat.prepareShared(db,c.id,d.userId);
   await lockPost(db,pid,c.id);
   let result;
   if(friend){const m=await chat.deliverShared(db,c.id,d.userId,pid,d.requestId);result={status:'delivered',conversationId:m.threadId,messageId:m.messageId};}
   else {const count=Number((await db.query("SELECT COUNT(*) n FROM tomi_post_share_requests WHERE sender_id=? AND recipient_id=? AND state='pending'",[c.id,d.userId])).rows[0].n);if(count>=10)fail(429,'SHARE_PENDING','لديك عشرة طلبات معلّقة لهذا الشخص؛ انتظر قبوله.');const id=randomUUID(),stamp=now();await db.query("INSERT INTO tomi_post_share_requests(id,sender_id,recipient_id,post_id,client_nonce,state,created_at,updated_at) VALUES(?,?,?,?,?,'pending',?,?)",[id,c.id,d.userId,pid,d.requestId,stamp,stamp]);result={status:'pending',requestId:id};}
   await db.query('INSERT INTO tomi_post_share_receipts(sender_id,request_id,target_id,post_id,fingerprint,result,created_at) VALUES(?,?,?,?,?,?,?)',[c.id,d.requestId,d.userId,pid,fp,JSON.stringify(result),now()]);return result;
  });
 }
 async function action(c,rid,d){fields(d,['requestId','action']);if(!uuid(d.requestId)||!['accept','block'].includes(d.action))fail(400,'VALIDATION','اختَر قبول الطلب أو الحظر.');const fp=digest(JSON.stringify([rid,d.action]));
  return database.transaction(async db=>{
   const old=(await db.query('SELECT * FROM tomi_post_share_actions WHERE actor_id=? AND request_id=?',[c.id,d.requestId])).rows[0];if(old){if(old.fingerprint!==fp)fail(409,'REQUEST_CHANGED','تغيّر الإجراء؛ استخدم طلبًا جديدًا.');return {...JSON.parse(old.result),replayed:true};}
   const initial=(await db.query('SELECT * FROM tomi_post_share_requests WHERE id=? AND recipient_id=?',[rid,c.id])).rows[0];if(!initial)fail(404,'NOT_FOUND','طلب المشاركة غير موجود.');
   // Erasure gates precede request and thread locks, including when deletion is queued.
   await accountGate(db,initial.sender_id);await lockUsers(db,[c.id,initial.sender_id]);
   const again=(await db.query('SELECT * FROM tomi_post_share_actions WHERE actor_id=? AND request_id=?',[c.id,d.requestId])).rows[0];if(again){if(again.fingerprint!==fp)fail(409,'REQUEST_CHANGED','تغيّر الإجراء.');return {...JSON.parse(again.result),replayed:true};}
   await db.query('UPDATE tomi_post_share_requests SET updated_at=updated_at WHERE id=?',[rid]);const r=(await db.query('SELECT * FROM tomi_post_share_requests WHERE id=? AND recipient_id=?',[rid,c.id])).rows[0];if(!r)fail(404,'NOT_FOUND','حُذف طلب المشاركة.');let result;
   if(d.action==='block'){
    await chat.blockShared(db,c.id,r.sender_id);
    await db.query("UPDATE tomi_post_share_requests SET state='blocked',updated_at=? WHERE (sender_id=? AND recipient_id=?) OR(sender_id=? AND recipient_id=?)",[now(),r.sender_id,c.id,c.id,r.sender_id]);
    await db.query('DELETE FROM tomi_post_share_pairs WHERE (sender_id=? AND recipient_id=?) OR(sender_id=? AND recipient_id=?)',[c.id,r.sender_id,r.sender_id,c.id]);result={status:'blocked',senderId:r.sender_id};
   } else {
    if(r.state==='blocked')fail(403,'CHAT_BLOCKED','هذا الطلب محظور.');await allowedPair(db,r.sender_id,c.id);
    if((await db.query('SELECT 1 FROM tomi_deleted_accounts WHERE user_id=?',[r.sender_id])).rows.length)fail(410,'ACCOUNT_DELETED','حُذف المرسل.');
    const prepared=await chat.prepareShared(db,r.sender_id,c.id);
    const requests=(await db.query("SELECT * FROM tomi_post_share_requests WHERE sender_id=? AND recipient_id=? AND state='pending' ORDER BY post_id,id",[r.sender_id,c.id])).rows;
    let threadId=r.state==='accepted'?prepared:null;const messages=[];
    for(const item of requests){if(!item.post_id)continue;try{await lockPost(db,item.post_id,c.id);}catch(e){if(e.code==='POST_NOT_FOUND')continue;throw e;}
     const m=await chat.deliverShared(db,r.sender_id,c.id,item.post_id,item.client_nonce);threadId=m.threadId;messages.push(m.messageId);await db.query('UPDATE tomi_post_share_receipts SET result=? WHERE sender_id=? AND request_id=?',[JSON.stringify({status:'delivered',conversationId:m.threadId,messageId:m.messageId}),r.sender_id,item.client_nonce]);
    }
    if(!threadId)fail(410,'POST_NOT_FOUND','المنشورات في هذا الطلب لم تعد متاحة.');
    await db.query('INSERT INTO tomi_post_share_pairs(sender_id,recipient_id,created_at) VALUES(?,?,?) ON CONFLICT(sender_id,recipient_id) DO NOTHING',[r.sender_id,c.id,now()]);
    await db.query("UPDATE tomi_post_share_requests SET state='accepted',updated_at=? WHERE sender_id=? AND recipient_id=? AND state='pending'",[now(),r.sender_id,c.id]);result={status:'accepted',conversationId:threadId,messageIds:messages,senderId:r.sender_id};
   }
   await db.query('INSERT INTO tomi_post_share_actions(actor_id,request_id,fingerprint,result,created_at) VALUES(?,?,?,?,?)',[c.id,d.requestId,fp,JSON.stringify(result),now()]);return result;
  });
 }
 async function handle(req,res,url,c){const path=url.pathname,send=path.match(/^\/v1\/posts\/([a-f0-9-]{36})\/share$/),act=path.match(/^\/v1\/post-shares\/requests\/([a-f0-9-]{36})$/);
  if(send&&req.method==='POST'){await limit('post-share:'+c.id,60);const d=await readJson(req),r=await share(c,send[1],d);chat.emit([c.id,d.userId],{type:r.status==='delivered'?'chat.message':'post_share.request',...(r.conversationId?{conversationId:r.conversationId}:{})});respond(res,200,r);return true;}
  if(act&&req.method==='POST'){await limit('post-share-actions:'+c.id,60);const r=await action(c,act[1],await readJson(req));chat.emit([c.id,...(r.senderId?[r.senderId]:[])],{type:r.status==='blocked'?'chat.blocked':'chat.message',...(r.conversationId?{conversationId:r.conversationId}:{})});respond(res,200,r);return true;}
  if(path==='/v1/post-shares/requests'&&req.method==='GET'){
   let cursor=null;const raw=url.searchParams.get('cursor');if(raw)try{if(raw.length>200)throw Error();cursor=JSON.parse(Buffer.from(raw,'base64url').toString());if(!uuid(cursor.id)||typeof cursor.time!=='string'||!Number.isFinite(Date.parse(cursor.time)))throw Error();}catch{fail(400,'VALIDATION','الصفحة غير صحيحة.');}
   const values=[c.id],condition=cursor?' AND (r.created_at<? OR(r.created_at=? AND r.id<?))':'';if(cursor)values.push(cursor.time,cursor.time,cursor.id);
   const rows=(await database.query('SELECT r.*,CASE WHEN '+visible+' THEN p.body ELSE NULL END preview FROM tomi_post_share_requests r LEFT JOIN tomi_posts p ON p.id=r.post_id WHERE '+pending+condition+' ORDER BY r.created_at DESC,r.id DESC LIMIT 31',values)).rows;
   const users=await usersByIds(rows.slice(0,30).map(r=>r.sender_id),c.id),last=rows[29];respond(res,200,{count:await pendingCount(c.id),items:rows.slice(0,30).filter(r=>users.has(r.sender_id)).map(r=>({id:r.id,sender:users.get(r.sender_id),postId:r.preview===null?null:r.post_id,text:r.preview??'المنشور غير متاح',createdAt:r.created_at})),nextCursor:rows.length>30?Buffer.from(JSON.stringify({time:last.created_at,id:last.id})).toString('base64url'):null});return true;
  }
  if(path==='/v1/post-shares/contacts'&&req.method==='GET'){
   const cursor=url.searchParams.get('cursor')??'';if(cursor&&!uuid(cursor))fail(400,'VALIDATION','الصفحة غير صحيحة.');
   const rows=(await database.query('SELECT u.id FROM tomi_users u WHERE u.id>? AND u.id<>? AND EXISTS(SELECT 1 FROM tomi_follows f WHERE (f.follower_id=? AND f.following_id=u.id) OR(f.following_id=? AND f.follower_id=u.id)) AND NOT EXISTS(SELECT 1 FROM tomi_user_blocks b WHERE (b.blocker_id=? AND b.blocked_id=u.id) OR(b.blocker_id=u.id AND b.blocked_id=?)) AND NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts a WHERE a.user_id=u.id) AND NOT EXISTS(SELECT 1 FROM tomi_account_restrictions a WHERE a.user_id=u.id AND a.suspended=1) ORDER BY u.id LIMIT 31',[cursor,c.id,c.id,c.id,c.id,c.id])).rows;
   const users=await usersByIds(rows.slice(0,30).map(r=>r.id),c.id);respond(res,200,{users:rows.slice(0,30).filter(r=>users.has(r.id)).map(r=>users.get(r.id)),nextCursor:rows.length>30?rows[29].id:null});return true;
  }
  return false;
 }
 return {handle,pendingCount};
}
