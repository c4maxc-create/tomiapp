import {cleanupVideoDerivatives} from './media_intents.mjs';
import {eraseChatExtras} from './chat_extras.mjs';
import {ApiError,digest,newToken,validateUsername,verifyPassword,isUniqueConflict} from './security.mjs';

const day=86400000,uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const tables={image:'tomi_image_uploads',audio:'tomi_audio_uploads',video:'tomi_video_uploads'};
export const deletionConfirmation='حذف حسابي';
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const fields=(d,allowed)=>{if(Object.keys(d).some(k=>!allowed.includes(k)))fail(400,'VALIDATION','طلب حذف الحساب غير صحيح.');};
function proof(d){if(typeof d.requestId!=='string'||!uuid.test(d.requestId)||typeof d.receiptToken!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(d.receiptToken))fail(400,'VALIDATION','معرّف طلب الحذف أو إيصال التحقق غير صحيح.');}

export function createAccountDeletion({database,guard,ownerUserId,readJson,respond,limit,session,rooms,calls,chat,storage,chatStorage,dummyHash,confirmCredential=null,authorizeSecurity=async()=>{},autoSweep=true,clock=()=>Date.now()}){
  const now=(delta=0)=>new Date(clock()+delta).toISOString();let sweeping=false,closed=false;
  async function receipt(d){
    const r=(await database.query(`SELECT r.id,d.user_id,d.requested_at,d.completed_at,r.expires_at,
      (SELECT COUNT(*) FROM tomi_erasure_media m WHERE m.user_id=d.user_id) pending_media,
      (SELECT COUNT(*) FROM tomi_voice_jobs j JOIN tomi_voice_members v ON v.identity=j.identity WHERE v.user_id=d.user_id) pending_voice,
      (SELECT COUNT(*) FROM tomi_voice_rooms v WHERE v.owner_id=d.user_id AND v.needs_delete=1) pending_rooms
      FROM tomi_deletion_receipts r JOIN tomi_deleted_accounts d ON d.user_id=r.user_id WHERE r.id=? AND r.token_hash=? AND r.expires_at>?`,[d.requestId,digest(d.receiptToken),now()])).rows[0];
    if(!r)return null;
    const pendingMedia=Number(r.pending_media),pendingVoice=Number(r.pending_voice)+Number(r.pending_rooms);
    return {requestId:r.id,accepted:true,personalDataErased:true,state:pendingMedia||pendingVoice?'cleanup_pending':'completed',pendingMedia,pendingVoice,
      requestedAt:r.requested_at,completedAt:pendingMedia||pendingVoice?null:r.completed_at??r.requested_at,receiptExpiresAt:r.expires_at,
      message:pendingMedia||pendingVoice?'حُذفت بيانات الحساب؛ تنظيف الملفات أو سحب الصوت ما زال قيد التنفيذ.':'اكتمل حذف بيانات الحساب وتنظيف الملفات وسحب الصوت.',
      retained:'تبقى معرفات عشوائية وسجلات هدايا مشتركة دون الملف الشخصي، وبيانات أمنية منقحة حتى90 يومًا. النسخ الاحتياطية ونسخ الآخرين لها حدود منفصلة موضحة بسياسة الخصوصية.'};
  }
  async function erase(row,d,current){
    const ended=[];
    try{await database.transaction(async db=>{
      await guard.gate(db,row.id,true);
      const live=(await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING *',[row.id])).rows[0];
      if(!live||live.password_hash!==row.password_hash||Number(live.auth_version)!==Number(row.auth_version))fail(409,'ACCOUNT_CHANGED','تغيّرت بيانات الحساب؛ تحقّق من حالة الطلب قبل المحاولة.');
      if(current){
        const s=(await db.query('SELECT 1 FROM tomi_sessions WHERE token_hash=? AND user_id=? AND auth_version=? AND expires_at>?',[current.tokenHash,row.id,live.auth_version,now()])).rows[0];
        if(!s)fail(401,'UNAUTHORIZED','انتهت الجلسة؛ تحقّق من الطلب أو سجّل دخولك.');
      }
      if((await db.query('SELECT 1 FROM tomi_deleted_accounts WHERE user_id=?',[row.id])).rows.length)fail(409,'ACCOUNT_DELETED','سبق حذف الحساب؛ استخدم إيصال الطلب السابق.');
      if(row.id===ownerUserId)fail(409,'OWNER_TRANSFER_REQUIRED','انقل ملكية التطبيق إلى حساب آخر في إعدادات الخدمة قبل حذف حساب المالك.');
      // Serialize existing chat writers before clearing authored content.
      const threads=(await db.query('SELECT id FROM tomi_chat_threads WHERE low_user_id=? OR high_user_id=? ORDER BY id',[row.id,row.id])).rows;
      for(const t of threads)await db.query('UPDATE tomi_chat_threads SET updated_at=updated_at WHERE id=?',[t.id]);
      await db.query('INSERT INTO tomi_deleted_accounts(user_id,requested_at) VALUES(?,?)',[row.id,now()]);
      await db.query('INSERT INTO tomi_deletion_receipts(id,user_id,token_hash,created_at,expires_at) VALUES(?,?,?,?,?)',[d.requestId,row.id,digest(d.receiptToken),now(),now(30*day)]);
      ended.push(...await calls.suspendUser(db,row.id));await rooms.suspendUser(db,row.id);
      for(const [type,table] of Object.entries(tables)){
        await db.query(`INSERT INTO tomi_erasure_media(id,user_id,media_type,upload_id,scope,object_key,final_after,next_at)
          SELECT ?||id,user_id,?,id,CASE WHEN object_key LIKE 'tomi/chat-%' THEN 'private' ELSE 'public' END,object_key,?,?
          FROM ${table} WHERE user_id=? ON CONFLICT(scope,object_key) DO NOTHING`,[type+':',type,now(16*60000),now(),row.id]);
        await db.query("UPDATE "+table+" SET state='deleting',expires_at=? WHERE user_id=?",[now(16*60000),row.id]);
      }
      // Audit/security retention is content-free and expires automatically.
      await db.query(`INSERT INTO tomi_privacy_retention(kind,id,expires_at) SELECT 'audit',id,? FROM tomi_admin_audit WHERE actor_id=? OR target_id=?
        OR target_id IN(SELECT id FROM tomi_posts WHERE user_id=?) OR target_id IN(SELECT id FROM tomi_voice_rooms WHERE owner_id=?)
        OR report_id IN(SELECT id FROM tomi_reports WHERE reporter_id=? OR subject_user_id=?) ON CONFLICT(kind,id) DO NOTHING`,[now(90*day),row.id,row.id,row.id,row.id,row.id,row.id]);
      await db.query("UPDATE tomi_admin_audit SET reason='حُذفت البيانات الشخصية',details='{}' WHERE id IN(SELECT id FROM tomi_privacy_retention WHERE kind='audit')");
      await db.query("INSERT INTO tomi_privacy_retention(kind,id,expires_at) SELECT 'report',id,? FROM tomi_reports WHERE subject_user_id=? ON CONFLICT(kind,id) DO NOTHING",[now(90*day),row.id]);
      await db.query("DELETE FROM tomi_reports WHERE reporter_id=?",[row.id]);
      await db.query("UPDATE tomi_reports SET description='',snapshot='{}',review_note='',public_message='حُذفت بيانات الهدف',status='resolved',revision=revision+1,updated_at=? WHERE subject_user_id=?",[now(),row.id]);
      await db.query("UPDATE tomi_reports SET review_note='',public_message='',reviewer_id=NULL,revision=revision+1,updated_at=? WHERE reviewer_id=?",[now(),row.id]);
      await db.query('DELETE FROM tomi_content_moderation WHERE target_type=\'post\' AND target_id IN(SELECT id FROM tomi_posts WHERE user_id=?)',[row.id]);
      for(const table of ['tomi_roulette_access','tomi_roulette_daily','tomi_roulette_spins','tomi_contribution_credits'])await db.query('DELETE FROM '+table+' WHERE user_id=?',[row.id]);
      await db.query('DELETE FROM tomi_roulette_requests WHERE actor_id=?',[row.id]);
      for(const table of ['tomi_live_roulette_bets','tomi_live_roulette_requests','tomi_live_roulette_last','tomi_live_roulette_daily','tomi_live_roulette_awards'])await db.query('DELETE FROM '+table+' WHERE user_id=?',[row.id]);
      await db.query("INSERT INTO tomi_erasure_media(id,user_id,media_type,upload_id,scope,object_key,final_after,next_at) SELECT 'secure:'||id,user_id,'image',id,'private',object_key,?,? FROM tomi_e2ee_uploads WHERE user_id=? ON CONFLICT(scope,object_key) DO NOTHING",[now(16*60000),now(),row.id]);
      await db.query('DELETE FROM tomi_e2ee_uploads WHERE user_id=?',[row.id]);
      await db.query('DELETE FROM tomi_e2ee_envelopes WHERE message_id IN(SELECT id FROM tomi_chat_messages WHERE sender_id=?)',[row.id]);
      for(const table of ['tomi_external_identities','tomi_account_auth','tomi_e2ee_devices','tomi_mfa','tomi_security_events','tomi_content_preferences','tomi_group_organisation','tomi_chat_organisation','tomi_explore_preferences','tomi_explore_hidden','tomi_support_tickets'])await db.query('DELETE FROM '+table+' WHERE user_id=?',[row.id]);
      await db.query('DELETE FROM tomi_contact_exceptions WHERE user_id=? OR target_id=?',[row.id,row.id]);
      await db.query('DELETE FROM tomi_notices WHERE recipient_id=? OR actor_id=?',[row.id,row.id]);
      await db.query('DELETE FROM tomi_invitations WHERE sender_id=? OR recipient_id=?',[row.id,row.id]);
      await db.query('DELETE FROM tomi_polls WHERE owner_id=?',[row.id]);
      await db.query('DELETE FROM tomi_poll_votes WHERE user_id=?',[row.id]);
      await db.query('DELETE FROM tomi_stories WHERE user_id=?',[row.id]);
      await db.query('DELETE FROM tomi_story_views WHERE user_id=?',[row.id]);
      await db.query('DELETE FROM tomi_story_receipts WHERE user_id=?',[row.id]);
      await db.query('DELETE FROM tomi_activity WHERE recipient_id=? OR actor_id=?',[row.id,row.id]);
      for(const table of ['tomi_post_share_receipts','tomi_post_share_requests','tomi_post_share_pairs'])await db.query('DELETE FROM '+table+' WHERE sender_id=? OR '+(table==='tomi_post_share_receipts'?'target_id':'recipient_id')+'=?',[row.id,row.id]);
      await db.query('DELETE FROM tomi_post_share_actions WHERE actor_id=?',[row.id]);
      await db.query('DELETE FROM tomi_post_shares WHERE message_id IN(SELECT id FROM tomi_chat_messages WHERE sender_id=?)',[row.id]);
      await db.query('DELETE FROM tomi_posts WHERE user_id=?',[row.id]);
      await db.query('DELETE FROM tomi_comments WHERE user_id=?',[row.id]);
      await db.query('DELETE FROM tomi_post_likes WHERE user_id=?',[row.id]);
      await db.query('DELETE FROM tomi_post_saves WHERE user_id=?',[row.id]);
      await db.query('DELETE FROM tomi_post_receipts WHERE user_id=?',[row.id]);
      for(const table of ['tomi_chat_audio','tomi_chat_video'])await db.query('DELETE FROM '+table+' WHERE message_id IN(SELECT id FROM tomi_chat_messages WHERE sender_id=?)',[row.id]);
      await db.query('DELETE FROM tomi_chat_pins WHERE pinned_by=? OR message_id IN(SELECT id FROM tomi_chat_messages WHERE sender_id=?)',[row.id,row.id]);
      await db.query("UPDATE tomi_chat_messages SET body='',image_upload_id=NULL,payload_hash='',deleted_at=COALESCE(deleted_at,?) WHERE sender_id=?",[now(),row.id]);
      await db.query('UPDATE tomi_chat_message_meta SET media_sha256=NULL WHERE message_id IN(SELECT id FROM tomi_chat_messages WHERE sender_id=?)',[row.id]);
      await db.query('DELETE FROM tomi_chat_reactions WHERE user_id=?',[row.id]);
      await db.query('UPDATE tomi_chat_members SET last_read_seq=0,visible=0 WHERE user_id=?',[row.id]);
      await db.query('DELETE FROM tomi_push_outbox WHERE recipient_id=? OR message_id IN(SELECT id FROM tomi_chat_messages WHERE sender_id=?)',[row.id,row.id]);
      await eraseChatExtras(db,row.id,now);
      await db.query('DELETE FROM tomi_user_avatars WHERE user_id=?',[row.id]);
      await db.query('UPDATE tomi_room_options SET image_upload_id=NULL WHERE image_upload_id IN(SELECT id FROM tomi_image_uploads WHERE user_id=?)',[row.id]);
      await db.query("UPDATE tomi_room_options SET announcement='',password_hash=NULL,category='الأصدقاء',mode='عادي',picture='headphones' WHERE room_id IN(SELECT id FROM tomi_voice_rooms WHERE owner_id=?)",[row.id]);
      await db.query("UPDATE tomi_voice_rooms SET title='غرفة حساب محذوف' WHERE owner_id=?",[row.id]);
      await db.query('DELETE FROM tomi_room_entry_effects WHERE (room_id,sequence) IN(SELECT room_id,sequence FROM tomi_room_events WHERE actor_id=?)',[row.id]);
      await db.query("UPDATE tomi_room_events SET body='',image_upload_id=NULL WHERE actor_id=?",[row.id]);
      await db.query("UPDATE tomi_room_audit SET detail='' WHERE actor_id=? OR room_id IN(SELECT id FROM tomi_voice_rooms WHERE owner_id=?) OR detail LIKE ?",[row.id,row.id,'%'+row.id+'%']);
      await db.query('DELETE FROM tomi_room_invites WHERE user_id=? OR invited_by=?',[row.id,row.id]);
      await db.query("UPDATE tomi_voice_members SET session_hash='',requested_at=NULL WHERE user_id=?",[row.id]);
      await db.query('DELETE FROM tomi_video_posters WHERE upload_id IN(SELECT id FROM tomi_video_uploads WHERE user_id=?)',[row.id]);
      await db.query('DELETE FROM tomi_private_video_posters WHERE upload_id IN(SELECT id FROM tomi_private_uploads WHERE user_id=?)',[row.id]);
      await db.query('DELETE FROM tomi_follows WHERE follower_id=? OR following_id=?',[row.id,row.id]);
      await db.query('DELETE FROM tomi_user_blocks WHERE blocker_id=? OR blocked_id=?',[row.id,row.id]);
      await db.query("UPDATE tomi_game_matches SET status='cancelled',state='{}',host_id=NULL,revision=revision+1 WHERE id IN(SELECT match_id FROM tomi_game_players WHERE user_id=?)",[row.id]);
      for(const table of ['tomi_saved_collections','tomi_contact_preferences','tomi_muted_chats','tomi_staff_permissions','tomi_admin_profiles','tomi_policy_acceptances','tomi_avatar_requests','tomi_media_intents','tomi_user_progress','tomi_user_identity','tomi_room_cosmetics','tomi_cosmetic_purchases','tomi_room_chat_cursors','tomi_room_preferences','tomi_room_entry_cooldowns','tomi_room_wallets','tomi_platform_roles','tomi_admin_requests','tomi_push_settings','tomi_push_devices','tomi_sessions','tomi_game_requests','tomi_game_awards','tomi_game_progress','tomi_game_players','tomi_roulette_watchers','tomi_call_cross_requests','tomi_message_receipts','tomi_live_watchers'])await db.query('DELETE FROM '+table+' WHERE '+(table==='tomi_admin_requests'?'actor_id':'user_id')+'=?',[row.id]);
      await db.query('DELETE FROM tomi_message_edits WHERE message_id IN(SELECT id FROM tomi_chat_messages WHERE sender_id=? UNION SELECT id FROM tomi_group_messages WHERE sender_id=?)',[row.id,row.id]);
      await db.query('DELETE FROM tomi_message_receipts WHERE message_id IN(SELECT id FROM tomi_chat_messages WHERE sender_id=? UNION SELECT id FROM tomi_group_messages WHERE sender_id=?)',[row.id,row.id]);
      await db.query("INSERT INTO tomi_live_cleanup(room,created_at) SELECT 'tomi-live-'||id,? FROM tomi_lives WHERE user_id=? ON CONFLICT(room) DO NOTHING",[Date.now(),row.id]);
      await db.query("INSERT INTO tomi_live_revoke(room,identity,created_at) SELECT 'tomi-live-'||b.a_id,'live-'||l.user_id||'-'||substr(l.session_hash,1,16),? FROM tomi_live_battles b JOIN tomi_lives l ON (l.id=b.a_id OR l.id=b.b_id) WHERE b.state='playing' AND (b.a_id IN(SELECT id FROM tomi_lives WHERE user_id=?) OR b.b_id IN(SELECT id FROM tomi_lives WHERE user_id=?)) ON CONFLICT(room,identity) DO NOTHING",[Date.now(),row.id,row.id]);
      await db.query("INSERT INTO tomi_live_cleanup(room,created_at) SELECT 'tomi-live-'||b.a_id,? FROM tomi_live_battles b WHERE b.state='playing' AND (b.a_id IN(SELECT id FROM tomi_lives WHERE user_id=?) OR b.b_id IN(SELECT id FROM tomi_lives WHERE user_id=?)) ON CONFLICT(room) DO NOTHING",[Date.now(),row.id,row.id]);
      await db.query("UPDATE tomi_lives SET status='ended',title='',session_hash='' WHERE user_id=?",[row.id]);
      await db.query("UPDATE tomi_live_battles SET state='cancelled' WHERE a_id IN(SELECT id FROM tomi_lives WHERE user_id=?) OR b_id IN(SELECT id FROM tomi_lives WHERE user_id=?)",[row.id,row.id]);
      await db.query('DELETE FROM tomi_live_actions WHERE user_id=?',[row.id]);
      await db.query("UPDATE tomi_calls SET caller_session='' WHERE caller_id=?",[row.id]);
      await db.query("UPDATE tomi_calls SET callee_session='' WHERE callee_id=?",[row.id]);
      await db.query("INSERT INTO tomi_account_restrictions(user_id,suspended,revision,reason,updated_by,updated_at) VALUES(?,1,1,'حساب محذوف',?,?) ON CONFLICT(user_id) DO UPDATE SET suspended=1,revision=tomi_account_restrictions.revision+1,reason=excluded.reason,updated_by=excluded.updated_by,updated_at=excluded.updated_at",[row.id,row.id,now()]);
      await db.query("UPDATE tomi_users SET username=?,display_name='حساب محذوف',bio='',avatar_preset='initials',password_hash=?,recovery_hash=?,auth_version=auth_version+1,updated_at=? WHERE id=?",['deleted_'+row.id.replaceAll('-',''),'erased:'+newToken(),digest(newToken()),now(),row.id]);
    });}catch(error){const accepted=await receipt(d);if(accepted)return accepted;if(isUniqueConflict(error))fail(409,'DELETION_REQUEST_CHANGED','الطلب مستخدم أو سبق حذف الحساب؛ تحقّق من الإيصال الأصلي.');throw error;}
    chat.invalidateUser(row.id);for(const r of ended)calls.notify(r);
    // Cleanup is durable; provider failures cannot undo the accepted erasure.
    if(autoSweep)void sweep().catch(()=>{});return receipt(d);
  }
  async function handle(request,response,url,{ip}){
    const path=url.pathname,method=request.method;
    if(method==='GET'&&path==='/v1/account/deletion/preview'){
      const current=await session(request),r=(await database.query(`SELECT
        (SELECT COUNT(*) FROM tomi_posts WHERE user_id=?) posts,(SELECT COUNT(*) FROM tomi_chat_messages WHERE sender_id=? AND deleted_at IS NULL) messages,
        (SELECT COUNT(*) FROM tomi_voice_rooms WHERE owner_id=? AND state='open') ownedRooms`,[current.id,current.id,current.id])).rows[0];
      respond(response,200,{confirmation:deletionConfirmation,canDelete:current.id!==ownerUserId,ownerTransferRequired:current.id===ownerUserId,counts:Object.fromEntries(Object.entries(r).map(([k,v])=>[k,Number(v)])),receiptDays:30,securityRetentionDays:90,uploadExpiryMinutes:16});return true;
    }
    if(method!=='POST'||!['/v1/account/deletion','/v1/account/deletion/web','/v1/account/deletion/status'].includes(path))return false;
    await limit('deletion:ip:'+ip,path.endsWith('/status')?60:10,900000);
    const d=await readJson(request,8192),status=path.endsWith('/status'),web=path.endsWith('/web');
    fields(d,status?['requestId','receiptToken']:['requestId','receiptToken','password','confirmation','mfaCode','identityToken',...(web?['username']:[])]);proof(d);
    const accepted=await receipt(d);if(accepted){respond(response,200,accepted);return true;}
    if(status)fail(404,'DELETION_RECEIPT_MISSING','إيصال الحذف غير موجود أو انتهت صلاحيته.');
    if(d.confirmation!==deletionConfirmation)fail(400,'DELETION_CONFIRMATION','اكتب «حذف حسابي» لتأكيد القرار.');
    try{let current=null,row;
    if(web){const username=validateUsername(d.username);await limit('deletion:user:'+username,5,900000);row=(await database.query('SELECT * FROM tomi_users WHERE username=?',[username])).rows[0];}
    else{current=await session(request);await limit('deletion:account:'+current.id,5,900000);row=(await database.query('SELECT * FROM tomi_users WHERE id=?',[current.id])).rows[0];}
    const password=typeof d.password==='string'&&[...d.password].length<=128?d.password:'';
    if(confirmCredential&&row)await confirmCredential(row,d);
    if((!confirmCredential||!row)&&!await verifyPassword(password,row?.password_hash||dummyHash)||!row)fail(400,'BAD_CREDENTIALS','بيانات الحساب أو كلمة المرور غير صحيحة.');
    if((await database.query('SELECT 1 FROM tomi_deletion_receipts WHERE id=?',[d.requestId])).rows.length)fail(409,'DELETION_REQUEST_CHANGED','رقم الطلب مستخدم؛ تحقّق من الإيصال الأصلي.');
    await authorizeSecurity(row,d,current);
    const result=await erase(row,d,current);respond(response,202,result);return true;
    }catch(error){const replay=await receipt(d);if(replay){respond(response,200,replay);return true;}throw error;}
  }
  async function sweep(){
    if(sweeping||closed)return;sweeping=true;
    try{
      await guard.unbound(async()=>{
        const jobs=(await database.query('SELECT * FROM tomi_erasure_media WHERE next_at<=? AND lease_until<=? ORDER BY next_at,id LIMIT 20',[now(),now()])).rows;
        for(const job of jobs){if(closed)break;const claimed=await database.query('UPDATE tomi_erasure_media SET lease_until=?,attempts=attempts+1 WHERE id=? AND lease_until<=? AND next_at<=?',[now(60000),job.id,now(),now()]);if(claimed.changes!==1)continue;
          try{
            const store=job.scope==='private'?chatStorage:storage;if(!store||!job.object_key.startsWith('tomi/'))throw Error('STORAGE_UNAVAILABLE');
            const multipart=(await database.query('SELECT provider_id FROM tomi_multipart_uploads WHERE upload_id=?',[job.upload_id])).rows[0];
            if(multipart){if(!store.abortMultipart)throw Error('MULTIPART_CLEANUP_UNAVAILABLE');await store.abortMultipart(job.object_key,multipart.provider_id);await database.query('DELETE FROM tomi_multipart_uploads WHERE upload_id=?',[job.upload_id]);}
            await cleanupVideoDerivatives(database,store,job.upload_id,job.object_key);
            await store.delete(job.object_key);
            if(job.final_after>now())await database.query("UPDATE tomi_erasure_media SET next_at=final_after,lease_until='' WHERE id=?",[job.id]);
            else await database.transaction(async db=>{await db.query('DELETE FROM '+tables[job.media_type]+' WHERE id=? AND user_id=?',[job.upload_id,job.user_id]);await db.query('DELETE FROM tomi_upload_digests WHERE upload_id=?',[job.upload_id]);await db.query('DELETE FROM tomi_erasure_media WHERE id=?',[job.id]);});
          }catch{await database.query("UPDATE tomi_erasure_media SET lease_until='',next_at=? WHERE id=?",[now(Math.min(3600000,30000*2**Math.min(Number(job.attempts),6))),job.id]);}
        }
        await rooms.flush();
        await database.query(`UPDATE tomi_deleted_accounts SET completed_at=? WHERE completed_at IS NULL
          AND NOT EXISTS(SELECT 1 FROM tomi_erasure_media m WHERE m.user_id=tomi_deleted_accounts.user_id)
          AND NOT EXISTS(SELECT 1 FROM tomi_voice_jobs j JOIN tomi_voice_members v ON v.identity=j.identity WHERE v.user_id=tomi_deleted_accounts.user_id)
          AND NOT EXISTS(SELECT 1 FROM tomi_voice_rooms r WHERE r.owner_id=tomi_deleted_accounts.user_id AND r.needs_delete=1)`,[now()]);
        await database.query("DELETE FROM tomi_reports WHERE id IN(SELECT id FROM tomi_privacy_retention WHERE kind='report' AND expires_at<=?)",[now()]);
        await database.query("DELETE FROM tomi_admin_audit WHERE id IN(SELECT id FROM tomi_privacy_retention WHERE kind='audit' AND expires_at<=?)",[now()]);
        await database.query('DELETE FROM tomi_privacy_retention WHERE expires_at<=?',[now()]);
        await database.query('DELETE FROM tomi_deletion_receipts WHERE expires_at<=?',[now()]);
      });
    }finally{sweeping=false;}
  }
  const timer=autoSweep?setInterval(()=>void sweep().catch(()=>{}),15000):null;timer?.unref();
  return {handle,sweep,close(){closed=true;if(timer)clearInterval(timer);}};
}
