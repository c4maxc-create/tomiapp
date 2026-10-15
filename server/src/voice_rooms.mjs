import {randomUUID} from 'node:crypto';
import {ApiError} from './security.mjs';

const stamp=(delta=0)=>new Date(Date.now()+delta).toISOString();
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const uuid=v=>typeof v==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(v);
const fields=(d,keys)=>{if(Object.keys(d).some(k=>!keys.includes(k)))fail(400,'VALIDATION','طلب الغرفة غير صحيح.');};

export function createVoiceRooms({database,provider,readJson,respond,limit,usersByIds,autoSweep=true}) {
  let stopped=false,sweeping=false,flushing=false;
  async function lock(db,id){
    await db.query('UPDATE tomi_voice_rooms SET revision=revision WHERE id=? RETURNING id',[id]);
    const r=(await db.query('SELECT * FROM tomi_voice_rooms WHERE id=?',[id])).rows[0];
    if(!r)fail(404,'ROOM_NOT_FOUND','الغرفة غير موجودة.');return r;
  }
  async function member(db,r,current,required=true){
    const m=(await db.query("SELECT * FROM tomi_voice_members WHERE room_id=? AND user_id=? AND state='active'",[r.id,current.id])).rows[0];
    if(!m&&required)fail(403,'ROOM_MEMBERSHIP','انضم للغرفة أولًا.');
    if(m&&m.session_hash!==current.tokenHash)fail(409,'ROOM_OTHER_DEVICE','الغرفة مفتوحة على جهاز آخر.');return m;
  }
  async function bump(db,r){await db.query('UPDATE tomi_voice_rooms SET revision=revision+1 WHERE id=?',[r.id]);}
  async function job(db,r,m,publish){
    await db.query(`INSERT INTO tomi_voice_jobs(identity,room_id,publish) VALUES(?,?,?)
      ON CONFLICT(identity) DO UPDATE SET publish=excluded.publish,version=tomi_voice_jobs.version+1`,[m.identity,r.id,publish]);
  }
  async function empty(db,r){
    if(!(await db.query("SELECT 1 FROM tomi_voice_members WHERE room_id=? AND state='active'",[r.id])).rows.length)
      await db.query('UPDATE tomi_voice_rooms SET empty_since=COALESCE(empty_since,?) WHERE id=?',[stamp(),r.id]);
  }
  async function remove(db,r,m,state='left'){
    await db.query('UPDATE tomi_voice_members SET state=?,seat=NULL,mic_allowed=0,requested_at=NULL WHERE room_id=? AND user_id=?',[state,r.id,m.user_id]);
    await db.query('DELETE FROM tomi_voice_presence WHERE user_id=? AND room_id=?',[m.user_id,r.id]);
    await job(db,r,m,-1);await bump(db,r);await empty(db,r);
  }
  async function closeRoom(db,r){
    const all=(await db.query("SELECT * FROM tomi_voice_members WHERE room_id=? AND state='active'",[r.id])).rows;
    for(const m of all)await remove(db,r,m);
    await db.query("UPDATE tomi_voice_rooms SET state='closed',needs_delete=1,revision=revision+1 WHERE id=?",[r.id]);
  }
  async function snapshot(db,r,current,details=true){
    const members=(await db.query("SELECT * FROM tomi_voice_members WHERE room_id=? AND state='active' ORDER BY joined_at,user_id",[r.id])).rows;
    const me=members.find(m=>m.user_id===current.id),manage=me&&['owner','moderator'].includes(me.role);
    const result={id:r.id,title:r.title,ownerId:r.owner_id,capacity:Number(r.capacity),seatCount:Number(r.seat_count),
      state:r.state,revision:Number(r.revision),createdAt:r.created_at,emptySince:r.empty_since,memberCount:members.length,
      myRole:me?.role??null,canControl:!!me&&me.session_hash===current.tokenHash,
      moderationPending:(await db.query('SELECT 1 FROM tomi_voice_jobs WHERE room_id=? LIMIT 1',[r.id])).rows.length>0};
    const users=details?await usersByIds(members.map(m=>m.user_id),current.id,db):null;
    if(details)result.members=members.map(m=>({user:users.get(m.user_id),
      identity:m.identity,role:m.role,seat:m.seat===null?null:Number(m.seat),micAllowed:Number(m.mic_allowed)===1,
      requestedAt:manage||m.user_id===current.id?m.requested_at:null}));
    return result;
  }
  // Serialize each SFU operation with the same room row used by moderation.
  // A stale grant can therefore never overtake a later removal or demotion.
  async function flush(roomId){
    if(!provider||flushing||stopped)return;flushing=true;
    try{
      const jobs=(await database.query('SELECT identity,room_id FROM tomi_voice_jobs'+(roomId?' WHERE room_id=?':'')+' ORDER BY room_id,identity LIMIT '+(roomId?'1':'10'),roomId?[roomId]:[])).rows;
      for(const j of jobs){
        if(stopped)break;
        try{await database.transaction(async db=>{
          const r=await lock(db,j.room_id),live=(await db.query('SELECT * FROM tomi_voice_jobs WHERE identity=?',[j.identity])).rows[0];
          if(!live)return;
          if(Number(live.publish)<0||r.state==='closed')await provider.remove(r,j.identity);
          else await provider.permissions(r,j.identity,Number(live.publish)===1);
          await db.query('DELETE FROM tomi_voice_jobs WHERE identity=? AND version=?',[live.identity,live.version]);
        });}catch{/* Keep the durable job. Do not report enforcement as completed. */}
      }
      const closed=(await database.query('SELECT id FROM tomi_voice_rooms WHERE needs_delete=1'+(roomId?' AND id=?':'')+' LIMIT 1',roomId?[roomId]:[])).rows;
      for(const c of closed)try{await database.transaction(async db=>{
        const r=await lock(db,c.id);if(!r.needs_delete)return;
        await provider.close(r);
        // DeleteRoom alone is not a token revocation. Retain every identity's
        // removal job and keep closing the SFU room until all are acknowledged.
        if(!(await db.query('SELECT 1 FROM tomi_voice_jobs WHERE room_id=? LIMIT 1',[r.id])).rows.length)
          await db.query('UPDATE tomi_voice_rooms SET needs_delete=0 WHERE id=?',[r.id]);
      });}catch{}
    }finally{flushing=false;}
  }
  async function sweep(){
    if(sweeping||stopped)return;sweeping=true;
    try{
      const list=(await database.query(`SELECT r.id FROM tomi_voice_rooms r WHERE r.state='open' AND (
        (r.empty_since IS NOT NULL AND r.empty_since<=?) OR EXISTS (
          SELECT 1 FROM tomi_voice_members m WHERE m.room_id=r.id AND m.state='active' AND (
            m.last_seen<? OR NOT EXISTS(SELECT 1 FROM tomi_sessions s JOIN tomi_users u ON u.id=s.user_id AND u.auth_version=s.auth_version WHERE s.token_hash=m.session_hash AND s.expires_at>?)
            OR EXISTS(SELECT 1 FROM tomi_user_blocks b JOIN tomi_voice_members v ON v.user_id=b.blocked_id AND v.room_id=r.id AND v.state='active' WHERE b.blocker_id=m.user_id)
          ))) ORDER BY r.created_at LIMIT 200`,[stamp(-600000),stamp(-45000),stamp()])).rows;
      for(const item of list){
        if(stopped)break;
        await database.transaction(async db=>{
          const r=await lock(db,item.id);
          const members=(await db.query("SELECT * FROM tomi_voice_members WHERE room_id=? AND state='active'",[r.id])).rows;
          for(const m of members){
            const valid=(await db.query(`SELECT 1 FROM tomi_sessions s JOIN tomi_users u ON u.id=s.user_id AND u.auth_version=s.auth_version
              WHERE s.token_hash=? AND s.expires_at>?`,[m.session_hash,stamp()])).rows.length;
            const blocked=(await db.query(`SELECT 1 FROM tomi_user_blocks b JOIN tomi_voice_members v ON v.user_id=b.blocked_id
              AND v.room_id=? AND v.state='active' WHERE b.blocker_id=?`,[r.id,m.user_id])).rows.length;
            if(!valid||m.last_seen<stamp(-45000)||blocked)await remove(db,r,m);
          }
          await empty(db,r);
          const fresh=(await db.query('SELECT empty_since FROM tomi_voice_rooms WHERE id=?',[r.id])).rows[0];
          if(fresh.empty_since&&fresh.empty_since<=stamp(-600000))await closeRoom(db,r);
        });
      }
      await flush();
      await database.query("DELETE FROM tomi_voice_rooms WHERE state='closed' AND needs_delete=0 AND created_at<?",[stamp(-7*86400000)]);
    }finally{sweeping=false;}
  }
  async function invalidateSession(hash){
    const list=(await database.query("SELECT room_id FROM tomi_voice_members WHERE session_hash=? AND state='active'",[hash])).rows;
    for(const item of list)await database.transaction(async db=>{
      const r=await lock(db,item.room_id),m=(await db.query("SELECT * FROM tomi_voice_members WHERE room_id=? AND session_hash=? AND state='active'",[r.id,hash])).rows[0];
      if(m)await remove(db,r,m);
    });await flush();
  }
  async function handle(request,response,url,current){
    const path=url.pathname,method=request.method;
    if(!path.startsWith('/v1/rooms'))return false;
    if(path==='/v1/rooms/settings'&&method==='GET'){
      respond(response,200,{configured:!!provider,maxMembers:30,maxSeats:8,emptyTimeoutSeconds:600,foregroundOnly:true});return true;
    }
    if(path==='/v1/rooms'&&method==='GET'){
      const before=url.searchParams.get('before');if(before&&!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\|[a-f0-9-]{36}$/.test(before))fail(400,'VALIDATION','صفحة الغرف غير صحيحة.');
      const values=[current.id,current.id];let page='';
      if(before){const [time,key]=before.split('|');if(!uuid(key))fail(400,'VALIDATION','صفحة الغرف غير صحيحة.');page=' AND (r.created_at<? OR (r.created_at=? AND r.id<?))';values.push(time,time,key);}
      const rows=(await database.query(`SELECT r.* FROM tomi_voice_rooms r WHERE r.state='open' AND
        NOT EXISTS(SELECT 1 FROM tomi_user_blocks b WHERE (b.blocker_id=? AND b.blocked_id=r.owner_id) OR (b.blocked_id=? AND b.blocker_id=r.owner_id))${page}
        ORDER BY r.created_at DESC,r.id DESC LIMIT 21`,values)).rows;
      const own=(await database.query("SELECT id FROM tomi_voice_rooms WHERE owner_id=? AND state='open'",[current.id])).rows[0];
      respond(response,200,{configured:!!provider,rooms:await Promise.all(rows.slice(0,20).map(r=>snapshot(database,r,current,false))),
        ownedRoomId:own?.id??null,nextBefore:rows.length>20?rows[19].created_at+'|'+rows[19].id:null});return true;
    }
    if(path==='/v1/rooms'&&method==='POST'){
      if(!provider)fail(503,'ROOMS_DISABLED','الغرف الصوتية تنتظر تفعيل الخدمة.');
      await limit('room-create:'+current.id,5,3600000);const d=await readJson(request);fields(d,['requestId','title','capacity','seatCount']);
      const title=typeof d.title==='string'?d.title.trim().normalize('NFC'):'';
      if(!uuid(d.requestId)||[...title].length<2||[...title].length>60||/[\p{Cc}\p{Cf}]/u.test(title)||
        !Number.isInteger(d.capacity)||d.capacity<2||d.capacity>30||!Number.isInteger(d.seatCount)||d.seatCount<2||d.seatCount>8||d.seatCount>d.capacity)
        fail(400,'VALIDATION','اسم الغرفة 2–60 حرف، الأعضاء 2–30 والمقاعد 2–8.');
      const r=await database.transaction(async db=>{
        await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING id',[current.id]);
        const old=(await db.query('SELECT * FROM tomi_voice_rooms WHERE id=?',[d.requestId])).rows[0];
        if(old){if(old.owner_id!==current.id||old.title!==title||Number(old.capacity)!==d.capacity||Number(old.seat_count)!==d.seatCount)fail(409,'REQUEST_CHANGED','طلب إنشاء الغرفة تغيّر.');return old;}
        if((await db.query("SELECT 1 FROM tomi_voice_rooms WHERE owner_id=? AND state='open'",[current.id])).rows.length)fail(409,'ROOM_OWNED','عندك غرفة مفتوحة؛ افتحها من قائمة الغرف.');
        await db.query('INSERT INTO tomi_voice_rooms(id,title,owner_id,capacity,seat_count,created_at,empty_since) VALUES(?,?,?,?,?,?,?)',[d.requestId,title,current.id,d.capacity,d.seatCount,stamp(),stamp()]);
        return lock(db,d.requestId);
      });respond(response,201,{room:await snapshot(database,r,current)});return true;
    }
    const match=/^\/v1\/rooms\/([a-f0-9-]{36})(?:\/(join|leave|heartbeat|request-mic|cancel-request|take-seat|leave-seat|moderate|close))?$/.exec(path);
    if(!match)return false;const [,roomId,action]=match;if(!uuid(roomId))fail(400,'VALIDATION','معرّف الغرفة غير صحيح.');
    if(!action&&method==='GET'){
      const room=await database.transaction(async db=>snapshot(db,await lock(db,roomId),current));respond(response,200,{room});return true;
    }
    if(method!=='POST')return false;
    await limit('room-action:'+current.id,60);const d=await readJson(request);
    let connection;
    const r=await database.transaction(async db=>{
      // Match call-start's user-before-room lock order for atomic exclusivity.
      if(action==='join')await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING id',[current.id]);
      const r=await lock(db,roomId);
      if(action==='leave'){
        fields(d,['identity']);const m=await member(db,r,current,false);
        if(m&&m.identity===d.identity)await remove(db,r,m);return lock(db,r.id);
      }
      if(r.state!=='open')fail(410,'ROOM_CLOSED','انغلقت الغرفة.');
      if(action==='join'){
        fields(d,[]);
        if(!(await db.query('SELECT 1 FROM tomi_sessions WHERE token_hash=? AND user_id=? AND expires_at>?',[current.tokenHash,current.id,stamp()])).rows.length)fail(401,'UNAUTHORIZED','انتهت جلسة الدخول.');
        if(!provider)fail(503,'ROOMS_DISABLED','الغرف الصوتية غير مفعلة.');
        const existing=await member(db,r,current,false);
        const previous=(await db.query('SELECT * FROM tomi_voice_members WHERE room_id=? AND user_id=?',[r.id,current.id])).rows[0];
        if(previous?.state==='kicked')fail(403,'ROOM_KICKED','أُزيل حسابك من هذه الغرفة.');
        const presence=(await db.query('SELECT room_id FROM tomi_voice_presence WHERE user_id=?',[current.id])).rows[0];
        if(presence&&presence.room_id!==r.id)fail(409,'ROOM_BUSY','غادر غرفتك الحالية أولًا.');
        if((await db.query('SELECT 1 FROM tomi_active_calls WHERE user_id=?',[current.id])).rows.length)fail(409,'CALL_BUSY','أنه المكالمة الخاصة قبل دخول الغرفة.');
        const blocked=(await db.query(`SELECT 1 FROM tomi_user_blocks b WHERE
          (b.blocker_id=? AND (b.blocked_id=? OR b.blocked_id IN(SELECT user_id FROM tomi_voice_members WHERE room_id=? AND state='active'))) OR
          (b.blocked_id=? AND (b.blocker_id=? OR b.blocker_id IN(SELECT user_id FROM tomi_voice_members WHERE room_id=? AND state='active')))`,[current.id,r.owner_id,r.id,current.id,r.owner_id,r.id])).rows.length;
        if(blocked)fail(403,'ROOM_BLOCKED','الانضمام لهذه الغرفة غير متاح بسبب الحظر.');
        const total=Number((await db.query("SELECT COUNT(*) n FROM tomi_voice_members WHERE room_id=? AND state='active'",[r.id])).rows[0].n);
        if(!existing&&total>=Number(r.capacity))fail(409,'ROOM_FULL','الغرفة ممتلئة.');
        // Room setup is idempotent; no permanent key is ever included in grants.
        try{await provider.ensure(r);}catch{fail(503,'ROOM_AUDIO_UNAVAILABLE','تعذّر تجهيز صوت الغرفة؛ جرّب لاحقًا.');}
        let m=existing;
        if(!m){
          const owner=r.owner_id===current.id;
          const ownerSeat=owner?(await db.query("SELECT seat FROM tomi_voice_members WHERE room_id=? AND state='active' AND seat=0",[r.id])).rows.length===0:false;
          const role=owner?'owner':previous?.role==='moderator'?'moderator':'member';
          m={room_id:r.id,user_id:current.id,identity:randomUUID(),session_hash:current.tokenHash,role,seat:ownerSeat?0:null,mic_allowed:ownerSeat?1:0};
          await db.query(`INSERT INTO tomi_voice_members(room_id,user_id,identity,session_hash,role,seat,mic_allowed,joined_at,last_seen)
            VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(room_id,user_id) DO UPDATE SET identity=excluded.identity,session_hash=excluded.session_hash,
            role=excluded.role,state='active',seat=excluded.seat,mic_allowed=excluded.mic_allowed,requested_at=NULL,joined_at=excluded.joined_at,last_seen=excluded.last_seen`,
          [r.id,current.id,m.identity,current.tokenHash,role,m.seat,m.mic_allowed,stamp(),stamp()]);
          await db.query('INSERT INTO tomi_voice_presence(user_id,room_id) VALUES(?,?) ON CONFLICT(user_id) DO NOTHING',[current.id,r.id]);
          await db.query('UPDATE tomi_voice_rooms SET empty_since=NULL WHERE id=?',[r.id]);await bump(db,r);
        }else await db.query('UPDATE tomi_voice_members SET last_seen=? WHERE room_id=? AND user_id=?',[stamp(),r.id,current.id]);
        connection=await provider.grant(r,m);
        return lock(db,r.id);
      }
      const me=await member(db,r,current);
      if(action==='heartbeat'){
        fields(d,['identity']);if(d.identity!==me.identity)fail(409,'ROOM_CONNECTION_CHANGED','تغيّر اتصال الغرفة.');
        await db.query('UPDATE tomi_voice_members SET last_seen=? WHERE room_id=? AND user_id=?',[stamp(),r.id,current.id]);
      }else if(action==='request-mic'||action==='cancel-request'){
        fields(d,[]);if(me.seat!==null)fail(409,'ROOM_ALREADY_SEATED','أنت على مقعد مايك.');
        await db.query('UPDATE tomi_voice_members SET requested_at=? WHERE room_id=? AND user_id=?',[action==='request-mic'?(me.requested_at??stamp()):null,r.id,current.id]);await bump(db,r);
      }else if(action==='take-seat'){
        fields(d,[]);if(!['owner','moderator'].includes(me.role))fail(403,'ROOM_FORBIDDEN','اطلب المايك من إدارة الغرفة.');
        if(me.seat===null){
          const used=(await db.query("SELECT seat FROM tomi_voice_members WHERE room_id=? AND state='active' AND seat IS NOT NULL",[r.id])).rows.map(v=>Number(v.seat));
          const seat=Array.from({length:Number(r.seat_count)},(_,i)=>i).find(s=>!used.includes(s));
          if(seat===undefined)fail(409,'ROOM_SEAT_FULL','كل مقاعد المايك مشغولة.');
          await db.query('UPDATE tomi_voice_members SET seat=?,mic_allowed=1,requested_at=NULL WHERE room_id=? AND user_id=?',[seat,r.id,current.id]);
          await job(db,r,me,1);await bump(db,r);
        }
      }else if(action==='leave-seat'){
        fields(d,[]);await db.query('UPDATE tomi_voice_members SET seat=NULL,mic_allowed=0,requested_at=NULL WHERE room_id=? AND user_id=?',[r.id,current.id]);
        await job(db,r,me,0);await bump(db,r);
      }else if(action==='close'){
        fields(d,[]);if(me.role!=='owner')fail(403,'ROOM_FORBIDDEN','إغلاق الغرفة للمالك فقط.');await closeRoom(db,r);
      }else if(action==='moderate'){
        fields(d,['targetId','operation','seat']);if(!uuid(d.targetId)||!['approve','reject','lower','mute','allow-mic','promote','demote','kick'].includes(d.operation))fail(400,'VALIDATION','إجراء الإدارة غير صحيح.');
        if(!['owner','moderator'].includes(me.role))fail(403,'ROOM_FORBIDDEN','هذا الإجراء للإدارة فقط.');
        const target=(await db.query("SELECT * FROM tomi_voice_members WHERE room_id=? AND user_id=? AND state='active'",[r.id,d.targetId])).rows[0];
        if(!target)fail(404,'ROOM_MEMBER_NOT_FOUND','العضو غادر الغرفة.');
        if(target.role==='owner'||target.user_id===current.id||me.role==='moderator'&&target.role!=='member')fail(403,'ROOM_FORBIDDEN','ما تگدر تغيّر صلاحيات هذا العضو.');
        if(['promote','demote'].includes(d.operation)){
          if(me.role!=='owner')fail(403,'ROOM_FORBIDDEN','تعيين المشرفين للمالك فقط.');
          await db.query('UPDATE tomi_voice_members SET role=? WHERE room_id=? AND user_id=?',[d.operation==='promote'?'moderator':'member',r.id,target.user_id]);
        }else if(d.operation==='kick')await remove(db,r,target,'kicked');
        else if(d.operation==='approve'){
          if(!target.requested_at||target.seat!==null)fail(409,'ROOM_NO_REQUEST','لا يوجد طلب مايك لهذا العضو.');
          const seats=(await db.query("SELECT seat FROM tomi_voice_members WHERE room_id=? AND state='active' AND seat IS NOT NULL",[r.id])).rows.map(v=>Number(v.seat));
          const seat=d.seat??Array.from({length:Number(r.seat_count)},(_,i)=>i).find(s=>!seats.includes(s));
          if(!Number.isInteger(seat)||seat<0||seat>=Number(r.seat_count)||seats.includes(seat))fail(409,'ROOM_SEAT_FULL','مقعد المايك غير متاح.');
          await db.query('UPDATE tomi_voice_members SET seat=?,mic_allowed=1,requested_at=NULL WHERE room_id=? AND user_id=?',[seat,r.id,target.user_id]);await job(db,r,target,1);
        }else if(d.operation==='reject')await db.query('UPDATE tomi_voice_members SET requested_at=NULL WHERE room_id=? AND user_id=?',[r.id,target.user_id]);
        else{
          if(target.seat===null)fail(409,'ROOM_NO_SEAT','العضو مستمع.');
          const allowed=d.operation==='allow-mic';
          await db.query('UPDATE tomi_voice_members SET seat=?,mic_allowed=? WHERE room_id=? AND user_id=?',[d.operation==='lower'?null:target.seat,allowed?1:0,r.id,target.user_id]);
          await job(db,r,target,allowed?1:0);
        }
        await bump(db,r);
      }else fail(404,'NOT_FOUND','المسار غير موجود.');
      return lock(db,r.id);
    });
    if(action!=='heartbeat'&&action!=='join')await flush(r.id);
    const room=await database.transaction(async db=>snapshot(db,await lock(db,r.id),current));
    respond(response,200,{room,...(connection?{connection}:{})});return true;
  }
  const timer=autoSweep?setInterval(()=>void sweep().catch(()=>console.error('Voice room cleanup deferred')),5000):null;timer?.unref();
  return {handle,sweep,flush,invalidateSession,close(){stopped=true;if(timer)clearInterval(timer);}};
}
