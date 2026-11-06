import {createNoticePush} from './notices.mjs';
import {activityVisible} from './home.mjs';
import {createPrivateKey,sign} from 'node:crypto';
import {ApiError,digest} from './security.mjs';
const stamp=(offset=0)=>new Date(Date.now()+offset).toISOString();
export function fcmFromEnvironment(env=process.env,{fetcher=fetch}={}){
 const accountJson=env.FCM_SERVICE_ACCOUNT_JSON?.trim()||env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
 if(!accountJson)return null;let key;
 try{const a=JSON.parse(accountJson);if(a.type!=='service_account'||!/^[a-z][a-z0-9-]{4,61}[a-z0-9]$/.test(a.project_id)||!/^.+@.+\.iam\.gserviceaccount\.com$/.test(a.client_email))throw Error();key={project:a.project_id,email:a.client_email,privateKey:createPrivateKey(a.private_key)};if(key.privateKey.asymmetricKeyType!=='rsa')throw Error();}catch{throw Error('FCM_CONFIG_INVALID');}
 let cached,expires=0,refresh;
 async function accessToken(){if(cached&&Date.now()<expires)return cached;if(refresh)return refresh;
  refresh=(async()=>{const time=Math.floor(Date.now()/1000),encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url'),unsigned=encode({alg:'RS256',typ:'JWT'})+'.'+encode({iss:key.email,scope:'https://www.googleapis.com/auth/firebase.messaging',aud:'https://oauth2.googleapis.com/token',iat:time,exp:time+3600}),jwt=unsigned+'.'+sign('RSA-SHA256',Buffer.from(unsigned),key.privateKey).toString('base64url');const r=await fetcher('https://oauth2.googleapis.com/token',{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:jwt}),signal:AbortSignal.timeout(10000),redirect:'error'});if(!r.ok)throw Error('FCM_AUTH');const data=await r.json();if(typeof data.access_token!=='string'||!Number.isFinite(data.expires_in))throw Error('FCM_AUTH');cached=data.access_token;expires=Date.now()+Math.max(0,data.expires_in-60)*1000;return cached;})();try{return await refresh;}finally{refresh=null;}
 }
 return async({token,threadId,recipientId,callId,callProtocol=1,bindingId,expiresAt,kind='audio',cancel=false,activityId,noticeId,notificationKind})=>{
  const message={token,notification:{title:'TOMI',body:'وصلتك رسالة جديدة في TOMI'},data:{type:'chat',conversationId:threadId,accountId:recipientId},android:{priority:'HIGH',ttl:'300s',collapse_key:'tomi-private-chat',notification:{tag:'chat-'+threadId,channel_id:'tomi_updates',sound:'default'}},apns:{headers:{'apns-expiration':String(Math.floor(Date.now()/1000)+300),'apns-collapse-id':threadId},payload:{aps:{sound:'default'}}}};
  if(activityId){message.notification.body=({follow:'عندك متابع جديد في TOMI',like:'إعجاب جديد بمنشورك في TOMI',comment:'تعليق جديد على منشورك في TOMI'})[notificationKind]||'عندك إشعار جديد في TOMI';message.data={type:'activity',activityId,accountId:recipientId};message.android.collapse_key='tomi-activity';message.android.notification.tag='activity-'+activityId;message.apns.headers['apns-collapse-id']=activityId;}
  if(noticeId){message.notification.body=notificationKind==='support'?'وصلك رد من دعم TOMI':'عندك تنبيه جديد في TOMI';message.data={type:'notice',noticeId,accountId:recipientId};message.android.collapse_key='tomi-notice';message.android.notification.tag='notice-'+noticeId;message.apns.headers['apns-collapse-id']=noticeId;}
  if(callId){message.notification.body='مكالمة واردة في TOMI';message.data={type:'call',callId,conversationId:threadId,accountId:recipientId};message.android.ttl='30s';message.android.collapse_key='tomi-incoming-call';message.android.notification.tag='call-'+callId;message.android.notification.sound='default';message.apns.headers['apns-expiration']=String(Math.floor(Date.now()/1000)+30);message.apns.headers['apns-collapse-id']=callId;}
  if(callId && callProtocol===2) {
    // Android native CallStyle receives data-only pushes. Legacy clients keep
    // their existing generic notification until they advertise protocol 2.
    delete message.notification;
    message.data={type:cancel?'call_cancel':'call',callId,conversationId:threadId,accountId:recipientId,bindingId,kind,expiresAt:String(expiresAt)};
    message.android={priority:'HIGH',ttl:cancel?'60s':Math.max(0,Math.min(35,Math.ceil((expiresAt-Date.now())/1000)))+'s'};
  }
  const r=await fetcher(`https://fcm.googleapis.com/v1/projects/${key.project}/messages:send`,{method:'POST',headers:{authorization:'Bearer '+await accessToken(),'content-type':'application/json'},body:JSON.stringify({message}),signal:AbortSignal.timeout(10000),redirect:'error'});
  if(r.ok){await r.body?.cancel();return 'sent';}if(r.status===401){cached=null;expires=0;}const data=await r.json().catch(()=>({}));if(data.error?.details?.some(x=>x.errorCode==='UNREGISTERED'))return 'invalid';throw Error('FCM_SEND');
 };
}
export function createPush({database,sender,readJson,respond,limit,autoFlush=true}){
 const noticePush=createNoticePush({database,sender});
 const configured=typeof sender==='function';let running=false,closed=false;
 async function settings(viewer){const{rows}=await database.query('SELECT enabled FROM tomi_push_settings WHERE user_id=?',[viewer]);return{configured,enabled:rows[0]?Number(rows[0].enabled)===1:true};}
 async function enqueue(db,{messageId,recipientId,threadId}){if(configured)await db.query('INSERT INTO tomi_push_outbox(message_id,recipient_id,thread_id,next_at,created_at) VALUES(?,?,?,?,?) ON CONFLICT(message_id) DO NOTHING',[messageId,recipientId,threadId,stamp(),stamp()]);}
 async function handle(request,response,url,current){const path=url.pathname,viewer=current.id;
  if(path==='/v1/push/settings'&&request.method==='GET'){respond(response,200,await settings(viewer));return true;}
  if(path==='/v1/push/settings'&&request.method==='PUT'){await limit('push-settings:'+viewer,20);const d=await readJson(request);if(Object.keys(d).length!==1||typeof d.enabled!=='boolean')throw new ApiError(400,'VALIDATION','حدّد حالة الإشعارات.');await database.query('INSERT INTO tomi_push_settings(user_id,enabled) VALUES(?,?) ON CONFLICT(user_id) DO UPDATE SET enabled=excluded.enabled',[viewer,d.enabled?1:0]);respond(response,200,await settings(viewer));return true;}
  if(path!=='/v1/push/device'||!['PUT','DELETE'].includes(request.method))return false;await limit('push-device:'+viewer,20);const d=await readJson(request);if(typeof d.token!=='string'||d.token.length<20||d.token.length>4096||!/^[A-Za-z0-9_:.-]+$/.test(d.token)||Object.keys(d).some(k=>!['token','platform','callProtocol'].includes(k)))throw new ApiError(400,'VALIDATION','رمز الجهاز غير صحيح.');const hash=digest(d.token);
  if(request.method==='DELETE'){await database.query('DELETE FROM tomi_push_devices WHERE token_hash=? AND user_id=? AND session_hash=?',[hash,viewer,current.tokenHash]);respond(response,200,{ok:true});return true;}
  if(d.callProtocol!==undefined&&(d.callProtocol!==2||d.platform!=='android'))throw new ApiError(400,'VALIDATION','بروتوكول المكالمة غير صحيح.');
  if(!['android','ios'].includes(d.platform))throw new ApiError(400,'VALIDATION','نوع الجهاز غير صحيح.');if(!configured){respond(response,200,{configured:false});return true;}
  await database.transaction(async db=>{await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING id',[viewer]);await db.query('DELETE FROM tomi_push_devices WHERE user_id=? AND session_hash=? AND token_hash<>?',[viewer,current.tokenHash,hash]);await db.query('INSERT INTO tomi_push_devices(token_hash,token,user_id,session_hash,platform,updated_at) VALUES(?,?,?,?,?,?) ON CONFLICT(token_hash) DO UPDATE SET token=excluded.token,user_id=excluded.user_id,session_hash=excluded.session_hash,platform=excluded.platform,updated_at=excluded.updated_at',[hash,d.token,viewer,current.tokenHash,d.platform,stamp()]);if(d.callProtocol===2)await db.query('INSERT INTO tomi_call_push_protocol(token_hash,protocol) VALUES(?,2) ON CONFLICT(token_hash) DO UPDATE SET protocol=2',[hash]);else await db.query('DELETE FROM tomi_call_push_protocol WHERE token_hash=?',[hash]);const{rows}=await db.query('SELECT token_hash FROM tomi_push_devices WHERE user_id=? ORDER BY updated_at DESC,token_hash',[viewer]);for(const old of rows.slice(5))await db.query('DELETE FROM tomi_push_devices WHERE token_hash=? AND user_id=?',[old.token_hash,viewer]);});respond(response,200,{configured:true,...d.callProtocol===2?{bindingId:digest('tomi-call-push:'+current.tokenHash)}:{}});return true;
 }
 async function eligible(job){const{rows}=await database.query(`SELECT m.id FROM tomi_chat_messages m JOIN tomi_chat_members cm ON cm.thread_id=m.thread_id AND cm.user_id=? LEFT JOIN tomi_push_settings ps ON ps.user_id=cm.user_id WHERE m.id=? AND m.deleted_at IS NULL AND m.sequence>cm.last_read_seq AND COALESCE(ps.enabled,1)=1 AND NOT EXISTS(SELECT 1 FROM tomi_muted_chats muted WHERE muted.user_id=cm.user_id AND muted.thread_id=m.thread_id) AND NOT EXISTS(SELECT 1 FROM tomi_user_blocks b WHERE (b.blocker_id=m.sender_id AND b.blocked_id=cm.user_id) OR (b.blocker_id=cm.user_id AND b.blocked_id=m.sender_id))`,[job.recipient_id,job.message_id]);return rows.length>0;}
 async function devices(job){return(await database.query(`SELECT d.token_hash,d.token FROM tomi_push_devices d JOIN tomi_sessions s ON s.token_hash=d.session_hash JOIN tomi_users u ON u.id=s.user_id AND u.auth_version=s.auth_version WHERE d.user_id=? AND s.user_id=d.user_id AND s.expires_at>? AND NOT EXISTS(SELECT 1 FROM tomi_push_receipts r WHERE r.message_id=? AND r.token_hash=d.token_hash)`,[job.recipient_id,stamp(),job.message_id])).rows;}
 async function flushMessages(){if(running||closed||!configured)return;running=true;try{
  const{rows}=await database.query("SELECT message_id FROM tomi_push_outbox WHERE state='pending' AND next_at<=? AND lease_until<? ORDER BY created_at LIMIT 10",[stamp(),stamp()]);
  for(const r of rows){if(closed)break;const job=(await database.query("UPDATE tomi_push_outbox SET lease_until=? WHERE message_id=? AND state='pending' AND lease_until<? RETURNING *",[stamp(120000),r.message_id,stamp()])).rows[0];if(!job)continue;
   try{if(!(await eligible(job))){await database.query("UPDATE tomi_push_outbox SET state='obsolete',lease_until='' WHERE message_id=?",[job.message_id]);continue;}
    for(const device of await devices(job)){if(closed||!(await eligible(job)))break;const valid=await database.query('SELECT d.token_hash FROM tomi_push_devices d JOIN tomi_sessions s ON s.token_hash=d.session_hash WHERE d.token_hash=? AND d.token=? AND d.user_id=? AND s.expires_at>?',[device.token_hash,device.token,job.recipient_id,stamp()]);if(!valid.rows.length)continue;const result=await sender({token:device.token,threadId:job.thread_id,recipientId:job.recipient_id});if(result==='invalid')await database.query('DELETE FROM tomi_push_devices WHERE token_hash=? AND token=? AND user_id=?',[device.token_hash,device.token,job.recipient_id]);else await database.query('INSERT INTO tomi_push_receipts(message_id,token_hash) VALUES(?,?) ON CONFLICT(message_id,token_hash) DO NOTHING',[job.message_id,device.token_hash]);}
    await database.query("UPDATE tomi_push_outbox SET state=?,lease_until='' WHERE message_id=?",[closed?'pending':'sent',job.message_id]);
   }catch{const attempts=Number(job.attempts)+1;await database.query('UPDATE tomi_push_outbox SET state=?,attempts=?,next_at=?,lease_until=? WHERE message_id=?',[attempts>=6?'failed':'pending',attempts,stamp(Math.min(300000,2**attempts*1000)),'',job.message_id]);}
  }
 }finally{running=false;}}

 let callRunning=false;
 async function enqueueCall(db,{callId,recipientId,threadId}){if(configured)await db.query('INSERT INTO tomi_call_push_outbox(call_id,recipient_id,thread_id,next_at,created_at) VALUES(?,?,?,?,?) ON CONFLICT(call_id) DO NOTHING',[callId,recipientId,threadId,stamp(),stamp()]);}
 async function callEligible(job){return (await database.query(`SELECT c.id FROM tomi_calls c JOIN tomi_sessions s ON s.token_hash=c.caller_session JOIN tomi_users u ON u.id=s.user_id AND u.auth_version=s.auth_version LEFT JOIN tomi_push_settings ps ON ps.user_id=c.callee_id WHERE c.id=? AND c.state='ringing' AND c.ring_deadline>? AND s.expires_at>? AND COALESCE(ps.enabled,1)=1 AND NOT EXISTS(SELECT 1 FROM tomi_user_blocks b WHERE (b.blocker_id=c.caller_id AND b.blocked_id=c.callee_id) OR (b.blocker_id=c.callee_id AND b.blocked_id=c.caller_id))`,[job.call_id,stamp(),stamp()])).rows.length>0;}
 async function flushCalls(){if(callRunning||closed||!configured)return;callRunning=true;try{
  const rows=(await database.query("SELECT call_id FROM tomi_call_push_outbox WHERE state='pending' AND next_at<=? AND lease_until<? ORDER BY created_at LIMIT 10",[stamp(),stamp()])).rows;
  for(const r of rows){if(closed)break;const job=(await database.query("UPDATE tomi_call_push_outbox SET lease_until=? WHERE call_id=? AND state='pending' AND lease_until<? RETURNING *",[stamp(120000),r.call_id,stamp()])).rows[0];if(!job)continue;
   try{if(!(await callEligible(job))){await database.query("UPDATE tomi_call_push_outbox SET state='obsolete',lease_until='' WHERE call_id=?",[job.call_id]);continue;}
    const devices=(await database.query(`SELECT d.token_hash,d.token,d.session_hash,cp.protocol FROM tomi_push_devices d JOIN tomi_sessions s ON s.token_hash=d.session_hash JOIN tomi_users u ON u.id=s.user_id AND u.auth_version=s.auth_version LEFT JOIN tomi_call_push_protocol cp ON cp.token_hash=d.token_hash WHERE d.user_id=? AND s.expires_at>? AND NOT EXISTS(SELECT 1 FROM tomi_call_push_receipts r WHERE r.call_id=? AND r.token_hash=d.token_hash)`,[job.recipient_id,stamp(),job.call_id])).rows;
    for(const device of devices){if(closed||!(await callEligible(job)))break;const valid=(await database.query('SELECT 1 FROM tomi_push_devices WHERE token_hash=? AND token=? AND user_id=?',[device.token_hash,device.token,job.recipient_id])).rows.length;if(!valid)continue;const live=(await database.query("SELECT ring_deadline,kind FROM tomi_calls WHERE id=? AND state='ringing'",[job.call_id])).rows[0];if(!live)break;const result=await sender({token:device.token,threadId:job.thread_id,recipientId:job.recipient_id,callId:job.call_id,callProtocol:Number(device.protocol??1),bindingId:digest('tomi-call-push:'+device.session_hash),expiresAt:Date.parse(live.ring_deadline),kind:live.kind});if(result==='invalid')await database.query('DELETE FROM tomi_push_devices WHERE token_hash=? AND token=? AND user_id=?',[device.token_hash,device.token,job.recipient_id]);else await database.query('INSERT INTO tomi_call_push_receipts(call_id,token_hash) VALUES(?,?) ON CONFLICT(call_id,token_hash) DO NOTHING',[job.call_id,device.token_hash]);}
    await database.query("UPDATE tomi_call_push_outbox SET state=?,lease_until='' WHERE call_id=?",[closed?'pending':'sent',job.call_id]);
   }catch{const attempts=Number(job.attempts)+1;await database.query('UPDATE tomi_call_push_outbox SET state=?,attempts=?,next_at=?,lease_until=? WHERE call_id=?',[attempts>=3?'failed':'pending',attempts,stamp(2**attempts*1000),'',job.call_id]);}
  }
 }finally{callRunning=false;}}
 let cancelRunning=false;
 async function flushCancelledCalls(){
  if(cancelRunning||closed||!configured)return;cancelRunning=true;
  try{
   await database.query(`INSERT INTO tomi_call_push_cancel(call_id,recipient_id,thread_id,next_at,created_at)
    SELECT o.call_id,o.recipient_id,o.thread_id,?,? FROM tomi_call_push_outbox o JOIN tomi_calls c ON c.id=o.call_id
    WHERE (c.state<>'ringing' OR c.ring_deadline<=?) AND NOT EXISTS(SELECT 1 FROM tomi_call_push_cancel x WHERE x.call_id=o.call_id)
    ON CONFLICT(call_id) DO NOTHING`,[stamp(),stamp(),stamp()]);
   const rows=(await database.query("SELECT call_id FROM tomi_call_push_cancel WHERE state='pending' AND next_at<=? AND lease_until<? ORDER BY created_at LIMIT 10",[stamp(),stamp()])).rows;
   for(const r of rows){
    if(closed)break;
    const job=(await database.query("UPDATE tomi_call_push_cancel SET lease_until=? WHERE call_id=? AND state='pending' AND lease_until<? RETURNING *",[stamp(120000),r.call_id,stamp()])).rows[0];if(!job)continue;
    try{
     const devices=(await database.query(`SELECT d.token_hash,d.token,d.session_hash FROM tomi_push_devices d
      JOIN tomi_call_push_protocol cp ON cp.token_hash=d.token_hash AND cp.protocol=2
      JOIN tomi_sessions s ON s.token_hash=d.session_hash AND s.user_id=d.user_id
      JOIN tomi_users u ON u.id=s.user_id AND u.auth_version=s.auth_version
      WHERE d.user_id=? AND s.expires_at>? AND NOT EXISTS(SELECT 1 FROM tomi_call_push_cancel_receipts x WHERE x.call_id=? AND x.token_hash=d.token_hash)`,[job.recipient_id,stamp(),job.call_id])).rows;
     for(const d of devices){
      if(closed)break;
      const valid=(await database.query('SELECT 1 FROM tomi_push_devices WHERE token_hash=? AND token=? AND user_id=? AND session_hash=?',[d.token_hash,d.token,job.recipient_id,d.session_hash])).rows.length;if(!valid)continue;
      const result=await sender({token:d.token,threadId:job.thread_id,recipientId:job.recipient_id,callId:job.call_id,callProtocol:2,bindingId:digest('tomi-call-push:'+d.session_hash),expiresAt:Date.now()+60000,cancel:true});
      if(result==='invalid')await database.query('DELETE FROM tomi_push_devices WHERE token_hash=? AND token=? AND user_id=?',[d.token_hash,d.token,job.recipient_id]);
      else await database.query('INSERT INTO tomi_call_push_cancel_receipts(call_id,token_hash) VALUES(?,?) ON CONFLICT(call_id,token_hash) DO NOTHING',[job.call_id,d.token_hash]);
     }
     await database.query("UPDATE tomi_call_push_cancel SET state=?,lease_until='' WHERE call_id=?",[closed?'pending':'sent',job.call_id]);
    }catch{const attempts=Number(job.attempts)+1;await database.query('UPDATE tomi_call_push_cancel SET state=?,attempts=?,next_at=?,lease_until=? WHERE call_id=?',[attempts>=4?'failed':'pending',attempts,stamp(2**attempts*1000),'',job.call_id]);}
   }
  }finally{cancelRunning=false;}
 }
 let activityRunning=false;
 async function flushActivity(){if(activityRunning||closed||!configured)return;activityRunning=true;try{
  const rows=(await database.query("SELECT id FROM tomi_activity WHERE push_state='pending' AND next_at<=? AND lease_until<? ORDER BY created_at LIMIT 10",[stamp(),stamp()])).rows;
  for(const row of rows){if(closed)break;const job=(await database.query("UPDATE tomi_activity SET lease_until=? WHERE id=? AND push_state='pending' AND lease_until<? RETURNING *",[stamp(120000),row.id,stamp()])).rows[0];if(!job)continue;
   const eligible=async()=>(await database.query(`SELECT n.id FROM tomi_activity n LEFT JOIN tomi_push_settings ps ON ps.user_id=n.recipient_id WHERE n.id=? AND n.read_at IS NULL AND COALESCE(ps.enabled,1)=1 AND ${activityVisible}`,[job.id])).rows.length>0;
   try{if(!await eligible()){await database.query("UPDATE tomi_activity SET push_state='obsolete',lease_until='' WHERE id=?",[job.id]);continue;}
    const devices=(await database.query(`SELECT d.token_hash,d.token FROM tomi_push_devices d JOIN tomi_sessions s ON s.token_hash=d.session_hash AND s.user_id=d.user_id JOIN tomi_users u ON u.id=s.user_id AND u.auth_version=s.auth_version WHERE d.user_id=? AND s.expires_at>? AND NOT EXISTS(SELECT 1 FROM tomi_activity_push_receipts r WHERE r.activity_id=? AND r.token_hash=d.token_hash)`,[job.recipient_id,stamp(),job.id])).rows;
    for(const device of devices){if(closed||!await eligible())break;const live=(await database.query('SELECT 1 FROM tomi_push_devices d JOIN tomi_sessions s ON s.token_hash=d.session_hash AND s.user_id=d.user_id WHERE d.token_hash=? AND d.token=? AND d.user_id=? AND s.expires_at>?',[device.token_hash,device.token,job.recipient_id,stamp()])).rows.length;if(!live)continue;const result=await sender({token:device.token,recipientId:job.recipient_id,activityId:job.id,notificationKind:job.kind});if(result==='invalid')await database.query('DELETE FROM tomi_push_devices WHERE token_hash=? AND token=? AND user_id=?',[device.token_hash,device.token,job.recipient_id]);else await database.query('INSERT INTO tomi_activity_push_receipts(activity_id,token_hash) VALUES(?,?) ON CONFLICT(activity_id,token_hash) DO NOTHING',[job.id,device.token_hash]);}
    await database.query('UPDATE tomi_activity SET push_state=?,lease_until=? WHERE id=?',[closed?'pending':'sent','',job.id]);
   }catch{const attempts=Number(job.attempts)+1;await database.query('UPDATE tomi_activity SET push_state=?,attempts=?,next_at=?,lease_until=? WHERE id=?',[attempts>=6?'failed':'pending',attempts,stamp(Math.min(300000,2**attempts*1000)),'',job.id]);}
  }
 }finally{activityRunning=false;}}
 let groupRunning=false;
 async function enqueueGroup(db,{messageId,recipientId,groupId}){if(configured)await db.query('INSERT INTO tomi_group_push(message_id,recipient_id,group_id,next_at,created_at) VALUES(?,?,?,?,?) ON CONFLICT(message_id,recipient_id) DO NOTHING',[messageId,recipientId,groupId,stamp(),stamp()]);}
 async function flushGroups(){if(groupRunning||closed||!configured)return;groupRunning=true;try{
  const jobs=(await database.query("SELECT message_id,recipient_id FROM tomi_group_push WHERE state='pending' AND next_at<=? AND lease_until<? ORDER BY created_at LIMIT 15",[stamp(),stamp()])).rows;
  for(const key of jobs){if(closed)break;const job=(await database.query("UPDATE tomi_group_push SET lease_until=? WHERE message_id=? AND recipient_id=? AND state='pending' AND lease_until<? RETURNING *",[stamp(120000),key.message_id,key.recipient_id,stamp()])).rows[0];if(!job)continue;
   const eligible=async()=>(await database.query(`SELECT m.id FROM tomi_group_messages m JOIN tomi_group_members gm ON gm.group_id=m.group_id AND gm.user_id=? AND gm.left_at IS NULL LEFT JOIN tomi_push_settings ps ON ps.user_id=gm.user_id WHERE m.id=? AND m.deleted_at IS NULL AND m.sequence>gm.last_read_seq AND COALESCE(ps.enabled,1)=1 AND NOT EXISTS(SELECT 1 FROM tomi_user_blocks b WHERE (b.blocker_id=m.sender_id AND b.blocked_id=gm.user_id) OR (b.blocker_id=gm.user_id AND b.blocked_id=m.sender_id))`,[job.recipient_id,job.message_id])).rows.length>0;
   try{if(!await eligible()){await database.query("UPDATE tomi_group_push SET state='obsolete',lease_until='' WHERE message_id=? AND recipient_id=?",[job.message_id,job.recipient_id]);continue;}
    const devices=(await database.query(`SELECT d.token_hash,d.token FROM tomi_push_devices d JOIN tomi_sessions s ON s.token_hash=d.session_hash AND s.user_id=d.user_id JOIN tomi_users u ON u.id=s.user_id AND u.auth_version=s.auth_version WHERE d.user_id=? AND s.expires_at>? AND NOT EXISTS(SELECT 1 FROM tomi_group_push_receipts x WHERE x.message_id=? AND x.recipient_id=? AND x.token_hash=d.token_hash)`,[job.recipient_id,stamp(),job.message_id,job.recipient_id])).rows;
    for(const device of devices){if(closed||!await eligible())break;if(!(await database.query('SELECT 1 FROM tomi_push_devices d JOIN tomi_sessions s ON s.token_hash=d.session_hash AND s.user_id=d.user_id WHERE d.token_hash=? AND d.token=? AND d.user_id=? AND s.expires_at>?',[device.token_hash,device.token,job.recipient_id,stamp()])).rows.length)continue;const result=await sender({token:device.token,threadId:job.group_id,recipientId:job.recipient_id});if(result==='invalid')await database.query('DELETE FROM tomi_push_devices WHERE token_hash=? AND token=? AND user_id=?',[device.token_hash,device.token,job.recipient_id]);else await database.query('INSERT INTO tomi_group_push_receipts(message_id,recipient_id,token_hash) VALUES(?,?,?) ON CONFLICT(message_id,recipient_id,token_hash) DO NOTHING',[job.message_id,job.recipient_id,device.token_hash]);}
    await database.query("UPDATE tomi_group_push SET state=?,lease_until='' WHERE message_id=? AND recipient_id=?",[closed?'pending':'sent',job.message_id,job.recipient_id]);
   }catch{const n=Number(job.attempts)+1;await database.query('UPDATE tomi_group_push SET state=?,attempts=?,next_at=?,lease_until=? WHERE message_id=? AND recipient_id=?',[n>=6?'failed':'pending',n,stamp(Math.min(300000,2**n*1000)),'',job.message_id,job.recipient_id]);}
  }
 }finally{groupRunning=false;}}
 async function flush(){await Promise.all([flushCalls(),flushMessages(),flushActivity(),flushGroups(),noticePush.flush()]);await flushCancelledCalls();}
 const timer=configured&&autoFlush?setInterval(()=>void flush().catch(()=>console.error('Push worker deferred')),2000):null;timer?.unref();
 return{configured,handle,enqueue,enqueueCall,enqueueGroup,flush,close(){closed=true;noticePush.close();if(timer)clearInterval(timer);},async cleanup(){await noticePush.cleanup();await database.query("DELETE FROM tomi_group_push WHERE created_at<? AND state<>'pending'",[stamp(-7*86400000)]);await database.query("DELETE FROM tomi_call_push_cancel WHERE created_at<? AND state<>'pending'",[stamp(-7*86400000)]);await database.query("DELETE FROM tomi_call_push_outbox WHERE created_at<? AND state<>'pending'",[stamp(-7*86400000)]);await database.query("DELETE FROM tomi_push_outbox WHERE created_at<? AND state<>'pending'",[stamp(-7*86400000)]);await database.query('DELETE FROM tomi_avatar_requests WHERE created_at<?',[stamp(-30*86400000)]);}};
}
