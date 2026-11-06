import {randomUUID} from 'node:crypto';
import {ApiError} from './security.mjs';
const stamp=(ms=0)=>new Date(Date.now()+ms).toISOString();
export const noticeVisible="NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts d WHERE d.user_id=n.recipient_id OR d.user_id=n.actor_id) AND NOT EXISTS(SELECT 1 FROM tomi_account_restrictions r WHERE (r.user_id=n.actor_id OR r.user_id=n.recipient_id) AND r.suspended=1) AND NOT EXISTS(SELECT 1 FROM tomi_user_blocks b WHERE (b.blocker_id=n.recipient_id AND b.blocked_id=n.actor_id) OR (b.blocker_id=n.actor_id AND b.blocked_id=n.recipient_id))";
/** @param {any} db @param {{recipientId:string,actorId?:string|null,kind:string,targetId:string,sourceKey:string}} value */
export async function recordNotice(db,{recipientId,actorId=null,kind,targetId,sourceKey}){
 if(!['support','mention_post','mention_story','schedule','tournament'].includes(kind))throw Error('NOTICE_KIND');
 if((await db.query('SELECT 1 FROM tomi_deleted_accounts WHERE user_id=?',[recipientId])).rows.length)return;
 await db.query('INSERT INTO tomi_notices(id,recipient_id,actor_id,kind,target_id,source_key,created_at,next_at) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(recipient_id,source_key) DO NOTHING',[randomUUID(),recipientId,actorId,kind,targetId,sourceKey,stamp(),stamp()]);
}
export function createNotices({database,readJson,respond,limit}){
 const view=r=>({id:r.id,kind:r.kind,targetId:r.target_id,createdAt:r.created_at,read:r.read_at!==null});
 return {async handle(req,res,url,c){
  if(url.pathname==='/v1/me/notices'&&req.method==='GET'){
   const cursor=url.searchParams.get('cursor');let after='',args=[c.id];if(cursor){if(!/^[a-f0-9-]{36}$/.test(cursor))throw new ApiError(400,'VALIDATION','صفحة غير صحيحة.');const row=(await database.query('SELECT id,created_at FROM tomi_notices WHERE id=? AND recipient_id=?',[cursor,c.id])).rows[0];if(!row)throw new ApiError(400,'VALIDATION','حدّث التنبيهات.');after=' AND (n.created_at<? OR (n.created_at=? AND n.id<?))';args.push(row.created_at,row.created_at,row.id);}
   const rows=(await database.query('SELECT n.* FROM tomi_notices n WHERE n.recipient_id=? AND '+noticeVisible+after+' ORDER BY n.created_at DESC,n.id DESC LIMIT 51',args)).rows;respond(res,200,{items:rows.slice(0,50).map(view),nextCursor:rows.length>50?rows[49].id:null});return true;
  }
  const match=/^\/v1\/me\/notices\/([a-f0-9-]{36})$/.exec(url.pathname);if(!match||!['GET','PUT'].includes(req.method))return false;
  await limit('notice-read:'+c.id,120);const row=(await database.query('SELECT n.* FROM tomi_notices n WHERE n.id=? AND n.recipient_id=? AND '+noticeVisible,[match[1],c.id])).rows[0];if(!row)throw new ApiError(404,'NOTICE_NOT_FOUND','التنبيه غير متاح.');if(req.method==='PUT'){const d=await readJson(req);if(!d||Object.keys(d).length)throw new ApiError(400,'VALIDATION','طلب غير صحيح.');await database.query('UPDATE tomi_notices SET read_at=COALESCE(read_at,?) WHERE id=? AND recipient_id=?',[stamp(),row.id,c.id]);row.read_at=stamp();}respond(res,200,{notice:view(row)});return true;
 }};
}
export function createNoticePush({database,sender}){
 let running=false,closed=false;
 async function flush(){if(closed||running||!sender)return;running=true;try{const rows=(await database.query("SELECT id FROM tomi_notices WHERE push_state='pending' AND next_at<=? AND lease_until<? ORDER BY created_at LIMIT 10",[stamp(),stamp()])).rows;
  for(const row of rows){if(closed)break;const job=(await database.query("UPDATE tomi_notices SET lease_until=? WHERE id=? AND push_state='pending' AND lease_until<? RETURNING *",[stamp(120000),row.id,stamp()])).rows[0];if(!job)continue;
   const eligible=async()=>(await database.query('SELECT n.id FROM tomi_notices n LEFT JOIN tomi_push_settings p ON p.user_id=n.recipient_id WHERE n.id=? AND n.read_at IS NULL AND COALESCE(p.enabled,1)=1 AND '+noticeVisible,[job.id])).rows.length>0;
   try{if(!await eligible()){await database.query("UPDATE tomi_notices SET push_state='obsolete',lease_until='' WHERE id=?",[job.id]);continue;}
    const devices=(await database.query('SELECT d.token_hash,d.token FROM tomi_push_devices d JOIN tomi_sessions s ON s.token_hash=d.session_hash AND s.user_id=d.user_id JOIN tomi_users u ON u.id=s.user_id AND u.auth_version=s.auth_version WHERE d.user_id=? AND s.expires_at>? AND NOT EXISTS(SELECT 1 FROM tomi_notice_receipts r WHERE r.notice_id=? AND r.token_hash=d.token_hash)',[job.recipient_id,stamp(),job.id])).rows;
    for(const device of devices){if(closed||!await eligible())break;const valid=(await database.query('SELECT 1 FROM tomi_push_devices d JOIN tomi_sessions s ON s.token_hash=d.session_hash WHERE d.token_hash=? AND d.token=? AND d.user_id=? AND s.expires_at>?',[device.token_hash,device.token,job.recipient_id,stamp()])).rows.length;if(!valid)continue;const result=await sender({token:device.token,recipientId:job.recipient_id,noticeId:job.id,notificationKind:job.kind});if(result==='invalid')await database.query('DELETE FROM tomi_push_devices WHERE token_hash=? AND token=? AND user_id=?',[device.token_hash,device.token,job.recipient_id]);else await database.query('INSERT INTO tomi_notice_receipts(notice_id,token_hash) VALUES(?,?) ON CONFLICT(notice_id,token_hash) DO NOTHING',[job.id,device.token_hash]);}
    await database.query("UPDATE tomi_notices SET push_state=?,lease_until='' WHERE id=?",[closed?'pending':'sent',job.id]);
   }catch{const attempt=Number(job.attempts)+1;await database.query("UPDATE tomi_notices SET push_state=?,attempts=?,next_at=?,lease_until='' WHERE id=?",[attempt>=6?'failed':'pending',attempt,stamp(Math.min(300000,2**attempt*1000)),job.id]);}
  }
 }finally{running=false;}}
 return {flush,close(){closed=true;},async cleanup(){await database.query('DELETE FROM tomi_notices WHERE created_at<?',[stamp(-30*86400000)]);}};
}
