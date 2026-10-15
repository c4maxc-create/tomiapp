import {ApiError} from './security.mjs';

const now=(offset=0)=>new Date(Date.now()+offset).toISOString();
const fail=(code,message,status=409)=>{throw new ApiError(status,code,message);};
const active=new Set(['pending','accepted','negotiating']);
const token=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const only=(d,keys)=>{if(Object.keys(d).some(k=>!keys.includes(k))||typeof d.requestId!=='string'||!token.test(d.requestId))fail('VALIDATION','طلب التحويل غير صحيح.',400);};

export async function latestMediaChange(db,callId) {
  return (await db.query('SELECT * FROM tomi_call_media_changes WHERE call_id=? ORDER BY revision DESC LIMIT 1',[callId])).rows[0]??null;
}
export async function mediaChangeSnapshot(db,r,current) {
  const m=await latestMediaChange(db,r.id);
  return m?{requestId:m.request_id,kind:m.target_kind,state:m.state,revision:Number(m.revision),requestedByMe:m.requester_id===current.id,deadline:m.deadline}:null;
}
async function abort(db,r,m,state) {
  await db.query('UPDATE tomi_call_media_changes SET state=?,updated_at=? WHERE call_id=? AND request_id=?',[state,now(),r.id,m.request_id]);
  if(m.state==='negotiating') {
    await db.query('UPDATE tomi_calls SET kind=?,updated_at=? WHERE id=?',[m.previous_kind,now(),r.id]);
    return {...r,kind:m.previous_kind};
  }
  return r;
}
export async function expireMediaChange(db,r) {
  const m=await latestMediaChange(db,r.id);
  return m&&active.has(m.state)&&m.deadline<=now()?abort(db,r,m,'expired'):r;
}
export async function endMediaChanges(db,r) {
  await db.query("UPDATE tomi_call_media_changes SET state='cancelled',updated_at=? WHERE call_id=? AND state IN ('pending','accepted','negotiating')",[now(),r.id]);
}

// The caller must lock the parent call and authenticate its owning session.
// Video negotiation is allowed only after consent AND both cameras are ready.
export async function changeCallMedia(db,r,current,action,d) {
  only(d,action==='media-request'?['requestId','kind']:action==='media-response'?['requestId','accept']:action==='media-ready'?['requestId','ready']:['requestId']);
  if(r.state!=='connected')fail('CALL_NOT_CONNECTED','انتظر اكتمال الاتصال أولًا.');
  let m=await latestMediaChange(db,r.id);
  if(action==='media-request') {
    if(!['audio','video'].includes(d.kind))fail('VALIDATION','اختَر صوت أو فيديو.',400);
    const old=(await db.query('SELECT * FROM tomi_call_media_changes WHERE call_id=? AND request_id=?',[r.id,d.requestId])).rows[0];
    if(old) {
      if(old.requester_id!==current.id||old.target_kind!==d.kind)fail('REQUEST_CHANGED','طلب التحويل تغيّر.');
      return r;
    }
    if(m&&active.has(m.state))fail('CALL_MEDIA_PENDING','عندك طلب تحويل قائم بالفعل.');
    if(r.kind===d.kind)fail('CALL_MEDIA_UNCHANGED','المكالمة من هذا النوع بالفعل.');
    const revision=Number(m?.revision??0)+1;
    if(revision>30)fail('CALL_MEDIA_LIMIT','وصلت المكالمة إلى حد تبديل النوع.',429);
    const state=d.kind==='video'?'pending':'applied';
    await db.query('INSERT INTO tomi_call_media_changes(call_id,request_id,requester_id,previous_kind,target_kind,revision,state,created_at,updated_at,deadline) VALUES(?,?,?,?,?,?,?,?,?,?)',[r.id,d.requestId,current.id,r.kind,d.kind,revision,state,now(),now(),now(30000)]);
    if(d.kind==='audio') {
      // Turning cameras off needs no new SDP; replaceTrack(null) keeps audio
      // and the existing transport alive. A future video request needs consent.
      await db.query("UPDATE tomi_calls SET kind='audio',updated_at=? WHERE id=?",[now(),r.id]);
      return {...r,kind:'audio'};
    }
    return r;
  }
  if(!m||m.request_id!==d.requestId)fail('CALL_MEDIA_STALE','طلب التحويل لم يعد متاحًا.');
  if(action==='media-response') {
    if(typeof d.accept!=='boolean')fail('VALIDATION','اختَر قبول أو رفض التحويل.',400);
    if(m.requester_id===current.id)fail('CALL_MEDIA_ROLE','الموافقة من الطرف الثاني فقط.',403);
    if(m.state!=='pending') {
      if(d.accept&&['accepted','negotiating','applied'].includes(m.state)||!d.accept&&m.state==='declined')return r;
      fail('CALL_MEDIA_STALE','انتهى طلب التحويل.');
    }
    await db.query('UPDATE tomi_call_media_changes SET state=?,deadline=?,updated_at=? WHERE call_id=? AND request_id=?',[d.accept?'accepted':'declined',now(d.accept?60000:0),now(),r.id,m.request_id]);
    return r;
  }
  if(action==='media-cancel') {
    if(m.state==='pending'&&m.requester_id!==current.id)fail('CALL_MEDIA_ROLE','إلغاء الطلب متاح لمن أرسله.',403);
    if(active.has(m.state))return abort(db,r,m,'cancelled');
    return r;
  }
  if(action==='media-ready') {
    if(typeof d.ready!=='boolean')fail('VALIDATION','حالة الكاميرا غير صحيحة.',400);
    if(!['accepted','negotiating','applied'].includes(m.state))fail('CALL_MEDIA_STALE','طلب الفيديو لم تتم الموافقة عليه.');
    if(m.state==='applied')return r;
    if(!d.ready)return abort(db,r,m,'failed');
    const column=r.caller_id===current.id?'caller_ready':'callee_ready';
    await db.query(`UPDATE tomi_call_media_changes SET ${column}=1,updated_at=? WHERE call_id=? AND request_id=?`,[now(),r.id,m.request_id]);
    m=await latestMediaChange(db,r.id);
    if(m.state==='accepted'&&Number(m.caller_ready)&&Number(m.callee_ready)) {
      await db.query("UPDATE tomi_call_media_changes SET state='negotiating',deadline=?,updated_at=? WHERE call_id=? AND request_id=?",[now(30000),now(),r.id,m.request_id]);
      await db.query("UPDATE tomi_calls SET kind='video',updated_at=? WHERE id=?",[now(),r.id]);
      return {...r,kind:'video'};
    }
    return r;
  }
  if(action==='media-applied') {
    if(m.state==='applied')return r;
    if(m.state!=='negotiating')fail('CALL_MEDIA_STALE','طلب التحويل لم يعد متاحًا.');
    const descriptions=(await db.query("SELECT signal_type,payload FROM tomi_call_signals WHERE call_id=? AND signal_type IN ('offer','answer')",[r.id])).rows.filter(v=>Number(JSON.parse(v.payload).revision??0)===Number(m.revision));
    if(descriptions.length!==2)fail('CALL_MEDIA_NOT_READY','انتظر اكتمال تحويل الاتصال.');
    const column=r.caller_id===current.id?'caller_applied':'callee_applied';
    await db.query(`UPDATE tomi_call_media_changes SET ${column}=1,updated_at=? WHERE call_id=? AND request_id=?`,[now(),r.id,m.request_id]);
    m=await latestMediaChange(db,r.id);
    if(Number(m.caller_applied)&&Number(m.callee_applied))await db.query("UPDATE tomi_call_media_changes SET state='applied',updated_at=? WHERE call_id=? AND request_id=?",[now(),r.id,m.request_id]);
    return r;
  }
  fail('NOT_FOUND','الطلب غير موجود.',404);
}

export async function signalMediaPolicy(db,r,revision,type,current) {
  if(!revision)return {offerer:r.caller_id,kind:r.kind};
  const m=(await db.query('SELECT * FROM tomi_call_media_changes WHERE call_id=? AND revision=?',[r.id,revision])).rows[0];
  if(!m||m.target_kind!=='video'||!['negotiating','applied'].includes(m.state))fail('CALL_MEDIA_NOT_READY','لم تكتمل الموافقة على الفيديو.');
  if(type!=='candidate') {
    const latest=await latestMediaChange(db,r.id);
    if(latest.revision!==m.revision||r.kind!=='video')fail('CALL_MEDIA_STALE','تغيّر نوع المكالمة.');
  }
  return {offerer:m.requester_id,kind:'video'};
}
