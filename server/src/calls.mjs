import {requireContact} from './contact_preferences.mjs';
import {randomUUID} from 'node:crypto';
import {ApiError,digest} from './security.mjs';
import {mediaChangeSnapshot,expireMediaChange,endMediaChanges,changeCallMedia,signalMediaPolicy} from './call_media.mjs';
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const stamp=(offset=0)=>new Date(Date.now()+offset).toISOString();
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const id=v=>{if(typeof v!=='string'||!uuid.test(v))fail(400,'VALIDATION','معرّف غير صحيح.');return v;};
const fields=(d,allowed)=>{if(Object.keys(d).some(k=>!allowed.includes(k)))fail(400,'VALIDATION','طلب المكالمة غير صحيح.');};
export function createCalls({database,iceProvider,readJson,respond,limit,userById,emit=()=>{},enqueuePush=async()=>{},autoSweep=true}) {
  let closed=false,checking=false;
  const iceCache=new Map();
  const notify=r=>emit([r.caller_id,r.callee_id],{type:'call.changed',callId:r.id,conversationId:r.thread_id});
  async function row(db,viewer,callId,lock=false) {
    if(lock)await db.query('UPDATE tomi_calls SET updated_at=updated_at WHERE id=? AND (caller_id=? OR callee_id=?) RETURNING id',[callId,viewer,viewer]);
    const r=(await db.query('SELECT * FROM tomi_calls WHERE id=? AND (caller_id=? OR callee_id=?)',[callId,viewer,viewer])).rows[0];
    if(!r)fail(404,'CALL_NOT_FOUND','المكالمة غير موجودة.');return r;
  }
  const owner=(r,current)=>r.caller_id===current.id?r.caller_session===current.tokenHash:r.callee_session===current.tokenHash;
  async function snapshot(r,current) {
    return {id:r.id,conversationId:r.thread_id,kind:r.kind,state:r.state,reason:r.reason,isCaller:r.caller_id===current.id,
      canControl:r.state!=='ended'&&(owner(r,current)||r.callee_id===current.id&&r.state==='ringing'),
      createdAt:r.created_at,ringDeadline:r.ring_deadline,acceptedAt:r.accepted_at,connectedAt:r.connected_at,endedAt:r.ended_at,
      mediaChange:await mediaChangeSnapshot(database,r,current),
      peer:await userById(r.caller_id===current.id?r.callee_id:r.caller_id,current.id)};
  }
  async function end(db,r,reason) {
    if(r.state==='ended')return r;
    await db.query("UPDATE tomi_calls SET state='ended',reason=?,ended_at=?,updated_at=? WHERE id=?",[reason,stamp(),stamp(),r.id]);
    await db.query('DELETE FROM tomi_active_calls WHERE call_id=?',[r.id]);
    await db.query('DELETE FROM tomi_call_signals WHERE call_id=?',[r.id]);
    await endMediaChanges(db,r);
    for(const key of iceCache.keys())if(key.startsWith(r.id+':'))iceCache.delete(key);
    return {...r,state:'ended',reason,ended_at:stamp()};
  }
  async function expire(db,r) {
    if(r.state==='ended')return r;
    r=await expireMediaChange(db,r);
    let reason;
    if((await db.query('SELECT 1 FROM tomi_user_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)',[r.caller_id,r.callee_id,r.callee_id,r.caller_id])).rows.length)reason='blocked';
    else {
      const sessions=[r.caller_session,...(r.callee_session?[r.callee_session]:[])];
      const valid=(await db.query(`SELECT s.token_hash FROM tomi_sessions s JOIN tomi_users u ON u.id=s.user_id AND u.auth_version=s.auth_version WHERE s.expires_at>? AND s.token_hash IN (${sessions.map(()=>'?').join(',')})`,[stamp(),...sessions])).rows;
      if(valid.length!==sessions.length)reason='session_ended';
      else if(r.state==='ringing'&&r.ring_deadline<=stamp())reason='missed';
      else if(r.state==='connecting'&&r.connect_deadline<=stamp())reason='failed';
      else if(r.caller_seen<stamp(-40000)||r.callee_session&&r.callee_seen<stamp(-40000))reason='disconnected';
      else if(r.connected_at&&r.connected_at<stamp(-7200000))reason='duration_limit';
    }
    return reason?end(db,r,reason):r;
  }
  async function sweep() {
    if(checking||closed)return;checking=true;
    try {
      const list=(await database.query("SELECT id,caller_id FROM tomi_calls WHERE state<>'ended' ORDER BY caller_seen LIMIT 200")).rows;
      for(const v of list) {
        if(closed)break;
        const r=await database.transaction(async db=>expire(db,await row(db,v.caller_id,v.id,true)));
        if(r.state==='ended')notify(r);
      }
    } finally {checking=false;}
  }
  async function handle(request,response,url,current) {
    const path=url.pathname,method=request.method;
    if(!path.startsWith('/v1/calls'))return false;
    if(path==='/v1/calls/settings'&&method==='GET'){respond(response,200,{configured:!!iceProvider,mediaSwitch:true,setupRequired:iceProvider?null:'turn',ringTimeoutSeconds:35,maxDurationSeconds:7200});return true;}
    if(path==='/v1/calls/active'&&method==='GET') {
      const active=(await database.query('SELECT call_id FROM tomi_active_calls WHERE user_id=?',[current.id])).rows[0];
      let r=null;if(active){r=await database.transaction(async db=>expire(db,await row(db,current.id,active.call_id,true)));if(r.state==='ended'){notify(r);r=null;}}
      respond(response,200,{configured:!!iceProvider,call:r?await snapshot(r,current):null});return true;
    }
    if(path==='/v1/calls'&&method==='GET') {
      const before=url.searchParams.get('before');
      if(before!==null&&(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\|[a-f0-9-]{36}$/.test(before)))fail(400,'VALIDATION','صفحة المكالمات غير صحيحة.');
      const values=[current.id,current.id];let page='';
      if(before){const [time,key]=before.split('|');id(key);page=' AND (created_at<? OR (created_at=? AND id<?))';values.push(time,time,key);}
      const rows=(await database.query('SELECT * FROM tomi_calls WHERE (caller_id=? OR callee_id=?)'+page+' ORDER BY created_at DESC,id DESC LIMIT 31',values)).rows;
      const calls=await Promise.all(rows.slice(0,30).map(r=>snapshot(r,current))),last=rows[29];
      respond(response,200,{calls,nextBefore:rows.length>30?last.created_at+'|'+last.id:null});return true;
    }
    if(path==='/v1/calls'&&method==='POST') {
      await limit('call-start:'+current.id,8);
      const d=await readJson(request);fields(d,['conversationId','requestId','kind']);id(d.conversationId);id(d.requestId);
      if(!['audio','video'].includes(d.kind))fail(400,'VALIDATION','اختَر صوت أو فيديو.');
      if(!iceProvider)fail(503,'CALLS_DISABLED','المكالمات غير متاحة حاليًا؛ جرّب لاحقًا.');
      const result=await database.transaction(async db=>{
        const t=(await db.query('SELECT * FROM tomi_chat_threads WHERE id=? AND (low_user_id=? OR high_user_id=?)',[d.conversationId,current.id,current.id])).rows[0];
        if(!t)fail(404,'CHAT_NOT_FOUND','المحادثة غير موجودة.');
        for(const user of [t.low_user_id,t.high_user_id])await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING id',[user]);
        // A suspension may commit while this request is still reading its body.
        if(!(await db.query('SELECT 1 FROM tomi_sessions s JOIN tomi_users u ON u.id=s.user_id AND u.auth_version=s.auth_version WHERE s.user_id=? AND s.token_hash=? AND s.expires_at>?',[current.id,current.tokenHash,stamp()])).rows.length)fail(401,'UNAUTHORIZED','انتهت جلسة الدخول.');
        if((await db.query('SELECT 1 FROM tomi_account_restrictions WHERE user_id IN (?,?) AND suspended=1',[t.low_user_id,t.high_user_id])).rows.length)fail(403,'CALL_UNAVAILABLE','الاتصال بهذا الحساب غير متاح.');
        const old=(await db.query('SELECT * FROM tomi_calls WHERE caller_id=? AND request_id=?',[current.id,d.requestId])).rows[0];
        if(old){if(old.thread_id!==d.conversationId||old.kind!==d.kind)fail(409,'REQUEST_CHANGED','طلب المكالمة تغيّر.');if(old.caller_session!==current.tokenHash)fail(409,'CALL_OTHER_DEVICE','المكالمة بدأت من جهاز آخر.');return {r:old,replay:true};}
        const alias=(await db.query('SELECT call_id FROM tomi_call_cross_requests WHERE user_id=? AND request_id=?',[current.id,d.requestId])).rows[0];
        if(alias){const prior=await row(db,current.id,alias.call_id);if(prior.thread_id!==d.conversationId||prior.kind!==d.kind)fail(409,'REQUEST_CHANGED','طلب المكالمة تغيّر.');if(!owner(prior,current))fail(409,'CALL_OTHER_DEVICE','تم الاتصال من جهاز آخر.');return {r:prior,replay:true};}
        const callee=t.low_user_id===current.id?t.high_user_id:t.low_user_id;
        if((await db.query('SELECT 1 FROM tomi_user_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)',[current.id,callee,callee,current.id])).rows.length)fail(403,'CHAT_BLOCKED','الاتصال غير متاح مع هذا المستخدم.');
        await requireContact(db,callee,current.id,'calls');
        // A stable call-lock order also covers two busy users calling across pairs.
        const activeRows=(await db.query('SELECT user_id,call_id FROM tomi_active_calls WHERE user_id IN (?,?)',[current.id,callee])).rows;
        const activeById=new Map(activeRows.map(v=>[v.call_id,v.user_id]));
        for(const activeId of [...activeById.keys()].sort())await expire(db,await row(db,activeById.get(activeId),activeId,true));
        const cross=(await db.query("SELECT c.* FROM tomi_calls c JOIN tomi_active_calls a ON a.call_id=c.id WHERE a.user_id=? AND c.caller_id=? AND c.callee_id=? AND c.thread_id=? AND c.state='ringing'",[current.id,callee,current.id,t.id])).rows[0];
        if(cross && cross.kind===d.kind){
          await db.query("UPDATE tomi_calls SET state='connecting',callee_session=?,callee_seen=?,accepted_at=?,connect_deadline=?,updated_at=? WHERE id=?",[current.tokenHash,stamp(),stamp(),stamp(45000),stamp(),cross.id]);
          await db.query('INSERT INTO tomi_call_cross_requests(user_id,request_id,call_id) VALUES(?,?,?)',[current.id,d.requestId,cross.id]);
          return {r:await row(db,current.id,cross.id),replay:false};
        }
        if((await db.query('SELECT 1 FROM tomi_active_calls WHERE user_id=?',[current.id])).rows.length)fail(409,'CALL_BUSY','عندك مكالمة جارية؛ أنهِها أولًا.');
        if((await db.query("SELECT 1 FROM tomi_lives WHERE user_id=? AND status='live'",[current.id])).rows.length)fail(409,'LIVE_BUSY','أنه البث قبل الاتصال.');
        if((await db.query('SELECT 1 FROM tomi_voice_presence WHERE user_id=?',[current.id])).rows.length)fail(409,'ROOM_BUSY','غادر الغرفة الصوتية قبل بدء المكالمة.');
        const busy=(await db.query('SELECT 1 FROM tomi_active_calls WHERE user_id=?',[callee])).rows.length>0||(await db.query('SELECT 1 FROM tomi_voice_presence WHERE user_id=?',[callee])).rows.length>0||(await db.query("SELECT 1 FROM tomi_lives WHERE user_id=? AND status='live'",[callee])).rows.length>0;
        const callId=randomUUID(),time=stamp(),ring=stamp(35000);
        await db.query(`INSERT INTO tomi_calls(id,thread_id,caller_id,callee_id,caller_session,request_id,kind,state,reason,created_at,updated_at,ring_deadline,caller_seen,ended_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,[callId,t.id,current.id,callee,current.tokenHash,d.requestId,d.kind,busy?'ended':'ringing',busy?'busy':null,time,time,ring,time,busy?time:null]);
        if(!busy){for(const user of [current.id,callee])await db.query('INSERT INTO tomi_active_calls(user_id,call_id) VALUES(?,?)',[user,callId]);await enqueuePush(db,{callId,recipientId:callee,threadId:t.id});}
        return {r:await row(db,current.id,callId),replay:false};
      });
      if(!result.replay)notify(result.r);
      respond(response,result.replay?200:201,{call:await snapshot(result.r,current)});return true;
    }
    const match=/^\/v1\/calls\/([a-f0-9-]{36})(?:\/(accept|decline|end|heartbeat|connected|signals|ice|media-request|media-response|media-ready|media-applied|media-cancel))?$/.exec(path);
    if(!match)return false;const callId=id(match[1]),action=match[2];
    if(method==='GET'&&!action) {
      const r=await database.transaction(async db=>expire(db,await row(db,current.id,callId,true)));if(r.state==='ended')notify(r);
      respond(response,200,{call:await snapshot(r,current)});return true;
    }
    if(action==='ice'&&method==='POST') {
      await limit('call-ice:'+current.id,8);
      const r=await database.transaction(async db=>expire(db,await row(db,current.id,callId,true)));
      if(!owner(r,current))fail(409,'CALL_OTHER_DEVICE','المكالمة على جهاز آخر.');
      if(r.state==='ended')fail(409,'CALL_ENDED','انتهت المكالمة.');
      const key=r.id+':'+current.tokenHash;let entry=iceCache.get(key);
      try{if(!entry||entry.until<Date.now()){const configuration=await iceProvider({callId,userId:current.id});entry={configuration,until:Date.now()+60000};iceCache.set(key,entry);}}
      catch{fail(503,'CALL_TURN_UNAVAILABLE','خدمة الاتصال غير متاحة حاليًا؛ جرّب مرة ثانية.');}
      const live=await row(database,current.id,callId);if(live.state==='ended'||!owner(live,current)){iceCache.delete(key);fail(409,'CALL_ENDED','انتهت المكالمة.');}
      respond(response,200,{configuration:entry.configuration});return true;
    }
    if(action==='signals'&&method==='GET') {
      const raw=url.searchParams.get('after')??'0';if(!/^\d{1,8}$/.test(raw))fail(400,'VALIDATION','مؤشر الاتصال غير صحيح.');
      const result=await database.transaction(async db=>{
        const r=await expire(db,await row(db,current.id,callId,true));
        if(!owner(r,current))fail(409,'CALL_OTHER_DEVICE','المكالمة على جهاز آخر.');
        const rows=r.state==='ended'?[]:(await db.query('SELECT sequence,signal_type,payload FROM tomi_call_signals WHERE call_id=? AND sender_id<>? AND sequence>? ORDER BY sequence LIMIT 100',[callId,current.id,Number(raw)])).rows;
        return {r,rows};
      });
      respond(response,200,{call:await snapshot(result.r,current),signals:result.rows.map(v=>({sequence:Number(v.sequence),type:v.signal_type,...JSON.parse(v.payload)})),nextAfter:result.rows.length?Number(result.rows.at(-1).sequence):Number(raw)});return true;
    }
    if(method!=='POST')return false;
    const d=await readJson(request,131072);
    if(action?.startsWith('media-')) {
      await limit('call-media:'+current.id,30);
      const r=await database.transaction(async db=>{
        const live=await expire(db,await row(db,current.id,callId,true));
        if(!owner(live,current))fail(409,'CALL_OTHER_DEVICE','المكالمة على جهاز آخر.');
        return changeCallMedia(db,live,current,action,d);
      });
      notify(r);respond(response,200,{call:await snapshot(r,current)});return true;
    }
    if(action==='signals') {
      await limit('call-signal:'+current.id,150);fields(d,['type','requestId','sdp','candidate','sdpMid','sdpMLineIndex','revision']);id(d.requestId);
      const revision=d.revision??0;
      if(!Number.isInteger(revision)||revision<0||revision>30)fail(400,'CALL_SIGNAL','جولة الاتصال غير صحيحة.');
      let payload;
      if(['offer','answer'].includes(d.type)) {
        if(typeof d.sdp!=='string'||Buffer.byteLength(d.sdp)>65536||!d.sdp.startsWith('v=0')||!d.sdp.includes('m=audio')||!d.sdp.includes('a=fingerprint:'))fail(400,'CALL_SIGNAL','وصف الاتصال غير صحيح.');
        if(d.candidate!==undefined||d.sdpMid!==undefined||d.sdpMLineIndex!==undefined)fail(400,'CALL_SIGNAL','وصف الاتصال غير صحيح.');payload={sdp:d.sdp};
      } else if(d.type==='candidate') {
        if(typeof d.candidate!=='string'||d.candidate.length>4096||!d.candidate.startsWith('candidate:')||d.sdp!==undefined||!(d.sdpMid===null||typeof d.sdpMid==='string'&&d.sdpMid.length<=64)||!(d.sdpMLineIndex===null||Number.isInteger(d.sdpMLineIndex)&&d.sdpMLineIndex>=0&&d.sdpMLineIndex<10))fail(400,'CALL_SIGNAL','بيانات الاتصال غير صحيحة.');
        payload={candidate:d.candidate,sdpMid:d.sdpMid,sdpMLineIndex:d.sdpMLineIndex};
      } else fail(400,'CALL_SIGNAL','نوع إشارة الاتصال غير صحيح.');
      payload.revision=revision;
      const raw=JSON.stringify(payload),hash=digest(d.type+raw);
      const result=await database.transaction(async db=>{
        const r=await expire(db,await row(db,current.id,callId,true));
        if(!owner(r,current))fail(409,'CALL_OTHER_DEVICE','المكالمة على جهاز آخر.');
        if(r.state==='ended')fail(409,'CALL_ENDED','انتهت المكالمة.');
        const old=(await db.query('SELECT sequence,payload_hash FROM tomi_call_signals WHERE call_id=? AND sender_id=? AND request_id=?',[callId,current.id,d.requestId])).rows[0];
        if(old){if(old.payload_hash!==hash)fail(409,'REQUEST_CHANGED','إشارة الاتصال تغيّرت.');return {r,sequence:Number(old.sequence)};}
        const policy=await signalMediaPolicy(db,r,revision,d.type,current);
        if(d.type==='offer'&&policy.offerer!==current.id||d.type==='answer'&&(policy.offerer===current.id||!['connecting','connected'].includes(r.state)))fail(403,'CALL_SIGNAL_ROLE','إشارة الاتصال غير مسموحة لهذا الطرف.');
        const descriptions=(await db.query("SELECT sender_id,signal_type,payload FROM tomi_call_signals WHERE call_id=? AND signal_type IN ('offer','answer')",[callId])).rows.filter(v=>Number(JSON.parse(v.payload).revision??0)===revision);
        if(d.type!=='candidate'&&descriptions.some(v=>v.signal_type===d.type))fail(409,'CALL_SIGNAL_EXISTS','إشارة الاتصال موجودة بالفعل.');
        if(d.type==='answer'&&!descriptions.some(v=>v.signal_type==='offer'))fail(409,'CALL_OFFER_MISSING','انتظر بدء الاتصال.');
        if(d.type==='candidate'&&!descriptions.some(v=>v.sender_id===current.id))fail(409,'CALL_SDP_MISSING','انتظر وصف الاتصال.');
        if(d.type!=='candidate'&&(policy.kind==='audio'&&d.sdp.includes('m=video')||d.sdp.includes('m=application')))fail(400,'CALL_SIGNAL','وصف الاتصال لا يطابق نوع المكالمة.');
        if(Number(r.next_seq)>=520)fail(429,'CALL_SIGNAL_LIMIT','وصل الاتصال إلى الحد المسموح.');
        const sequence=Number(r.next_seq)+1;
        await db.query('INSERT INTO tomi_call_signals(call_id,sequence,sender_id,request_id,signal_type,payload,payload_hash,created_at) VALUES(?,?,?,?,?,?,?,?)',[callId,sequence,current.id,d.requestId,d.type,raw,hash,stamp()]);
        await db.query('UPDATE tomi_calls SET next_seq=? WHERE id=?',[sequence,callId]);return {r,sequence};
      });notify(result.r);respond(response,200,{sequence:result.sequence});return true;
    }
    fields(d,action==='end'?['reason']:[]);
    const result=await database.transaction(async db=>{
      let r=await expire(db,await row(db,current.id,callId,true));
      if(action==='accept') {
        if(current.id!==r.callee_id)fail(403,'CALL_ROLE','الرد متاح للطرف المستلم فقط.');
        if(r.state==='ended')return r;
        if(r.state!=='ringing'){if(!owner(r,current))fail(409,'CALL_OTHER_DEVICE','تم الرد من جهاز آخر.');return r;}
        await db.query("UPDATE tomi_calls SET state='connecting',callee_session=?,callee_seen=?,accepted_at=?,connect_deadline=?,updated_at=? WHERE id=?",[current.tokenHash,stamp(),stamp(),stamp(45000),stamp(),r.id]);return row(db,current.id,r.id);
      }
      if(action==='decline') {
        if(current.id!==r.callee_id)fail(403,'CALL_ROLE','رفض المكالمة متاح للمستلم فقط.');
        if(r.state==='ended')return r;
        if(r.state!=='ringing')fail(409,'CALL_ALREADY_ACCEPTED','تم الرد على المكالمة بالفعل.');return end(db,r,'declined');
      }
      if(!owner(r,current))fail(409,'CALL_OTHER_DEVICE','المكالمة على جهاز آخر.');
      if(r.state==='ended')return r;
      if(action==='end') {
        if(d.reason!==undefined&&!['ended','failed','background'].includes(d.reason))fail(400,'VALIDATION','سبب الإنهاء غير صحيح.');
        return end(db,r,d.reason==='failed'?'failed':d.reason==='background'?'background':r.state==='ringing'?'cancelled':'ended');
      }
      if(action==='heartbeat') {
        const col=r.caller_id===current.id?'caller_seen':'callee_seen';await db.query(`UPDATE tomi_calls SET ${col}=? WHERE id=?`,[stamp(),r.id]);return r;
      }
      if(action==='connected') {
        if(!r.callee_session)fail(409,'CALL_NOT_ACCEPTED','المكالمة لم تُقبل بعد.');
        const col=r.caller_id===current.id?'caller_connected':'callee_connected';await db.query(`UPDATE tomi_calls SET ${col}=1 WHERE id=?`,[r.id]);
        r=await row(db,current.id,r.id);
        if(Number(r.caller_connected)&&Number(r.callee_connected)&&r.state!=='connected'){await db.query("UPDATE tomi_calls SET state='connected',connected_at=?,updated_at=? WHERE id=?",[stamp(),stamp(),r.id]);r=await row(db,current.id,r.id);}
        return r;
      }
      fail(404,'NOT_FOUND','الطلب غير موجود.');
    });if(action!=='heartbeat')notify(result);respond(response,200,{call:await snapshot(result,current)});return true;
  }
  async function invalidateSession(hash) {
    const rows=(await database.query("SELECT id,caller_id FROM tomi_calls WHERE state<>'ended' AND (caller_session=? OR callee_session=?)",[hash,hash])).rows;
    for(const v of rows){const r=await database.transaction(async db=>end(db,await row(db,v.caller_id,v.id,true),'session_ended'));notify(r);}
  }
  const timer=autoSweep?setInterval(()=>void sweep().catch(()=>console.error('Call cleanup deferred')),5000):null;timer?.unref();
  return {handle,sweep,invalidateSession,notify,
    async suspendUser(db,userId){
      const list=(await db.query("SELECT id,caller_id FROM tomi_calls WHERE state<>'ended' AND (caller_id=? OR callee_id=?) ORDER BY id",[userId,userId])).rows,ended=[];
      for(const item of list)ended.push(await end(db,await row(db,item.caller_id,item.id,true),'session_ended'));
      return ended;
    },
    close(){closed=true;if(timer)clearInterval(timer);iceCache.clear();},async cleanup(){await sweep();await database.query("DELETE FROM tomi_calls WHERE state='ended' AND ended_at<?",[stamp(-90*86400000)]);}};
}
