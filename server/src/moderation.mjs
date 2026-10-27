import {staffPermissions,legacyPermissions,validatePermissions,effectivePermissions} from './platform_access.mjs';
import {ownerActions,prepareOwnerCommand,applyOwnerCommand,accountEconomy} from './owner_controls.mjs';
import {randomUUID} from 'node:crypto';
import {ApiError,digest,isUniqueConflict} from './security.mjs';

const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const now=()=>new Date().toISOString();
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const reasons=['spam','harassment','unsafe','impersonation','other'];
const statuses=['open','reviewing','resolved','dismissed'];
function id(value){if(typeof value!=='string'||!uuid.test(value))fail(400,'VALIDATION','المعرّف غير صحيح.');return value;}
function text(value,max,required=false){if(value!==undefined&&typeof value!=='string')fail(400,'VALIDATION','النص غير صحيح.');const s=(value??'').trim();if([...s].length>max||required&&[...s].length<4)fail(400,'VALIDATION','اكتب سببًا من 4 إلى '+max+' حرف.');return s;}
function fields(d,allowed){if(Object.keys(d).some(k=>!allowed.includes(k)))fail(400,'VALIDATION','هذا التعديل غير مسموح.');}
function page(url){
  const raw=url.searchParams.get('before');if(raw&&(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\|[a-f0-9-]{36}$/.test(raw)||!Number.isFinite(Date.parse(raw.split('|')[0]))||!uuid.test(raw.split('|')[1])))fail(400,'VALIDATION','صفحة السجل غير صحيحة.');
  return raw?raw.split('|'):null;
}
function windowSql(cursor,prefix=''){return cursor?{sql:` AND (${prefix}created_at<? OR (${prefix}created_at=? AND ${prefix}id<?))`,args:[cursor[0],cursor[0],cursor[1]]}:{sql:'',args:[]};}
function paged(rows,convert=x=>x){const items=rows.slice(0,20),last=items.at(-1);return {items:items.map(convert),nextBefore:rows.length>20?`${last.created_at}|${last.id}`:null};}
function ownReport(r){return {id:r.id,targetType:r.target_type,targetId:r.target_id,reason:r.reason,description:r.description,status:r.status,revision:Number(r.revision),publicMessage:r.public_message,createdAt:r.created_at,updatedAt:r.updated_at};}
function staffReport(r){return {...ownReport(r),reporterId:r.reporter_id,subjectUserId:r.subject_user_id,snapshot:JSON.parse(r.snapshot),note:r.review_note,reviewerId:r.reviewer_id};}

export function moderationOwner(env=process.env){
  const value=(env.TOMI_OWNER_USER_ID??'').trim().toLowerCase();
  if(value&&!uuid.test(value))throw Error('TOMI_OWNER_USER_ID must be an existing account UUID, not a username or token');
  return value||null;
}

export function createModeration({database,ownerUserId=null,storage,readJson,respond,limit,userById,usersByIds,rooms,calls,chat,operations,accountGate=async()=>{}}){
  if(ownerUserId&&!uuid.test(ownerUserId))throw Error('Invalid platform owner UUID');
  async function active(db,userId){
    if((await db.query('SELECT 1 FROM tomi_deleted_accounts WHERE user_id=?',[userId])).rows.length)fail(401,'ACCOUNT_DELETED','حُذف الحساب ولا يمكن استعادته.');
    const r=(await db.query('SELECT suspended FROM tomi_account_restrictions WHERE user_id=?',[userId])).rows[0];
    if(Number(r?.suspended??0))fail(403,'ACCOUNT_SUSPENDED','الحساب موقوف من إدارة تومي.');
  }
  async function role(db,userId){
    if(userId===ownerUserId)return 'owner';
    return (await db.query('SELECT role FROM tomi_platform_roles WHERE user_id=?',[userId])).rows[0]?.role??'member';
  }
  async function authorize(db,current,ownerOnly=false,permission=null){
    await active(db,current.id);const value=await role(db,current.id);
    if(value==='member'||ownerOnly&&value!=='owner')fail(403,'ADMIN_FORBIDDEN','هذا الإجراء لإدارة التطبيق المخوّلة.');
    if(permission&&value!=='owner'){const permissions=await effectivePermissions(db,current.id,value);if(!(Array.isArray(permission)?permission:[permission]).some(p=>permissions.includes(p)))fail(403,'ADMIN_PERMISSION','هذه الصلاحية غير ممنوحة لحسابك.');}
    return value;
  }
  async function lockUsers(db,current,others=[]){
    for(const uid of [...new Set([current.id,...others])].sort()){
      const q=await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING id',[uid]);
      if(!q.rows.length)fail(404,'NOT_FOUND','الحساب غير موجود.');
    }
    const live=(await db.query('SELECT 1 FROM tomi_sessions s JOIN tomi_users u ON u.id=s.user_id AND u.auth_version=s.auth_version WHERE s.user_id=? AND s.token_hash=? AND s.expires_at>?',[current.id,current.tokenHash,now()])).rows.length;
    if(!live)fail(401,'UNAUTHORIZED','انتهت الجلسة؛ سجّل دخولك مرة ثانية.');
    await active(db,current.id);
  }
  async function accountState(db,userId){
    const r=(await db.query(`SELECT u.id,COALESCE(a.suspended,0) suspended,COALESCE(a.revision,0) restriction_revision,
      COALESCE(p.revision,0) role_revision FROM tomi_users u LEFT JOIN tomi_account_restrictions a ON a.user_id=u.id
      LEFT JOIN tomi_platform_roles p ON p.user_id=u.id WHERE u.id=?`,[userId])).rows[0];
    if(!r)fail(404,'NOT_FOUND','الحساب غير موجود.');
    const value=await role(db,userId),profile=(await db.query('SELECT special,revision FROM tomi_admin_profiles WHERE user_id=?',[userId])).rows[0];
    return {suspended:!!Number(r.suspended),restrictionRevision:Number(r.restriction_revision),role:value,roleRevision:Number(r.role_revision),permissions:await effectivePermissions(db,userId,value),special:!!Number(profile?.special??0),adminRevision:Number(profile?.revision??0)};
  }
  async function contentState(db,type,targetId){
    const r=(await db.query('SELECT hidden,revision FROM tomi_content_moderation WHERE target_type=? AND target_id=?',[type,targetId])).rows[0];
    return {hidden:!!Number(r?.hidden??0),revision:Number(r?.revision??0)};
  }
  async function target(db,type,targetId,{preview=false}={}){
    let r;
    if(type==='account')r=(await db.query('SELECT id user_id,username,display_name,bio body FROM tomi_users WHERE id=?',[targetId])).rows[0];
    else if(type==='post')r=(await db.query(`SELECT p.user_id,p.body,u.username,u.display_name,i.object_key image_key,v.object_key video_key,v.width video_width,v.height video_height,v.duration_ms video_duration
      FROM tomi_posts p JOIN tomi_users u ON u.id=p.user_id LEFT JOIN tomi_image_uploads i ON i.id=p.image_upload_id
      LEFT JOIN tomi_post_video pv ON pv.post_id=p.id LEFT JOIN tomi_video_uploads v ON v.id=pv.upload_id WHERE p.id=?`,[targetId])).rows[0];
    else if(type==='room')r=(await db.query('SELECT r.owner_id user_id,r.title,r.state,u.username,u.display_name FROM tomi_voice_rooms r JOIN tomi_users u ON u.id=r.owner_id WHERE r.id=?',[targetId])).rows[0];
    else fail(400,'VALIDATION','نوع البلاغ غير صحيح.');
    if(!r)fail(404,'REPORT_TARGET_MISSING','المحتوى غير موجود أو انحذف.');
    const data={type,id:targetId,subjectUserId:r.user_id,user:{id:r.user_id,username:r.username,displayName:r.display_name},text:r.body??'',title:r.title??'',hasImage:!!r.image_key,hasVideo:!!r.video_key};
    if(preview){
      data.state=type==='account'?await accountState(db,targetId):{...await contentState(db,type,targetId),...(type==='room'?{roomState:r.state}:{})};
      if(r.image_key&&storage)data.imageUrl=storage.readUrl(r.image_key);
      if(r.video_key&&storage)data.video={url:storage.readUrl(r.video_key),width:Number(r.video_width),height:Number(r.video_height),durationMs:Number(r.video_duration)};
    }
    return data;
  }
  async function submit(current,d){
    fields(d,['requestId','targetType','targetId','reason','description']);id(d.requestId);id(d.targetId);
    if(!['account','post','room'].includes(d.targetType)||!reasons.includes(d.reason))fail(400,'VALIDATION','اختَر نوع البلاغ والسبب.');
    const description=text(d.description,1000),hash=digest(JSON.stringify([d.targetType,d.targetId,d.reason,description]));
    return database.transaction(async db=>{
      await lockUsers(db,current);
      const old=(await db.query('SELECT report_id,payload_hash FROM tomi_report_requests WHERE reporter_id=? AND request_id=?',[current.id,d.requestId])).rows[0];
      if(old){if(old.payload_hash!==hash)fail(409,'REQUEST_CHANGED','محتوى البلاغ تغيّر؛ استخدم طلبًا جديدًا.');return {report:ownReport((await db.query('SELECT * FROM tomi_reports WHERE id=?',[old.report_id])).rows[0]),replayed:true};}
      const subject=await target(db,d.targetType,d.targetId);
      await accountGate(db,subject.subjectUserId);
      // Re-read after the erasure gate: a concurrent delete may have scrubbed
      // the target while this request was waiting in PostgreSQL.
      const snapshot=await target(db,d.targetType,d.targetId);
      if((await db.query('SELECT 1 FROM tomi_deleted_accounts WHERE user_id=?',[snapshot.subjectUserId])).rows.length)fail(410,'ACCOUNT_DELETED','حُذف الحساب أو محتواه؛ لا يمكن إنشاء بلاغ جديد عليه.');
      if(snapshot.subjectUserId===current.id)fail(400,'REPORT_SELF','لا يمكن الإبلاغ عن حسابك أو محتواك.');
      let r=(await db.query("SELECT * FROM tomi_reports WHERE reporter_id=? AND target_type=? AND target_id=? AND status IN('open','reviewing')",[current.id,d.targetType,d.targetId])).rows[0];
      const duplicate=!!r,stamp=now();
      if(!r){const rid=randomUUID();await db.query('INSERT INTO tomi_reports(id,reporter_id,target_type,target_id,subject_user_id,reason,description,snapshot,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?)',[rid,current.id,d.targetType,d.targetId,snapshot.subjectUserId,d.reason,description,JSON.stringify(snapshot),stamp,stamp]);r=(await db.query('SELECT * FROM tomi_reports WHERE id=?',[rid])).rows[0];}
      await db.query('INSERT INTO tomi_report_requests(reporter_id,request_id,report_id,payload_hash,created_at) VALUES(?,?,?,?,?)',[current.id,d.requestId,r.id,hash,stamp]);
      return {report:ownReport(r),duplicate};
    });
  }

  const actionTypes={review_report:'report',hide_post:'post',restore_post:'post',close_room:'room',suspend_user:'account',restore_user:'account',grant_moderator:'account',revoke_moderator:'account',...Object.fromEntries(ownerActions.map(a=>[a,'account']))};
  async function command(current,d){
    if(!Object.hasOwn(actionTypes,d.action))fail(400,'VALIDATION','إجراء الإدارة غير معروف.');
    fields(d,['requestId','action','targetId','reason','expectedRevision','reportId',...(d.action==='review_report'?['status','note','publicMessage']:[]),...(d.action==='grant_moderator'?['permissions']:[]),...(ownerActions.includes(d.action)?['amount']:[]),...(d.action==='create_account'?['username','displayName','password','special']:[])]);
    id(d.requestId);id(d.targetId);if(d.reportId!==undefined)id(d.reportId);
    if(!Number.isSafeInteger(d.expectedRevision)||d.expectedRevision<0)fail(400,'VALIDATION','حدّث بيانات العنصر قبل الإجراء.');
    const reason=text(d.reason,500,d.action!=='review_report'),type=actionTypes[d.action];
    const isCreate=d.action==='create_account',ownerControl=ownerActions.includes(d.action);
    const hash=digest(JSON.stringify(Object.fromEntries(Object.keys(d).filter(k=>!isCreate||k!=='password').sort().map(k=>[k,d[k]]))));
    if(d.action==='grant_moderator'&&d.permissions!==undefined)validatePermissions(d.permissions);
    let prepared={};if(isCreate){await authorize(database,current,true);await limit('admin-create:'+current.id,10,3600000);prepared=await prepareOwnerCommand(d);}
    const ownerOnly=ownerControl||['grant_moderator','revoke_moderator'].includes(d.action);
    const permission=({review_report:'reports',hide_post:'posts',restore_post:'posts',close_room:'rooms',suspend_user:'bans',restore_user:'bans'})[d.action];
    let selected=null;
    if(type!=='report'&&!isCreate)try{selected=await target(database,type,d.targetId);}catch(e){if(e.status!==404)throw e;}
    const ended=[];
    const result=await database.transaction(async db=>{
      await lockUsers(db,current,selected?[selected.subjectUserId]:[]);
      const ownRole=await authorize(db,current,ownerOnly,permission);
      const replay=(await db.query('SELECT payload_hash,result FROM tomi_admin_requests WHERE actor_id=? AND request_id=?',[current.id,d.requestId])).rows[0];
      if(replay){if(replay.payload_hash!==hash)fail(409,'REQUEST_CHANGED','محتوى الإجراء تغيّر؛ استخدم طلبًا جديدًا.');return {...JSON.parse(replay.result),replayed:true};}
      if(type!=='report'&&!isCreate&&!selected)fail(404,'REPORT_TARGET_MISSING','المحتوى غير موجود أو انحذف.');
      if(selected){
        if((await db.query('SELECT 1 FROM tomi_deleted_accounts WHERE user_id=?',[selected.subjectUserId])).rows.length)fail(410,'ACCOUNT_DELETED','حُذفت بيانات الحساب؛ لا يمكن إعادته أو منحه صلاحية.');
        await target(db,type,d.targetId);
        const subjectRole=await role(db,selected.subjectUserId);
        if(selected.subjectUserId===ownerUserId&&ownRole!=='owner'||ownRole==='moderator'&&subjectRole!=='member')fail(403,'ADMIN_PROTECTED','هذا الحساب أو المحتوى محمي من إجراء المشرف.');
        if(type==='account'&&!ownerControl&&(d.targetId===current.id||d.targetId===ownerUserId))fail(403,'ADMIN_PROTECTED','لا يمكن تغيير صلاحيات المالك أو إيقاف حساب الإدارة الحالي.');
      }
      if(d.reportId){const linked=(await db.query('SELECT target_type,target_id FROM tomi_reports WHERE id=?',[d.reportId])).rows[0];if(!linked||linked.target_type!==type||linked.target_id!==d.targetId)fail(400,'REPORT_ACTION_MISMATCH','الإجراء لا يطابق هدف البلاغ.');}
      let revision,applied=true,before,after,ephemeral;
      if(ownerControl){({revision,applied,before,after,ephemeral}=await applyOwnerCommand(db,current,d,prepared));}
      else if(type==='report'){
        await db.query('UPDATE tomi_reports SET revision=revision WHERE id=? RETURNING id',[d.targetId]);
        const r=(await db.query('SELECT * FROM tomi_reports WHERE id=?',[d.targetId])).rows[0];if(!r)fail(404,'REPORT_NOT_FOUND','البلاغ غير موجود.');
        if(!statuses.includes(d.status))fail(400,'VALIDATION','حالة البلاغ غير صحيحة.');
        const note=text(d.note,1000),message=text(d.publicMessage,280);before={status:r.status,revision:Number(r.revision)};
        if(Number(r.revision)!==d.expectedRevision)fail(409,'ADMIN_CHANGED','تم تعديل العنصر من جهاز آخر؛ حدّث الصفحة.');
        if(['open','reviewing'].includes(d.status)&&(await db.query("SELECT 1 FROM tomi_reports WHERE reporter_id=? AND target_type=? AND target_id=? AND status IN('open','reviewing') AND id<>?",[r.reporter_id,r.target_type,r.target_id,r.id])).rows.length)fail(409,'REPORT_ALREADY_OPEN','يوجد بلاغ أحدث مفتوح للعنصر نفسه.');
        applied=r.status!==d.status||r.review_note!==note||r.public_message!==message;revision=Number(r.revision)+(applied?1:0);
        if(applied)await db.query('UPDATE tomi_reports SET status=?,review_note=?,public_message=?,reviewer_id=?,revision=?,updated_at=? WHERE id=?',[d.status,note,message,current.id,revision,now(),r.id]);
      }else if(['grant_moderator','revoke_moderator'].includes(d.action)){
        const state=await accountState(db,d.targetId);before=state;
        if(state.roleRevision!==d.expectedRevision)fail(409,'ADMIN_CHANGED','تغيّرت الصلاحية؛ حدّث الصفحة.');
        const next=d.action==='grant_moderator'?'moderator':'member';if(state.suspended&&next==='moderator')fail(409,'ADMIN_SUSPENDED','ألغِ إيقاف الحساب قبل منحه الصلاحية.');
        const permissions=next==='moderator'?(d.permissions===undefined?[...legacyPermissions]:validatePermissions(d.permissions)):[];
        applied=state.role!==next||JSON.stringify(state.permissions)!==JSON.stringify(permissions);revision=state.roleRevision+(applied?1:0);
        if(applied)await db.query('INSERT INTO tomi_platform_roles(user_id,role,revision,granted_by,updated_at) VALUES(?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET role=excluded.role,revision=excluded.revision,granted_by=excluded.granted_by,updated_at=excluded.updated_at',[d.targetId,next,revision,current.id,now()]);
        if(applied){if(next==='moderator')await db.query('INSERT INTO tomi_staff_permissions(user_id,permissions) VALUES(?,?) ON CONFLICT(user_id) DO UPDATE SET permissions=excluded.permissions',[d.targetId,JSON.stringify(permissions)]);else await db.query('DELETE FROM tomi_staff_permissions WHERE user_id=?',[d.targetId]);}
        after={role:next,permissions};
      }else if(type==='account'){
        const state=await accountState(db,d.targetId);before=state;
        if(state.restrictionRevision!==d.expectedRevision)fail(409,'ADMIN_CHANGED','تغيّرت حالة الحساب؛ حدّث الصفحة.');
        const suspended=d.action==='suspend_user';
        if(suspended&&state.role!=='member')fail(409,'ADMIN_STAFF','ألغِ صلاحية المشرف أولًا قبل إيقافه.');
        applied=state.suspended!==suspended;revision=state.restrictionRevision+(applied?1:0);
        if(applied){
          await db.query('INSERT INTO tomi_account_restrictions(user_id,suspended,revision,reason,updated_by,updated_at) VALUES(?,?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET suspended=excluded.suspended,revision=excluded.revision,reason=excluded.reason,updated_by=excluded.updated_by,updated_at=excluded.updated_at',[d.targetId,suspended?1:0,revision,reason,current.id,now()]);
          await db.query('UPDATE tomi_users SET auth_version=auth_version+1 WHERE id=?',[d.targetId]);
          await db.query('DELETE FROM tomi_sessions WHERE user_id=?',[d.targetId]);
          await db.query('DELETE FROM tomi_push_devices WHERE user_id=?',[d.targetId]);
          if(suspended){await rooms.suspendUser(db,d.targetId);ended.push(...await calls.suspendUser(db,d.targetId));}
        }
      }else{
        const state=await contentState(db,type,d.targetId);before=state;
        if(state.revision!==d.expectedRevision)fail(409,'ADMIN_CHANGED','تغيّرت حالة المحتوى؛ حدّث الصفحة.');
        const hidden=d.action!=='restore_post';applied=state.hidden!==hidden;
        if(type==='room')applied=await rooms.adminClose(db,d.targetId);
        revision=state.revision+(applied?1:0);
        if(applied)await db.query('INSERT INTO tomi_content_moderation(target_type,target_id,hidden,revision,reason,updated_by,updated_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(target_type,target_id) DO UPDATE SET hidden=excluded.hidden,revision=excluded.revision,reason=excluded.reason,updated_by=excluded.updated_by,updated_at=excluded.updated_at',[type,d.targetId,hidden?1:0,revision,reason,current.id,now()]);
      }
      const receiptId=randomUUID(),stamp=now();
      if(applied)await db.query('INSERT INTO tomi_admin_audit(id,actor_id,action,target_type,target_id,reason,report_id,details,created_at) VALUES(?,?,?,?,?,?,?,?,?)',[receiptId,current.id,d.action,type,d.targetId,reason||'تحديث حالة البلاغ',d.reportId??(type==='report'?d.targetId:null),JSON.stringify({before,after,revision}),stamp]);
      const reply={receiptId,action:d.action,targetType:type,targetId:d.targetId,revision,applied,createdAt:stamp};
      await db.query('INSERT INTO tomi_admin_requests(actor_id,request_id,payload_hash,result,created_at) VALUES(?,?,?,?,?)',[current.id,d.requestId,hash,JSON.stringify(reply),stamp]);
      return {...reply,...ephemeral};
    }).catch(e=>{if(d.action==='create_account'&&isUniqueConflict(e))fail(409,'USERNAME_TAKEN','اسم المستخدم مستخدم.');if(d.action==='review_report'&&isUniqueConflict(e))fail(409,'REPORT_ALREADY_OPEN','يوجد بلاغ أحدث مفتوح للعنصر نفسه.');throw e;});
    for(const r of ended)calls.notify(r);
    if(!result.replayed&&['close_room','suspend_user'].includes(d.action))void rooms.flush().catch(()=>{});
    if(!result.replayed&&['suspend_user','restore_user'].includes(d.action))chat.invalidateUser?.(d.targetId);
    return result;
  }

  async function handle(request,response,url,current){
    const path=url.pathname,method=request.method;
    if(path==='/v1/moderation/access'&&method==='GET'){respond(response,200,{role:await role(database,current.id),permissions:await effectivePermissions(database,current.id,await role(database,current.id)),availablePermissions:staffPermissions,ownerConfigured:!!ownerUserId,reasons,statuses});return true;}
    if(path==='/v1/reports'&&method==='POST'){await limit('report:'+current.id,5,600000);await limit('report-day:'+current.id,20,86400000);respond(response,201,await submit(current,await readJson(request)));return true;}
    if(path==='/v1/reports'&&method==='GET'){
      const w=windowSql(page(url)),rows=(await database.query('SELECT * FROM tomi_reports WHERE reporter_id=?'+w.sql+' ORDER BY created_at DESC,id DESC LIMIT 21',[current.id,...w.args])).rows;
      respond(response,200,paged(rows,ownReport));return true;
    }
    const mine=/^\/v1\/reports\/([a-f0-9-]{36})$/.exec(path);
    if(mine&&method==='GET'){id(mine[1]);const r=(await database.query('SELECT * FROM tomi_reports WHERE id=? AND reporter_id=?',[mine[1],current.id])).rows[0];if(!r)fail(404,'REPORT_NOT_FOUND','البلاغ غير موجود.');respond(response,200,{report:ownReport(r)});return true;}
    if(!path.startsWith('/v1/admin/'))return false;
    await authorize(database,current);await limit('admin:'+current.id,90);
    if(path==='/v1/admin/actions'&&method==='POST'){respond(response,200,await command(current,await readJson(request)));return true;}
    if(method!=='GET')return false;
    const readPermission=path.startsWith('/v1/admin/reports')?'reports':path==='/v1/admin/metrics'?'metrics':path==='/v1/admin/audit'?'audit':path==='/v1/admin/rooms'?'rooms':path==='/v1/admin/posts'?'posts':path==='/v1/admin/users'?['accounts','bans']:null;
    if(readPermission)await authorize(database,current,false,readPermission);
    if(path==='/v1/admin/metrics'){respond(response,200,await operations.snapshot(database));return true;}
    if(path==='/v1/admin/reports'){
      const status=url.searchParams.get('status')??'open';if(![...statuses,'all'].includes(status))fail(400,'VALIDATION','حالة البلاغ غير صحيحة.');
      const w=windowSql(page(url)),rows=(await database.query('SELECT * FROM tomi_reports WHERE '+(status==='all'?'1=1':'status=?')+w.sql+' ORDER BY created_at DESC,id DESC LIMIT 21',[...(status==='all'?[]:[status]),...w.args])).rows;
      respond(response,200,paged(rows,staffReport));return true;
    }
    const report=/^\/v1\/admin\/reports\/([a-f0-9-]{36})$/.exec(path);
    if(report){id(report[1]);const r=(await database.query('SELECT * FROM tomi_reports WHERE id=?',[report[1]])).rows[0];if(!r)fail(404,'REPORT_NOT_FOUND','البلاغ غير موجود.');let live=null;try{live=await target(database,r.target_type,r.target_id,{preview:true});}catch(e){if(e.status!==404)throw e;}
      respond(response,200,{report:staffReport(r),target:live,reporter:await userById(r.reporter_id,current.id)});return true;
    }
    if(path==='/v1/admin/audit'){
      const w=windowSql(page(url)),rows=(await database.query('SELECT * FROM tomi_admin_audit WHERE 1=1'+w.sql+' ORDER BY created_at DESC,id DESC LIMIT 21',w.args)).rows;
      respond(response,200,paged(rows,r=>({id:r.id,actorId:r.actor_id,action:r.action,targetType:r.target_type,targetId:r.target_id,reason:r.reason,reportId:r.report_id,details:JSON.parse(r.details),createdAt:r.created_at})));return true;
    }
    if(path==='/v1/admin/users'||path==='/v1/admin/staff'){
      const staff=path.endsWith('/staff');if(staff)await authorize(database,current,true);
      const q=(url.searchParams.get('q')??'').trim().replace(/^@/,'').toLowerCase();if(q.length>40)fail(400,'VALIDATION','نص البحث طويل.');
      const pattern='%'+q.replace(/[\\%_]/g,c=>'\\'+c)+'%',w=windowSql(page(url),'u.');
      const rows=(await database.query("SELECT u.id,u.created_at FROM tomi_users u WHERE u.username LIKE ? ESCAPE '\\'"+(staff?" AND (u.id=? OR EXISTS(SELECT 1 FROM tomi_platform_roles p WHERE p.user_id=u.id AND p.role='moderator'))":'')+w.sql+' ORDER BY u.created_at DESC,u.id DESC LIMIT 21',[pattern,...(staff?[ownerUserId??'']:[]),...w.args])).rows;
      const users=await usersByIds(rows.slice(0,20).map(r=>r.id),current.id),result=paged(rows);
      result.items=await Promise.all(result.items.map(async r=>({user:users.get(r.id),state:{...await accountState(database,r.id),...((await role(database,current.id))==='owner'?await accountEconomy(database,r.id):{})}})));respond(response,200,result);return true;
    }
    if(path==='/v1/admin/posts'){
      const w=windowSql(page(url),'p.'),rows=(await database.query("SELECT p.id,p.user_id,p.body,p.created_at,COALESCE(m.hidden,0) hidden,COALESCE(m.revision,0) revision FROM tomi_posts p LEFT JOIN tomi_content_moderation m ON m.target_type='post' AND m.target_id=p.id WHERE 1=1"+w.sql+' ORDER BY p.created_at DESC,p.id DESC LIMIT 21',w.args)).rows;
      const users=await usersByIds(rows.slice(0,20).map(r=>r.user_id),current.id),result=paged(rows),own=await role(database,current.id);
      result.items=await Promise.all(result.items.map(async r=>({id:r.id,text:r.body,createdAt:r.created_at,user:users.get(r.user_id),hidden:!!Number(r.hidden),revision:Number(r.revision),protected:own!=='owner'&&(await role(database,r.user_id))!=='member'})));
      respond(response,200,result);return true;
    }
    if(path==='/v1/admin/rooms'){
      const state=url.searchParams.get('state')??'open';if(!['open','closed','all'].includes(state))fail(400,'VALIDATION','حالة الغرفة غير صحيحة.');
      const w=windowSql(page(url),'r.'),rows=(await database.query('SELECT r.*,(SELECT COUNT(*) FROM tomi_voice_members m WHERE m.room_id=r.id AND m.state=\'active\') member_count FROM tomi_voice_rooms r WHERE '+(state==='all'?'1=1':'r.state=?')+w.sql+' ORDER BY r.created_at DESC,r.id DESC LIMIT 21',[...(state==='all'?[]:[state]),...w.args])).rows,result=paged(rows);
      result.items=await Promise.all(result.items.map(async r=>({id:r.id,title:r.title,ownerId:r.owner_id,state:r.state,memberCount:Number(r.member_count),createdAt:r.created_at,moderation:await contentState(database,'room',r.id)})));respond(response,200,result);return true;
    }
    return false;
  }
  return {handle,active,role};
}
