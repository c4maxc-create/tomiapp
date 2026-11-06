import {requireContact} from './contact_preferences.mjs';
import {decorateRoomUsers,roomCosmetics} from './room_policy.mjs';
import {giftProgress} from './identity_catalog.mjs';
import {randomUUID} from 'node:crypto';
import {ApiError,hashPassword,verifyPassword} from './security.mjs';
import {uploadWithDigest} from './media_intents.mjs';
import {giftCatalog,welcomeCoins,dailyCoins} from './room_catalog.mjs';
const now=(delta=0)=>new Date(Date.now()+delta).toISOString();
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const uuid=v=>typeof v==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(v);
const fields=(d,allowed)=>{if(Object.keys(d).some(k=>!allowed.includes(k)))fail(400,'VALIDATION','طلب الغرفة غير صحيح.');};
const text=(s,max,min=0)=>{
 if(typeof s!=='string')fail(400,'VALIDATION','النص غير صحيح.');
 const v=s.trim().normalize('NFC');
 if([...v].length<min||[...v].length>max||/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(v))fail(400,'VALIDATION','طول النص أو محتواه غير صحيح.');
 return v;
};
export function createRoomFeatures({database,storage,usersByIds,job,bump,remove}){
 async function options(db,r){
  await db.query('INSERT INTO tomi_room_options(room_id) VALUES(?) ON CONFLICT(room_id) DO NOTHING',[r.id]);
  return (await db.query('SELECT * FROM tomi_room_options WHERE room_id=?',[r.id])).rows[0];
 }
 async function wallet(db,user){
  await db.query('INSERT INTO tomi_room_wallets(user_id,coins,next_claim) VALUES(?,?,?) ON CONFLICT(user_id) DO NOTHING',[user,welcomeCoins,now(86400000)]);
  const w=(await db.query('SELECT * FROM tomi_room_wallets WHERE user_id=?',[user])).rows[0];
  return {coins:Number(w.coins),nextClaim:w.next_claim,dailyCoins,trial:true};
 }
 async function audit(db,r,current,action,detail=''){
  await db.query('INSERT INTO tomi_room_audit(room_id,id,actor_id,action,detail,created_at) VALUES(?,?,?,?,?,?)',[r.id,randomUUID(),current.id,action,detail,now()]);
 }
 async function emit(db,r,current,kind,body,{requestId=null,imageId=null,giftId=null}={}){
  const seq=Number((await db.query('UPDATE tomi_room_options SET next_event=next_event+1 WHERE room_id=? RETURNING next_event',[r.id])).rows[0].next_event);
  await db.query('INSERT INTO tomi_room_events(room_id,sequence,actor_id,request_id,kind,body,image_upload_id,gift_id,created_at) VALUES(?,?,?,?,?,?,?,?,?)',
   [r.id,seq,current.id,requestId,kind,body,imageId,giftId,now()]);
  return seq;
 }
 async function picture(db,id){
  if(!id)return null;const u=(await db.query('SELECT * FROM tomi_image_uploads WHERE id=?',[id])).rows[0];
  return u&&storage?{url:storage.avatarUrl?.(u.object_key)??storage.readUrl(u.object_key),width:Number(u.width),height:Number(u.height)}:null;
 }
 async function history(db,r,current,before=null){
  const rows=(await db.query(`SELECT e.*,g.id AS resolved_gift_id,g.gift_id AS catalog_id,g.quantity,g.total,g.recipient_id,x.style_id
   FROM tomi_room_events e LEFT JOIN tomi_support_events se ON se.room_id=e.room_id AND se.sequence=e.sequence LEFT JOIN tomi_room_all_gifts g ON g.id=COALESCE(e.gift_id,se.gift_id) LEFT JOIN tomi_room_entry_effects x ON x.room_id=e.room_id AND x.sequence=e.sequence
   WHERE e.room_id=? AND e.sequence>COALESCE((SELECT after_sequence FROM tomi_room_chat_cursors WHERE room_id=e.room_id AND user_id=?),0) ${before===null?'':'AND e.sequence<?'} ORDER BY e.sequence DESC LIMIT 41`,[r.id,current.id,...(before===null?[]:[before])])).rows;
  const more=rows.length>40;rows.splice(40);rows.reverse();
  const users=await usersByIds([...new Set(rows.flatMap(e=>[e.actor_id,e.recipient_id].filter(Boolean)))],current.id,db);
  await decorateRoomUsers(db,users);
  const items=await Promise.all(rows.map(async e=>({sequence:Number(e.sequence),kind:e.kind,text:e.body,createdAt:e.created_at,
   actor:users.get(e.actor_id),effect:e.style_id?{kind:'entrance',styleId:e.style_id}:e.resolved_gift_id?{kind:'gift',styleId:giftCatalog.find(g=>g.id===e.catalog_id)?.effect??'pulse'}:null,image:await picture(db,e.image_upload_id),requestId:e.actor_id===current.id?e.request_id:null,
   gift:e.resolved_gift_id?{id:e.resolved_gift_id,giftId:e.catalog_id,quantity:Number(e.quantity),total:Number(e.total),recipient:users.get(e.recipient_id)}:null})));
  return {events:items,nextBefore:more?Number(rows[0].sequence):null};
 }
 async function snapshot(db,r,current,me,details){
  // Snapshot reads do not create rows: listing rooms stays read-only.
  const o=(await db.query('SELECT * FROM tomi_room_options WHERE room_id=?',[r.id])).rows[0]??{};
  const result={announcement:o.announcement??'',category:o.category??'الأصدقاء',mode:o.mode??'عادي',
   background:o.background??'ocean',theme:o.theme??'gold',picture:o.picture??'headphones',
   companionEnabled:o.companion_enabled===undefined||Number(o.companion_enabled)===1,
   chatDisabled:Number(o.chat_disabled)===1,imagesDisabled:Number(o.images_disabled)===1,
   highQuality:o.high_quality===undefined||Number(o.high_quality)===1,passwordRequired:!!o.password_hash,
   image:await picture(db,o.image_upload_id),hasLevels:r.tier==='advanced'};
  if(details){
   result.seats=(await db.query('SELECT seat,locked,muted FROM tomi_room_seats WHERE room_id=?',[r.id])).rows.map(v=>({seat:Number(v.seat),locked:!!v.locked,muted:!!v.muted}));
   if(me&&me.session_hash===current.tokenHash){
    const page=await history(db,r,current);result.events=page.events;result.eventsBefore=page.nextBefore;
    const inv=(await db.query('SELECT seat,expires_at FROM tomi_room_invites WHERE room_id=? AND user_id=? AND expires_at>?',[r.id,current.id,now()])).rows[0];
    result.invitation=inv?{seat:Number(inv.seat),expiresAt:inv.expires_at}:null;
   }
  }
  return result;
 }
 async function readAdministration(db,r,current){
  const rows=(await db.query("SELECT user_id,role,state FROM tomi_voice_members WHERE room_id=? AND (role='moderator' OR state='kicked') ORDER BY joined_at DESC LIMIT 100",[r.id])).rows;
  const entries=(await db.query('SELECT * FROM tomi_room_audit WHERE room_id=? ORDER BY created_at DESC,id DESC LIMIT 50',[r.id])).rows;
  const leaders=(await db.query('SELECT sender_id,SUM(total) AS points FROM tomi_room_all_gifts WHERE room_id=? GROUP BY sender_id ORDER BY SUM(total) DESC,sender_id LIMIT 100',[r.id])).rows;
  const users=await usersByIds([...new Set([...rows.map(v=>v.user_id),...entries.map(v=>v.actor_id),...leaders.map(v=>v.sender_id)])],current.id,db);
  return {members:rows.map(v=>({user:users.get(v.user_id),role:v.role,state:v.state})),
   audit:entries.map(v=>({id:v.id,actor:users.get(v.actor_id),action:v.action,detail:v.detail,createdAt:v.created_at})),
   leaders:leaders.map(v=>({user:users.get(v.sender_id),points:Number(v.points)}))};
 }
 async function verifyJoin(db,r,current,d,existing){
  fields(d,['password']);const o=await options(db,r);
  if(o.password_hash&&r.owner_id!==current.id&&!existing){
   if(typeof d.password!=='string'||d.password.length>64||!(await verifyPassword(d.password,o.password_hash)))
    fail(403,'ROOM_PASSWORD','اكتب كلمة مرور الغرفة الصحيحة.');
  }
 }
 async function validateSeat(db,r,seat,{empty=true}={}){
  const o=await options(db,r);
  if(!Number.isInteger(seat)||seat===-1||seat< -2||seat>=Number(r.seat_count)||seat===-2&&!Number(o.companion_enabled))
   fail(403,'ROOM_RESERVED_SEAT','هذا المقعد محجوز أو غير متاح.');
  const s=(await db.query('SELECT * FROM tomi_room_seats WHERE room_id=? AND seat=?',[r.id,seat])).rows[0];
  if(s?.locked)fail(409,'ROOM_SEAT_LOCKED','مقعد المايك مقفول.');
  if(empty&&(await db.query("SELECT 1 FROM tomi_voice_members WHERE room_id=? AND seat=? AND state='active'",[r.id,seat])).rows.length)
   fail(409,'ROOM_SEAT_FULL','مقعد المايك مشغول.');
  return {micAllowed:!s?.muted};
 }
 async function freeSeat(db,r){
  for(let i=0;i<Number(r.seat_count);i++)try{await validateSeat(db,r,i);return i;}catch(e){if(!['ROOM_SEAT_LOCKED','ROOM_SEAT_FULL'].includes(e.code))throw e;}
  fail(409,'ROOM_SEAT_FULL','كل مقاعد المايك مشغولة أو مقفولة.');
 }
 async function prepare(action,d,current){
  const prepared={};
  if(action==='settings'&&Object.hasOwn(d,'password')){
   if(typeof d.password!=='string'||(d.password!==''&&([...d.password].length<4||[...d.password].length>64)))fail(400,'VALIDATION','كلمة مرور الغرفة من4 إلى64 حرفًا أو فارغة لإلغائها.');
   prepared.passwordHash=d.password===''?null:await hashPassword(d.password);
  }
  if(['message','settings'].includes(action)&&d.imageUploadId){
   if(!uuid(d.imageUploadId))fail(400,'VALIDATION','الصورة غير صحيحة.');
   // Replay of a committed send must not try to verify its already-attached upload.
   const replay=action==='message'&&uuid(d.requestId)?(await database.query('SELECT 1 FROM tomi_room_events WHERE actor_id=? AND request_id=?',[current.id,d.requestId])).rows.length:0;
   if(!replay){
    if(!storage)fail(503,'IMAGES_DISABLED','رفع الصور غير متاح.');
    const u=(await database.query('SELECT * FROM tomi_image_uploads WHERE id=? AND user_id=?',[d.imageUploadId,current.id])).rows[0];
    if(!u||u.state!=='pending'||u.expires_at<=now()||!u.object_key.startsWith('tomi/posts/'+current.id+'/'))fail(400,'UPLOAD_INVALID','الصورة انتهت أو استُخدمت.');
    prepared.image=await storage.verify(await uploadWithDigest(database,u,d.attachmentSha256));
   }
  }
  return prepared;
 }
 async function attach(db,current,id,dimensions){
  if(!dimensions)fail(409,'UPLOAD_INVALID','الصورة استُخدمت؛ اختَرها مرة ثانية.');
  const q=await db.query("UPDATE tomi_image_uploads SET state='attached',width=?,height=? WHERE id=? AND user_id=? AND state='pending' AND expires_at>?",[dimensions.width,dimensions.height,id,current.id,now()]);
  if(q.changes!==1)fail(409,'UPLOAD_INVALID','الصورة استُخدمت أو انتهت.');
 }
 async function action(db,r,current,me,name,d,p){
  const o=await options(db,r),manage=['owner','moderator'].includes(me.role);
  if(name==='gift'){
   fields(d,['requestId','recipientId','recipientIds','audience','giftId','quantity']);
   const gift=giftCatalog.find(g=>g.id===d.giftId),audience=d.audience??'person';
   if(!uuid(d.requestId)||!['person','all','mics','viewers'].includes(audience)||audience==='person'&&!uuid(d.recipientId)||!gift||!Number.isInteger(d.quantity)||d.quantity<1||d.quantity>99)fail(400,'VALIDATION','اختَر المستلمين والهدية والكمية1–99.');
   if(d.recipientIds!==undefined&&(!Array.isArray(d.recipientIds)||d.recipientIds.length>30||d.recipientIds.some(x=>!uuid(x))||new Set(d.recipientIds).size!==d.recipientIds.length))fail(400,'VALIDATION','قائمة المستلمين غير صحيحة.');
   const fingerprint=JSON.stringify([audience,audience==='person'?d.recipientId:null,gift.id,d.quantity,audience==='person'?null:d.recipientIds?.slice().sort()??null]);
   const old=(await db.query('SELECT * FROM tomi_room_support_batches WHERE sender_id=? AND request_id=?',[current.id,d.requestId])).rows[0];
   if(old){if(old.room_id!==r.id||old.fingerprint!==fingerprint)fail(409,'REQUEST_CHANGED','محتوى إرسال الهدية تغيّر.');return {wallet:await wallet(db,current.id),receiptId:old.id,total:Number(old.total),recipients:JSON.parse(old.recipients)};}
   const legacy=(await db.query('SELECT * FROM tomi_room_gifts WHERE sender_id=? AND request_id=?',[current.id,d.requestId])).rows[0];
   if(legacy){if(legacy.room_id!==r.id||audience!=='person'||legacy.recipient_id!==d.recipientId||legacy.gift_id!==gift.id||Number(legacy.quantity)!==d.quantity)fail(409,'REQUEST_CHANGED','طلب الإرسال تغيّر.');return {wallet:await wallet(db,current.id),receiptId:legacy.id};}
   if((await db.query('SELECT 1 FROM tomi_room_events WHERE room_id=? AND actor_id=? AND request_id=?',[r.id,current.id,d.requestId])).rows.length)fail(409,'REQUEST_CHANGED','معرّف الإرسال مستخدم.');
   const targets=(await db.query("SELECT user_id,seat FROM tomi_voice_members WHERE room_id=? AND state='active' ORDER BY user_id",[r.id])).rows.filter(m=>audience==='person'?m.user_id===d.recipientId:audience==='mics'?m.seat!==null:audience==='viewers'?m.seat===null:true);
   if(audience!=='person'&&d.recipientIds!==undefined&&JSON.stringify(targets.map(x=>x.user_id).sort())!==JSON.stringify(d.recipientIds.slice().sort()))fail(409,'ROOM_RECIPIENTS_CHANGED','تغيّر الحاضرون؛ راجع المستلمين والسعر ثم أرسل من جديد.');
   if(!targets.length)fail(409,'ROOM_RECIPIENT_LEFT','لا يوجد مستلمون في الاختيار الحالي.');
   for(const target of targets)if((await db.query('SELECT 1 FROM tomi_user_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)',[current.id,target.user_id,target.user_id,current.id])).rows.length)fail(403,'ROOM_BLOCKED','أحد المستلمين محظور؛ اختَر مستلمين آخرين.');
   const unitTotal=gift.price*d.quantity,total=unitTotal*targets.length;await wallet(db,current.id);
   if((await db.query('UPDATE tomi_room_wallets SET coins=coins-? WHERE user_id=? AND coins>=?',[total,current.id,total])).changes!==1)fail(409,'ROOM_COINS_LOW','رصيد الكوينز غير كافٍ لدعم كل المستلمين.');
   const id=randomUUID(),ids=targets.map(t=>t.user_id);
   await db.query('INSERT INTO tomi_room_support_batches(id,room_id,sender_id,request_id,fingerprint,total,recipients) VALUES(?,?,?,?,?,?,?)',[id,r.id,current.id,d.requestId,fingerprint,total,JSON.stringify(ids)]);
   for(let i=0;i<targets.length;i++){
    const recipient=targets[i].user_id,gid=randomUUID();
    await db.query('INSERT INTO tomi_room_support(id,room_id,sender_id,recipient_id,request_id,gift_id,quantity,unit_price,total,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)',[gid,r.id,current.id,recipient,i===0?d.requestId:randomUUID(),gift.id,d.quantity,gift.price,unitTotal,now()]);
    await giftProgress(db,current.id,recipient,unitTotal);
    const seq=await emit(db,r,current,'gift',gift.name,{requestId:i===0?d.requestId:null});
    await db.query('INSERT INTO tomi_support_events(room_id,sequence,gift_id) VALUES(?,?,?)',[r.id,seq,gid]);
   }
   await bump(db,r);return {wallet:await wallet(db,current.id),receiptId:id,total,recipients:ids};
  }
  if(name==='message'){
   fields(d,['requestId','text','imageUploadId','attachmentSha256']);const body=text(d.text??'',500),imageId=d.imageUploadId??null;
   if(d.attachmentSha256!==undefined&&(!imageId||typeof d.attachmentSha256!=='string'||!/^[a-f0-9]{64}$/.test(d.attachmentSha256)))fail(400,'VALIDATION','بصمة الصورة غير صحيحة.');
   if(!uuid(d.requestId)||!body&&!imageId||imageId&&!uuid(imageId))fail(400,'VALIDATION','اكتب رسالة أو اختَر صورة.');
   const old=(await db.query('SELECT body,image_upload_id,kind FROM tomi_room_events WHERE room_id=? AND actor_id=? AND request_id=?',[r.id,current.id,d.requestId])).rows[0];
   if(old){const oldSha=old.image_upload_id?(await db.query('SELECT sha256 FROM tomi_upload_digests WHERE upload_id=?',[old.image_upload_id])).rows[0]?.sha256:null;if(old.kind!=='message'||old.body!==body||(d.attachmentSha256?oldSha!==d.attachmentSha256:(old.image_upload_id??null)!==imageId))fail(409,'REQUEST_CHANGED','محتوى الرسالة تغيّر.');return {};}
   if(o.chat_disabled&&!manage)fail(403,'ROOM_CHAT_DISABLED','الدردشة مقفلة من إدارة الغرفة.');
   if(imageId){if(o.images_disabled)fail(403,'ROOM_IMAGES_DISABLED','إرسال الصور مقفل.');await attach(db,current,imageId,p.image);}
   await emit(db,r,current,'message',body,{requestId:d.requestId,imageId});await bump(db,r);return {};
  }
  if(!manage&&['settings','seat-control','invite','administration'].includes(name))fail(403,'ROOM_FORBIDDEN','هذا الإجراء للإدارة فقط.');
  if(name==='settings'){
   if(me.role!=='owner')fail(403,'ROOM_FORBIDDEN','إعدادات الغرفة للمالك فقط.');
   const strings={announcement:['announcement',300,0],title:['title',60,2]};
   const enums={category:['category',['الأصدقاء','الموسيقى','الألعاب','عيد ميلاد','المكالمات']],mode:['mode',['عادي','تعارف','احتفال']],
    background:['background',['ocean','dusk','forest','midnight']],theme:['theme',['gold','rose','ice']],picture:['picture',['headphones','moon','crown','game','music','owner']]};
   const bools={companionEnabled:'companion_enabled',chatDisabled:'chat_disabled',imagesDisabled:'images_disabled',highQuality:'high_quality'};
   fields(d,[...Object.keys(strings),...Object.keys(enums),...Object.keys(bools),'password','imageUploadId']);
   for(const [k,v]of Object.entries(d)){
    if(k==='title'){if(typeof v!=='string'||/[\p{Cc}\p{Cf}]/u.test(v))fail(400,'VALIDATION','اسم الغرفة غير صحيح.');await db.query('UPDATE tomi_voice_rooms SET title=? WHERE id=?',[text(v,60,2),r.id]);continue;}
    if(k in strings)await db.query('UPDATE tomi_room_options SET '+strings[k][0]+'=? WHERE room_id=?',[text(v,strings[k][1],strings[k][2]),r.id]);
    else if(k in enums){if(!enums[k][1].includes(v))fail(400,'VALIDATION','اختيار الإعداد غير صحيح.');await db.query('UPDATE tomi_room_options SET '+enums[k][0]+'=? WHERE room_id=?',[v,r.id]);}
    else if(k in bools){if(typeof v!=='boolean')fail(400,'VALIDATION','قيمة الإعداد غير صحيحة.');await db.query('UPDATE tomi_room_options SET '+bools[k]+'=? WHERE room_id=?',[v?1:0,r.id]);}
   }
   if(Object.hasOwn(d,'password'))await db.query('UPDATE tomi_room_options SET password_hash=? WHERE room_id=?',[p.passwordHash,r.id]);
   if(Object.hasOwn(d,'imageUploadId')){
    if(d.imageUploadId!==null){if(!uuid(d.imageUploadId))fail(400,'VALIDATION','الصورة غير صحيحة.');await attach(db,current,d.imageUploadId,p.image);}
    await db.query('UPDATE tomi_room_options SET image_upload_id=? WHERE room_id=?',[d.imageUploadId,r.id]);
    if(o.image_upload_id&&o.image_upload_id!==d.imageUploadId)await db.query("UPDATE tomi_image_uploads SET state='deleting',expires_at=? WHERE id=?",[now(1200000),o.image_upload_id]);
   }
   if(d.companionEnabled===false){
    const target=(await db.query("SELECT * FROM tomi_voice_members WHERE room_id=? AND seat=-2 AND state='active'",[r.id])).rows[0];
    if(target){await db.query('UPDATE tomi_voice_members SET seat=NULL,mic_allowed=0 WHERE room_id=? AND user_id=?',[r.id,target.user_id]);await job(db,r,target,0);}
    await db.query('DELETE FROM tomi_room_invites WHERE room_id=? AND seat=-2',[r.id]);
   }
   await audit(db,r,current,'settings',Object.keys(d).join('، '));await bump(db,r);return {};
  }
  if(name==='seat-control'){
   fields(d,['seat','operation']);if(!Number.isInteger(d.seat)||d.seat===-1||d.seat< -2||d.seat>=Number(r.seat_count)||!['lock','unlock','mute','allow'].includes(d.operation))fail(403,'ROOM_RESERVED_SEAT','مقعد المالك محجوز دائمًا؛ اختَر مقعدًا آخر.');
   const occupied=(await db.query("SELECT * FROM tomi_voice_members WHERE room_id=? AND seat=? AND state='active'",[r.id,d.seat])).rows[0];
   if(me.role==='moderator'&&occupied?.role==='moderator'&&occupied.user_id!==current.id)fail(403,'ROOM_FORBIDDEN','ما تگدر تتحكم بمقعد مشرف آخر.');
   await db.query('INSERT INTO tomi_room_seats(room_id,seat) VALUES(?,?) ON CONFLICT(room_id,seat) DO NOTHING',[r.id,d.seat]);
   const key=['lock','unlock'].includes(d.operation)?'locked':'muted',value=['lock','mute'].includes(d.operation)?1:0;
   await db.query('UPDATE tomi_room_seats SET '+key+'=? WHERE room_id=? AND seat=?',[value,r.id,d.seat]);
   if(key==='muted'){
    const target=(await db.query("SELECT * FROM tomi_voice_members WHERE room_id=? AND seat=? AND state='active'",[r.id,d.seat])).rows[0];
    if(target){await db.query('UPDATE tomi_voice_members SET mic_allowed=? WHERE room_id=? AND user_id=?',[value?0:1,r.id,target.user_id]);await job(db,r,target,value?0:1);}
   }
   if(d.operation==='lock')await db.query('DELETE FROM tomi_room_invites WHERE room_id=? AND seat=?',[r.id,d.seat]);
   await audit(db,r,current,d.operation,'مقعد '+(d.seat===-2?'مميز':d.seat+1));await bump(db,r);return {};
  }
  if(name==='invite'){
   fields(d,['targetId','seat']);if(!uuid(d.targetId)||d.targetId===r.owner_id)fail(403,'ROOM_RESERVED_SEAT','مقعد المالك ثابت.');
   await requireContact(db,d.targetId,current.id,'roomInvites');
   await validateSeat(db,r,d.seat);
   const target=(await db.query("SELECT * FROM tomi_voice_members WHERE room_id=? AND user_id=? AND state='active'",[r.id,d.targetId])).rows[0];
   if(!target||target.seat!==null)fail(409,'ROOM_NO_LISTENER','اختَر عضوًا من المستمعين.');
   await db.query('INSERT INTO tomi_room_invites(room_id,user_id,seat,invited_by,expires_at) VALUES(?,?,?,?,?) ON CONFLICT(room_id,user_id) DO UPDATE SET seat=excluded.seat,invited_by=excluded.invited_by,expires_at=excluded.expires_at',[r.id,d.targetId,d.seat,current.id,now(90000)]);
   await audit(db,r,current,'invite',d.targetId);await bump(db,r);return {};
  }
  if(name==='answer-invite'){
   fields(d,['accept']);if(typeof d.accept!=='boolean')fail(400,'VALIDATION','رد الدعوة غير صحيح.');
   const inv=(await db.query('SELECT * FROM tomi_room_invites WHERE room_id=? AND user_id=? AND expires_at>?',[r.id,current.id,now()])).rows[0];
   if(!inv)fail(409,'ROOM_INVITE_EXPIRED','انتهت الدعوة.');
   if(d.accept){
    if(me.role==='owner'||me.seat!==null)fail(409,'ROOM_ALREADY_SEATED','أنت على مقعد.');
    const s=await validateSeat(db,r,Number(inv.seat));
    await db.query('UPDATE tomi_voice_members SET seat=?,mic_allowed=?,requested_at=NULL WHERE room_id=? AND user_id=?',[inv.seat,s.micAllowed?1:0,r.id,current.id]);
    await job(db,r,me,s.micAllowed?1:0);
   }
   await db.query('DELETE FROM tomi_room_invites WHERE room_id=? AND user_id=?',[r.id,current.id]);await bump(db,r);return {};
  }
  if(name==='administration'){
   fields(d,['targetId','operation']);if(!uuid(d.targetId)||!['unban','revoke-mod'].includes(d.operation)||d.targetId===r.owner_id||me.role!=='owner')fail(403,'ROOM_FORBIDDEN','هذا الإجراء للمالك فقط.');
   const t=(await db.query('SELECT * FROM tomi_voice_members WHERE room_id=? AND user_id=?',[r.id,d.targetId])).rows[0];
   if(!t)fail(404,'ROOM_MEMBER_NOT_FOUND','العضو غير موجود.');
   if(d.operation==='unban'&&t.state==='kicked')await db.query("UPDATE tomi_voice_members SET state='left' WHERE room_id=? AND user_id=?",[r.id,d.targetId]);
   if(d.operation==='revoke-mod'&&t.role==='moderator')await db.query("UPDATE tomi_voice_members SET role='member' WHERE room_id=? AND user_id=?",[r.id,d.targetId]);
   await audit(db,r,current,d.operation,d.targetId);await bump(db,r);return {};
  }
  return null;
 }
 async function entry(db,r,current){
  const purchased=(await roomCosmetics(db,current.id)).find(x=>x.kind==='entrance'&&Number(x.equipped));
  const style=purchased?.style_id??'glow';
  const name=(await db.query('SELECT display_name FROM tomi_users WHERE id=?',[current.id])).rows[0].display_name;
  const seq=await emit(db,r,current,'system',name+' انضم إلى السالفة');
  await db.query('INSERT INTO tomi_room_entry_effects(room_id,sequence,style_id) VALUES(?,?,?)',[r.id,seq,style]);
  await db.query('INSERT INTO tomi_room_entry_cooldowns(room_id,user_id,last_effect_at) VALUES(?,?,?) ON CONFLICT(room_id,user_id) DO UPDATE SET last_effect_at=excluded.last_effect_at',[r.id,current.id,now()]);await bump(db,r);
 }
 async function receipt(db,roomId,current,nonce){
  const gift=(await db.query('SELECT id FROM tomi_room_support_batches WHERE room_id=? AND sender_id=? AND request_id=?',[roomId,current.id,nonce])).rows[0];
  const legacy=gift?null:(await db.query('SELECT id FROM tomi_room_gifts WHERE room_id=? AND sender_id=? AND request_id=?',[roomId,current.id,nonce])).rows[0];
  if(gift||legacy)return {roomId,requestId:nonce,kind:'gift',receiptId:(gift??legacy).id,wallet:await wallet(db,current.id)};
  const e=(await db.query("SELECT sequence,kind FROM tomi_room_events WHERE room_id=? AND actor_id=? AND request_id=? AND kind='message'",[roomId,current.id,nonce])).rows[0];
  if(e)return {roomId,requestId:nonce,kind:e.kind,sequence:Number(e.sequence)};
  fail(404,'REQUEST_NOT_FOUND','لم يُسجّل هذا الإرسال بعد.');
 }
 return {walletFor:wallet,options,snapshot,history,receipt,entry,verifyJoin,validateSeat,freeSeat,prepare,action,audit,readAdministration,
  catalog:{gifts:giftCatalog,hasLevels:true,welcomeCoins,dailyCoins,trial:true},
  async wallet(current){return database.transaction(db=>wallet(db,current.id));},
  async claim(current){return database.transaction(async db=>{
   await wallet(db,current.id);
   const q=await db.query('UPDATE tomi_room_wallets SET coins=coins+?,next_claim=? WHERE user_id=? AND next_claim<=?',[dailyCoins,now(86400000),current.id,now()]);
   return {wallet:await wallet(db,current.id),claimed:q.changes===1};
  })}};
}
