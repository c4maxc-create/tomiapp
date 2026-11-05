import {policy,policyFields,createPolicy,afterDeparture,advancedPrice,roomLifetime,roomShop,roomCosmetics,buyCosmetic,equipCosmetic,decorateRoomUsers} from './room_policy.mjs';
import {createRoomSocial} from './room_social.mjs';
import {giftRanking} from './ranking.mjs';
import {randomUUID} from 'node:crypto';
import {ApiError} from './security.mjs';
import {createRoomFeatures} from './room_features.mjs';

const stamp=(delta=0)=>new Date(Date.now()+delta).toISOString();
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const uuid=v=>typeof v==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(v);
const fields=(d,keys)=>{if(Object.keys(d).some(k=>!keys.includes(k)))fail(400,'VALIDATION','طلب الغرفة غير صحيح.');};

export function createVoiceRooms({database,provider,readJson,respond,limit,usersByIds,storage,autoSweep=true,emit=()=>{}}) {
  let stopped=false,sweeping=false,flushing=false;
  async function announce(roomId,extra=[]){
    const ids=(await database.query("SELECT user_id FROM tomi_voice_members WHERE room_id=? AND state='active'",[roomId])).rows.map(x=>x.user_id);
    emit([...new Set([...ids,...extra].filter(Boolean))],{type:'voice_room.changed',roomId});
  }
  const social=createRoomSocial({database,readJson,respond,limit});
  async function lock(db,id){
    await db.query('UPDATE tomi_voice_rooms SET revision=revision WHERE id=? RETURNING id',[id]);
    const r=(await db.query('SELECT * FROM tomi_voice_rooms WHERE id=?',[id])).rows[0];
    if(!r)fail(404,'ROOM_NOT_FOUND','الغرفة غير موجودة.');
    const rules=await policy(db,r);r.tier=rules.tier;
    if(r.state==='open'&&r.tier==='advanced'&&Date.parse(rules.last_owner_visit)<=Date.now()-roomLifetime){await closeRoom(db,r);r.state='closed';}
    // Lazy additive upgrade of occupied 0.7 rooms. Negative owner seat cannot
    // collide with any old seat; preserve the attendance identity and SFU link.
    const owner=(await db.query("SELECT * FROM tomi_voice_members WHERE room_id=? AND user_id=? AND state='active' AND (seat IS NULL OR seat<>-1)",[r.id,r.owner_id])).rows[0];
    if(owner){
      await db.query('UPDATE tomi_voice_members SET seat=-1,mic_allowed=1,requested_at=NULL WHERE room_id=? AND user_id=?',[r.id,r.owner_id]);
      if(!Number(owner.mic_allowed))await job(db,r,owner,1);
      await bump(db,r);r.revision=Number(r.revision)+1;
    }
    return r;
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
    await db.query('DELETE FROM tomi_room_invites WHERE room_id=? AND user_id=?',[r.id,m.user_id]);
    await job(db,r,m,-1);await bump(db,r);await empty(db,r);await afterDeparture(db,r,m,job);
  }
  async function closeRoom(db,r){
    r.state='closed';
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
    Object.assign(result,await policyFields(db,r));
    result.features=await features.snapshot(db,{...r,tier:result.tier},current,me,details);
    result.preferences=await social.preferences(db,r.id,current.id);
    const users=details?await usersByIds([...new Set([r.owner_id,...members.map(m=>m.user_id)])],current.id,db):null;
    if(details){await decorateRoomUsers(db,users);result.owner=users.get(r.owner_id);}
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
      const jobs=(await database.query('SELECT identity,room_id FROM tomi_voice_jobs'+(roomId?' WHERE room_id=?':'')+' ORDER BY room_id,identity LIMIT '+(roomId?'30':'30'),roomId?[roomId]:[])).rows;
      for(const j of jobs){
        if(stopped)break;
        try{await database.transaction(async db=>{
          const r=await lock(db,j.room_id),live=(await db.query('SELECT * FROM tomi_voice_jobs WHERE identity=?',[j.identity])).rows[0];
          if(!live)return;
          if(Number(live.publish)<0||r.state==='closed')await provider.remove(r,j.identity);
          else await provider.permissions(r,j.identity,Number(live.publish)===1);
          await db.query('DELETE FROM tomi_voice_jobs WHERE identity=? AND version=?',[live.identity,live.version]);
        });}catch{/* Keep the durable job; stop at the first SFU outage. */break;}
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
      const list=(await database.query(`SELECT r.id FROM tomi_voice_rooms r WHERE r.state='open' AND EXISTS (
          SELECT 1 FROM tomi_voice_members m WHERE m.room_id=r.id AND m.state='active' AND (
            m.last_seen<? OR NOT EXISTS(SELECT 1 FROM tomi_sessions s JOIN tomi_users u ON u.id=s.user_id AND u.auth_version=s.auth_version WHERE s.token_hash=m.session_hash AND s.expires_at>?)
            OR EXISTS(SELECT 1 FROM tomi_user_blocks b JOIN tomi_voice_members v ON v.user_id=b.blocked_id AND v.room_id=r.id AND v.state='active' WHERE b.blocker_id=m.user_id)
          )) ORDER BY r.created_at LIMIT 200`,[stamp(-45000),stamp()])).rows;
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
          // Only advanced rooms retain their identity after the final leave.
        });await announce(item.id);
      }
      const expired=(await database.query("SELECT r.id FROM tomi_voice_rooms r JOIN tomi_room_policy p ON p.room_id=r.id WHERE r.state='open' AND ((p.tier='advanced' AND p.last_owner_visit<=?) OR (p.tier='free' AND r.empty_since IS NOT NULL AND r.empty_since<=?)) LIMIT 200",[stamp(-roomLifetime),stamp(-120000)])).rows;
      for(const e of expired)await database.transaction(async db=>{const r=await lock(db,e.id);if(r.state==='open'&&r.tier==='free'&&!(await db.query("SELECT 1 FROM tomi_voice_members WHERE room_id=? AND state='active'",[r.id])).rows.length)await closeRoom(db,r);});
      await flush();
      // Gift ledgers and room history are retained, including closed rooms.
    }finally{sweeping=false;}
  }
  async function invalidateSession(hash){
    const list=(await database.query("SELECT room_id FROM tomi_voice_members WHERE session_hash=? AND state='active'",[hash])).rows;
    for(const item of list)await database.transaction(async db=>{
      const r=await lock(db,item.room_id),m=(await db.query("SELECT * FROM tomi_voice_members WHERE room_id=? AND session_hash=? AND state='active'",[r.id,hash])).rows[0];
      if(m)await remove(db,r,m);
    });for(const item of list)await announce(item.room_id);await flush();
  }
  const features=createRoomFeatures({database,storage,usersByIds,job,bump,remove});
  async function handle(request,response,url,current){
    const path=url.pathname,method=request.method;
    if(!path.startsWith('/v1/rooms'))return false;
    if(await social.handle(request,response,url,current))return true;
    if(path==='/v1/rooms/settings'&&method==='GET'){
      respond(response,200,{configured:!!provider,maxMembers:30,maxSeats:8,specialSeats:2,ownerSeat:-1,emptyTimeoutSeconds:0,persistentRooms:true,advancedPrice,advancedInactivityDays:60,foregroundOnly:false,backgroundAudio:'android_foreground_service'});return true;
    }
    if(path==='/v1/rooms/shop'&&method==='GET'){respond(response,200,{items:roomShop,owned:await roomCosmetics(database,current.id)});return true;}
    if(path==='/v1/rooms/shop'&&method==='POST'){
      await limit('room-shop:'+current.id,20);const d=await readJson(request);
      const data=await database.transaction(db=>buyCosmetic(db,current,d,features.walletFor));const live=(await database.query('SELECT room_id FROM tomi_voice_presence WHERE user_id=?',[current.id])).rows[0];if(live)await announce(live.room_id);respond(response,200,data);return true;
    }
    if(path==='/v1/rooms/shop/equip'&&method==='PUT'){
      await limit('room-equip:'+current.id,30);const d=await readJson(request);
      const data=await database.transaction(db=>equipCosmetic(db,current,d));const live=(await database.query('SELECT room_id FROM tomi_voice_presence WHERE user_id=?',[current.id])).rows[0];if(live)await announce(live.room_id);respond(response,200,data);return true;
    }
    const lookup=/^\/v1\/rooms\/lookup\/([A-Za-z0-9-]{1,40})$/.exec(path);
    if(lookup&&method==='GET'){
      const row=(await database.query("SELECT r.id FROM tomi_voice_rooms r JOIN tomi_room_policy p ON p.room_id=r.id WHERE p.public_id=? AND p.tier='advanced' AND r.state='open'",[lookup[1]])).rows[0];
      if(!row)fail(404,'ROOM_NOT_FOUND','ماكو غرفة متقدمة بهذا المعرّف.');
      const room=await database.transaction(async db=>{const r=await lock(db,row.id);if(r.state!=='open')fail(410,'ROOM_CLOSED','انتهت صلاحية الغرفة.');if((await db.query('SELECT 1 FROM tomi_user_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)',[current.id,r.owner_id,r.owner_id,current.id])).rows.length)fail(403,'ROOM_BLOCKED','الغرفة غير متاحة بسبب الحظر.');return snapshot(db,r,current,false);});
      respond(response,200,{room});return true;
    }
    if(path==='/v1/rooms/gifts' &&method==='GET'){respond(response,200,features.catalog);return true;}
    if(path==='/v1/rooms/wallet'&&method==='GET'){respond(response,200,{wallet:await features.wallet(current)});return true;}
    if(path==='/v1/rooms/wallet/claim'&&method==='POST'){
      await limit('room-claim:'+current.id,10);fields(await readJson(request),[]);
      respond(response,200,await features.claim(current));return true;
    }
    if(path==='/v1/rooms'&&method==='GET'){
      const before=url.searchParams.get('before');if(before&&!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\|[a-f0-9-]{36}$/.test(before))fail(400,'VALIDATION','صفحة الغرف غير صحيحة.');
      const scope=url.searchParams.get('scope')||'all';if(!['all','favorites','following'].includes(scope))fail(400,'VALIDATION','قائمة الغرف غير صحيحة.');
      const values=[current.id,current.id];let page='';
      if(scope!=='all'){page+=' AND EXISTS(SELECT 1 FROM tomi_room_preferences p WHERE p.room_id=r.id AND p.user_id=? AND p.'+(scope==='favorites'?'favorite':'following')+'=1)';values.push(current.id);}
      if(before){const [time,key]=before.split('|');if(!uuid(key))fail(400,'VALIDATION','صفحة الغرف غير صحيحة.');page+=' AND (r.created_at<? OR (r.created_at=? AND r.id<?))';values.push(time,time,key);}
      const rows=(await database.query(`SELECT r.* FROM tomi_voice_rooms r WHERE r.state='open' AND EXISTS(SELECT 1 FROM tomi_room_policy rp WHERE rp.room_id=r.id AND (rp.tier='free' OR rp.last_owner_visit>'${stamp(-roomLifetime)}')) AND
        NOT EXISTS(SELECT 1 FROM tomi_user_blocks b WHERE (b.blocker_id=? AND b.blocked_id=r.owner_id) OR (b.blocked_id=? AND b.blocker_id=r.owner_id))${page}
        ORDER BY r.created_at DESC,r.id DESC LIMIT 21`,values)).rows;
      const own=(await database.query("SELECT r.id FROM tomi_voice_rooms r JOIN tomi_room_policy p ON p.room_id=r.id WHERE r.owner_id=? AND r.state='open' AND (p.tier='free' OR p.last_owner_visit>?)",[current.id,stamp(-roomLifetime)])).rows[0];
      respond(response,200,{configured:!!provider,rooms:await Promise.all(rows.slice(0,20).map(r=>snapshot(database,r,current,false))),
        ownedRoomId:own?.id??null,nextBefore:rows.length>20?rows[19].created_at+'|'+rows[19].id:null});return true;
    }
    if(path==='/v1/rooms'&&method==='POST'){
      if(!provider)fail(503,'ROOMS_DISABLED','الغرف الصوتية تنتظر تفعيل الخدمة.');
      await limit('room-create:'+current.id,5,3600000);const d=await readJson(request);fields(d,['requestId','title','capacity','seatCount','tier','acceptTerms']);
      const tier=d.tier??'free';if(!['free','advanced'].includes(tier))fail(400,'VALIDATION','نوع الغرفة غير صحيح.');
      if(tier==='advanced'&&d.acceptTerms!==true)fail(400,'ROOM_TERMS','وافق على سعر 5799 كوينز والحذف بعد 60 يومًا من عدم دخول المالك قبل الشراء.');
      const title=typeof d.title==='string'?d.title.trim().normalize('NFC'):'';
      if(!uuid(d.requestId)||[...title].length<2||[...title].length>60||/[\p{Cc}\p{Cf}]/u.test(title)||
        !Number.isInteger(d.capacity)||d.capacity<2||d.capacity>30||!Number.isInteger(d.seatCount)||d.seatCount<2||d.seatCount>8||d.seatCount>d.capacity)
        fail(400,'VALIDATION','اسم الغرفة 2–60 حرف، الأعضاء 2–30 والمقاعد 2–8.');
      const r=await database.transaction(async db=>{
        await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING id',[current.id]);
        const old=(await db.query('SELECT * FROM tomi_voice_rooms WHERE id=?',[d.requestId])).rows[0];
        if(old){if((await policy(db,old)).creator_id!==current.id||(await policy(db,old)).tier!==tier||old.title!==title||Number(old.capacity)!==d.capacity||Number(old.seat_count)!==d.seatCount)fail(409,'REQUEST_CHANGED','طلب إنشاء الغرفة تغيّر.');return old;}
        for(const previous of (await db.query("SELECT id FROM tomi_voice_rooms WHERE owner_id=? AND state='open'",[current.id])).rows)await lock(db,previous.id);
        if((await db.query("SELECT 1 FROM tomi_voice_rooms WHERE owner_id=? AND state='open'",[current.id])).rows.length)fail(409,'ROOM_OWNED','عندك غرفة مفتوحة؛ افتحها من قائمة الغرف.');
        await features.walletFor(db,current.id);
        if(tier==='advanced'&&(await db.query('UPDATE tomi_room_wallets SET coins=coins-? WHERE user_id=? AND coins>=?',[advancedPrice,current.id,advancedPrice])).changes!==1)fail(409,'ROOM_COINS_LOW','رصيدك غير كافٍ لشراء الغرفة المتقدمة (5799 كوينز).');
        await db.query('INSERT INTO tomi_voice_rooms(id,title,owner_id,capacity,seat_count,created_at,empty_since) VALUES(?,?,?,?,?,?,?)',[d.requestId,title,current.id,d.capacity,d.seatCount,stamp(),stamp()]);
        await createPolicy(db,{id:d.requestId,owner_id:current.id},tier);
        await db.query('INSERT INTO tomi_user_progress(user_id,rooms_created) VALUES(?,1) ON CONFLICT(user_id) DO UPDATE SET rooms_created=tomi_user_progress.rooms_created+1',[current.id]);
        return lock(db,d.requestId);
      });respond(response,201,{room:await snapshot(database,r,current),wallet:await features.wallet(current)});return true;
    }
    const creation=/^\/v1\/rooms\/purchases\/([a-f0-9-]{36})$/.exec(path);
    if(creation&&method==='GET'){
      const row=(await database.query('SELECT r.* FROM tomi_voice_rooms r JOIN tomi_room_policy p ON p.room_id=r.id WHERE r.id=? AND p.creator_id=?',[creation[1],current.id])).rows[0];
      if(!row)fail(404,'REQUEST_NOT_FOUND','لم يُسجّل إنشاء الغرفة بعد.');respond(response,200,{room:await snapshot(database,row,current),wallet:await features.wallet(current)});return true;
    }
    const receipt=/^\/v1\/rooms\/([a-f0-9-]{36})\/requests\/([a-f0-9-]{36})$/.exec(path);
    if(method==='GET'&&receipt&&uuid(receipt[1])&&uuid(receipt[2])){respond(response,200,await features.receipt(database,receipt[1],current,receipt[2]));return true;}
    const match=/^\/v1\/rooms\/([a-f0-9-]{36})(?:\/(join|leave|heartbeat|request-mic|cancel-request|take-seat|leave-seat|moderate|close|gift|message|settings|seat-control|invite|answer-invite|administration|ranking|events))?$/.exec(path);
    if(!match)return false;const [,roomId,action]=match;if(!uuid(roomId))fail(400,'VALIDATION','معرّف الغرفة غير صحيح.');
    if(!action&&method==='GET'){
      const room=await database.transaction(async db=>snapshot(db,await lock(db,roomId),current));respond(response,200,{room});return true;
    }
    if(method==='GET'&&action==='events'){
      const raw=url.searchParams.get('before'),before=raw===null?null:Number(raw);
      if(raw!==null&&(!/^\d{1,16}$/.test(raw)||!Number.isSafeInteger(before)||before<1))fail(400,'VALIDATION','صفحة الرسائل غير صحيحة.');
      await limit('room-history:'+current.id,60);
      const data=await database.transaction(async db=>{const r=await lock(db,roomId);await member(db,r,current);if(r.state!=='open')fail(410,'ROOM_CLOSED','انغلقت الغرفة.');return features.history(db,r,current,before);});respond(response,200,data);return true;
    }
    if(method==='GET'&&['administration','ranking'].includes(action)){
      const data=await database.transaction(async db=>{
        const r=await lock(db,roomId),m=await member(db,r,current);
        if(action==='administration'&&!['owner','moderator'].includes(m.role))fail(403,'ROOM_FORBIDDEN','هذا الإجراء للإدارة فقط.');
        if(action==='ranking')return giftRanking(db,current.id,usersByIds,{roomId:r.id,period:url.searchParams.get('period')||'all'});
        return features.readAdministration(db,r,current);
      });respond(response,200,data);return true;
    }
    if(method!=='POST')return false;
    await limit('room-action:'+current.id,60);const d=await readJson(request);
    if(action==='join')await limit('room-join:'+current.id,20);
    const prepared=await features.prepare(action,d,current);let connection,extra={};
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
        const currentMember=await member(db,r,current,false);await features.verifyJoin(db,r,current,d,currentMember);
        if(!(await db.query('SELECT 1 FROM tomi_sessions WHERE token_hash=? AND user_id=? AND expires_at>?',[current.tokenHash,current.id,stamp()])).rows.length)fail(401,'UNAUTHORIZED','انتهت جلسة الدخول.');
        if(!provider)fail(503,'ROOMS_DISABLED','الغرف الصوتية غير مفعلة.');
        const existing=await member(db,r,current,false);
        const previous=(await db.query('SELECT * FROM tomi_voice_members WHERE room_id=? AND user_id=?',[r.id,current.id])).rows[0];
        if(previous?.state==='kicked')fail(403,'ROOM_KICKED','أُزيل حسابك من هذه الغرفة.');
        const presence=(await db.query('SELECT room_id FROM tomi_voice_presence WHERE user_id=?',[current.id])).rows[0];
        if(presence&&presence.room_id!==r.id)fail(409,'ROOM_BUSY','غادر غرفتك الحالية أولًا.');
        if((await db.query("SELECT 1 FROM tomi_lives WHERE user_id=? AND status='live'",[current.id])).rows.length)fail(409,'LIVE_BUSY','أنه البث قبل دخول الغرفة.');
        if((await db.query('SELECT 1 FROM tomi_active_calls WHERE user_id=?',[current.id])).rows.length)fail(409,'CALL_BUSY','أنه المكالمة الخاصة قبل دخول الغرفة.');
        const blocked=(await db.query(`SELECT 1 FROM tomi_user_blocks b WHERE
          (b.blocker_id=? AND (b.blocked_id=? OR b.blocked_id IN(SELECT user_id FROM tomi_voice_members WHERE room_id=? AND state='active'))) OR
          (b.blocked_id=? AND (b.blocker_id=? OR b.blocker_id IN(SELECT user_id FROM tomi_voice_members WHERE room_id=? AND state='active')))`,[current.id,r.owner_id,r.id,current.id,r.owner_id,r.id])).rows.length;
        if(blocked)fail(403,'ROOM_BLOCKED','الانضمام لهذه الغرفة غير متاح بسبب الحظر.');
        const total=Number((await db.query("SELECT COUNT(*) n FROM tomi_voice_members WHERE room_id=? AND state='active'",[r.id])).rows[0].n);
        let ownerPresent=(await db.query("SELECT 1 FROM tomi_voice_members WHERE room_id=? AND user_id=? AND state='active'",[r.id,r.owner_id])).rows.length>0;
        if(!existing&&r.tier==='free'&&!ownerPresent){await db.query('UPDATE tomi_voice_rooms SET owner_id=?,revision=revision+1 WHERE id=?',[current.id,r.id]);r.owner_id=current.id;ownerPresent=true;}
        if(!existing&&current.id!==r.owner_id&&total>=Number(r.capacity)-(ownerPresent?0:1))fail(409,'ROOM_FULL','الغرفة ممتلئة؛ مكان المالك محجوز.');
        if(!existing&&current.id===r.owner_id&&total>=Number(r.capacity)){
          // Upgrade of a full legacy room: make the newly reserved owner place.
          const last=(await db.query("SELECT * FROM tomi_voice_members WHERE room_id=? AND user_id<>? AND state='active' ORDER BY joined_at DESC,user_id DESC LIMIT 1",[r.id,r.owner_id])).rows[0];
          if(last)await remove(db,r,last);
        }
        // Room setup is idempotent; no permanent key is ever included in grants.
        try{await provider.ensure(r);}catch{fail(503,'ROOM_AUDIO_UNAVAILABLE','تعذّر تجهيز صوت الغرفة؛ جرّب لاحقًا.');}
        let m=existing;
        if(!m){
          const owner=r.owner_id===current.id;
          const ownerSeat=owner;
          const role=owner?'owner':r.tier==='advanced'&&previous?.role==='moderator'?'moderator':'member';
          m={room_id:r.id,user_id:current.id,identity:randomUUID(),session_hash:current.tokenHash,role,seat:ownerSeat?-1:null,mic_allowed:ownerSeat?1:0};
          await db.query(`INSERT INTO tomi_voice_members(room_id,user_id,identity,session_hash,role,seat,mic_allowed,joined_at,last_seen)
            VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(room_id,user_id) DO UPDATE SET identity=excluded.identity,session_hash=excluded.session_hash,
            role=excluded.role,state='active',seat=excluded.seat,mic_allowed=excluded.mic_allowed,requested_at=NULL,joined_at=excluded.joined_at,last_seen=excluded.last_seen`,
          [r.id,current.id,m.identity,current.tokenHash,role,m.seat,m.mic_allowed,stamp(),stamp()]);
          const cursor=Number((await features.options(db,r)).next_event);
          await db.query('INSERT INTO tomi_room_chat_cursors(room_id,user_id,identity,after_sequence) VALUES(?,?,?,?) ON CONFLICT(room_id,user_id) DO UPDATE SET identity=excluded.identity,after_sequence=excluded.after_sequence',[r.id,current.id,m.identity,cursor]);
          await db.query('INSERT INTO tomi_voice_presence(user_id,room_id) VALUES(?,?) ON CONFLICT(user_id) DO NOTHING',[current.id,r.id]);
          await db.query('UPDATE tomi_voice_rooms SET empty_since=NULL WHERE id=?',[r.id]);await features.entry(db,r,current);await bump(db,r);
        }else await db.query('UPDATE tomi_voice_members SET last_seen=? WHERE room_id=? AND user_id=?',[stamp(),r.id,current.id]);
        if(r.owner_id===current.id)await db.query('UPDATE tomi_room_policy SET last_owner_visit=? WHERE room_id=?',[stamp(),r.id]);
        connection={...await provider.grant(r,m),highQuality:Number((await features.options(db,r)).high_quality)===1};
        return lock(db,r.id);
      }
      const me=await member(db,r,current);
      if(action==='heartbeat'){
        if(r.owner_id===current.id)await db.query('UPDATE tomi_room_policy SET last_owner_visit=? WHERE room_id=?',[stamp(),r.id]);
        fields(d,['identity']);if(d.identity!==me.identity)fail(409,'ROOM_CONNECTION_CHANGED','تغيّر اتصال الغرفة.');
        await db.query('UPDATE tomi_voice_members SET last_seen=? WHERE room_id=? AND user_id=?',[stamp(),r.id,current.id]);
      }else if(action==='request-mic'||action==='cancel-request'){
        fields(d,[]);if(me.seat!==null)fail(409,'ROOM_ALREADY_SEATED','أنت على مقعد مايك.');
        await db.query('UPDATE tomi_voice_members SET requested_at=? WHERE room_id=? AND user_id=?',[action==='request-mic'?(me.requested_at??stamp()):null,r.id,current.id]);await bump(db,r);
      }else if(action==='take-seat'){
        fields(d,['seat']);if(!['owner','moderator'].includes(me.role))fail(403,'ROOM_FORBIDDEN','اطلب المايك من إدارة الغرفة.');
        const seat=me.role==='owner'?-1:(d.seat??(me.seat??await features.freeSeat(db,r)));
        if(me.role==='owner'&&d.seat!==undefined&&d.seat!==-1)fail(403,'ROOM_RESERVED_SEAT','مقعد المالك ثابت.');
        const allowed=me.role==='owner'?true:(await features.validateSeat(db,r,seat,{empty:me.seat!==seat})).micAllowed;
        await db.query('UPDATE tomi_voice_members SET seat=?,mic_allowed=?,requested_at=NULL WHERE room_id=? AND user_id=?',[seat,allowed?1:0,r.id,current.id]);
        await job(db,r,me,allowed?1:0);await bump(db,r);
      }else if(action==='leave-seat'){
        fields(d,[]);await db.query('UPDATE tomi_voice_members SET seat=?,mic_allowed=0,requested_at=NULL WHERE room_id=? AND user_id=?',[me.role==='owner'?-1:null,r.id,current.id]);
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
          if(r.tier!=='advanced')fail(403,'ROOM_NO_MODERATORS','الغرف المجانية لا تحتوي على مشرفين.');
          if(me.role!=='owner')fail(403,'ROOM_FORBIDDEN','تعيين المشرفين للمالك فقط.');
          await db.query('UPDATE tomi_voice_members SET role=? WHERE room_id=? AND user_id=?',[d.operation==='promote'?'moderator':'member',r.id,target.user_id]);
        }else if(d.operation==='kick')await remove(db,r,target,'kicked');
        else if(d.operation==='approve'){
          if(!target.requested_at||target.seat!==null)fail(409,'ROOM_NO_REQUEST','لا يوجد طلب مايك لهذا العضو.');
          const seat=d.seat??await features.freeSeat(db,r),allowed=(await features.validateSeat(db,r,seat)).micAllowed;
          await db.query('UPDATE tomi_voice_members SET seat=?,mic_allowed=?,requested_at=NULL WHERE room_id=? AND user_id=?',[seat,allowed?1:0,r.id,target.user_id]);await job(db,r,target,allowed?1:0);
        }else if(d.operation==='reject')await db.query('UPDATE tomi_voice_members SET requested_at=NULL WHERE room_id=? AND user_id=?',[r.id,target.user_id]);
        else{
          if(target.seat===null)fail(409,'ROOM_NO_SEAT','العضو مستمع.');
          const allowed=d.operation==='allow-mic';
          if(allowed&&!(await features.validateSeat(db,r,Number(target.seat),{empty:false})).micAllowed)fail(409,'ROOM_SEAT_MUTED','ألغِ كتم المقعد أولًا.');
          await db.query('UPDATE tomi_voice_members SET seat=?,mic_allowed=? WHERE room_id=? AND user_id=?',[d.operation==='lower'?null:target.seat,allowed?1:0,r.id,target.user_id]);
          await job(db,r,target,allowed?1:0);
        }
        await features.audit(db,r,current,d.operation,target.user_id);await bump(db,r);
      }else {
        extra=await features.action(db,r,current,me,action,d,prepared);
        if(extra===null)fail(404,'NOT_FOUND','المسار غير موجود.');
      }
      return lock(db,r.id);
    });
    if(action!=='heartbeat')await announce(r.id,[current.id,d.targetId]);
    if(action!=='heartbeat'&&action!=='join')await flush(r.id);
    const room=await database.transaction(async db=>snapshot(db,await lock(db,r.id),current));
    respond(response,200,{room,...extra,...(connection?{connection}:{})});return true;
  }
  const timer=autoSweep?setInterval(()=>void sweep().catch(()=>console.error('Voice room cleanup deferred')),5000):null;timer?.unref();
  return {handle,sweep,flush,invalidateSession,
    async adminClose(db,id){const r=await lock(db,id);if(r.state==='closed')return false;await closeRoom(db,r);return true;},
    async suspendUser(db,userId){
      const list=(await db.query("SELECT id room_id FROM tomi_voice_rooms WHERE owner_id=? AND state='open' UNION SELECT room_id FROM tomi_voice_members WHERE user_id=? AND state='active' ORDER BY room_id",[userId,userId])).rows;
      for(const item of list){const r=await lock(db,item.room_id);if(r.owner_id===userId&&r.state==='open'){await closeRoom(db,r);continue;}const m=(await db.query("SELECT * FROM tomi_voice_members WHERE room_id=? AND user_id=? AND state='active'",[r.id,userId])).rows[0];if(m)await remove(db,r,m);}
    },
    close(){stopped=true;if(timer)clearInterval(timer);}};
}
