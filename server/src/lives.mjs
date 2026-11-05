import {randomUUID} from 'node:crypto';
import {ApiError} from './security.mjs';
const fail=(s,c,t)=>{throw new ApiError(s,c,t);},uuid=/^[a-f0-9-]{36}$/;
const fields=(d,keys)=>{if(Object.keys(d).some(k=>!keys.includes(k)))fail(400,'VALIDATION','طلب غير صحيح.');};
export function createLives({database,provider,readJson,respond,limit,usersByIds,clock=Date.now,autoTick=true,emit=()=>{}}){
 let closed=false,working=false;
 async function changed(ids){const slots=ids.map(()=>'?').join(',');const users=(await database.query(`SELECT user_id FROM tomi_lives WHERE id IN (${slots}) UNION SELECT user_id FROM tomi_live_watchers WHERE live_id IN (${slots}) AND seen_at>?`,[...ids,...ids,clock()-45000])).rows.map(r=>r.user_id);emit(users,{type:'live.changed',liveIds:ids});}
 const room=id=>'tomi-live-'+id;
 async function revokePair(db,b){for(const id of [b.a_id,b.b_id]){const l=await live(db,id);await db.query('INSERT INTO tomi_live_revoke(room,identity,created_at) VALUES(?,?,?) ON CONFLICT(room,identity) DO NOTHING',[room(b.a_id),'live-'+l.user_id+'-'+l.session_hash.slice(0,16),clock()]);}await db.query('INSERT INTO tomi_live_cleanup(room,created_at) VALUES(?,?) ON CONFLICT(room) DO NOTHING',[room(b.a_id),clock()]);}
 async function finish(db,id){const own=await live(db,id);await db.query('INSERT INTO tomi_live_revoke(room,identity,created_at) VALUES(?,?,?) ON CONFLICT(room,identity) DO NOTHING',[room(id),'live-'+own.user_id+'-'+own.session_hash.slice(0,16),clock()]);for(const b of (await db.query("SELECT * FROM tomi_live_battles WHERE (a_id=? OR b_id=?) AND state='playing'",[id,id])).rows)await revokePair(db,b);await db.query("UPDATE tomi_lives SET status='ended' WHERE id=?",[id]);await db.query("UPDATE tomi_live_battles SET state='cancelled' WHERE (a_id=? OR b_id=?) AND state IN('invited','playing')",[id,id]);await db.query('INSERT INTO tomi_live_cleanup(room,created_at) VALUES(?,?) ON CONFLICT(room) DO NOTHING',[room(id),clock()]);}
 let sweepWork;
 const sweep=()=>sweepWork??=(async()=>{await runSweep();})().finally(()=>sweepWork=null);
 async function runSweep(){if(closed||working)return;working=true;try{
  for(const b of (await database.query("SELECT * FROM tomi_live_battles WHERE state='playing' AND ends_at<=?",[clock()])).rows)await revokePair(database,b);
  await database.query("UPDATE tomi_live_battles SET state='finished' WHERE state='playing' AND ends_at<=?",[clock()]);
  await database.query("UPDATE tomi_live_battles SET state='expired' WHERE state='invited' AND ends_at<=?",[clock()]);
  const stale=(await database.query("SELECT l.id FROM tomi_lives l WHERE l.status='live' AND (l.seen_at<? OR NOT EXISTS(SELECT 1 FROM tomi_sessions s JOIN tomi_users u ON u.id=s.user_id AND s.auth_version=u.auth_version WHERE s.token_hash=l.session_hash AND s.user_id=l.user_id AND s.expires_at>?) OR EXISTS(SELECT 1 FROM tomi_account_restrictions r WHERE r.user_id=l.user_id AND r.suspended=1))",[clock()-45000,new Date(clock()).toISOString()])).rows;
  for(const r of stale)await database.transaction(db=>finish(db,r.id));
  await database.query('DELETE FROM tomi_live_watchers WHERE seen_at<?',[clock()-120000]);
  if(provider?.remove)for(const r of (await database.query('SELECT room,identity FROM tomi_live_revoke ORDER BY created_at LIMIT 20')).rows){try{await provider.remove(r.room,r.identity);await database.query('DELETE FROM tomi_live_revoke WHERE room=? AND identity=?',[r.room,r.identity]);}catch{}}
  if(provider)for(const r of (await database.query('SELECT room FROM tomi_live_cleanup ORDER BY created_at LIMIT 10')).rows){try{await provider.close(r.room);await database.query('DELETE FROM tomi_live_cleanup WHERE room=?',[r.room]);}catch{}}
 }finally{working=false;}}
 const timer=autoTick?setInterval(()=>sweep().catch(()=>{}),5000):null;timer?.unref();
 async function live(db,id){const r=(await db.query('SELECT * FROM tomi_lives WHERE id=?',[id])).rows[0];if(!r)fail(404,'LIVE_MISSING','البث غير موجود.');return r;}
 async function battle(db,id){const r=(await db.query('SELECT * FROM tomi_live_battles WHERE id=?',[id])).rows[0];if(!r)fail(404,'BATTLE_MISSING','الجولة غير موجودة.');return r;}
 async function view(r,viewer){const users=await usersByIds([r.user_id],viewer),b=(await database.query("SELECT * FROM tomi_live_battles WHERE (a_id=? OR b_id=?) AND state IN('invited','playing','finished') ORDER BY created_at DESC,id DESC LIMIT 1",[r.id,r.id])).rows[0];const hosts=b?(await database.query('SELECT id,user_id FROM tomi_lives WHERE id IN (?,?)',[b.a_id,b.b_id])).rows:[];return{id:r.id,title:r.title,status:r.status,isMine:r.user_id===viewer,host:users.get(r.user_id),battle:b?{id:b.id,aId:b.a_id,bId:b.b_id,aUserId:hosts.find(x=>x.id===b.a_id)?.user_id,bUserId:hosts.find(x=>x.id===b.b_id)?.user_id,mode:'combined',state:b.state,endsAt:Number(b.ends_at),aScore:Number(b.a_score),bScore:Number(b.b_score),winner:b.state==='finished'?(Number(b.a_score)===Number(b.b_score)?'tie':Number(b.a_score)>Number(b.b_score)?b.a_id:b.b_id):null}:null};}
 return {sweep,close(){closed=true;if(timer)clearInterval(timer);},async handle(req,res,url,c){if(!url.pathname.startsWith('/v1/lives'))return false;await sweep();const path=url.pathname,method=req.method;
  if(path==='/v1/lives'&&method==='GET'){const rows=(await database.query("SELECT l.* FROM tomi_lives l WHERE l.status='live' AND NOT EXISTS(SELECT 1 FROM tomi_user_blocks b WHERE (b.blocker_id=? AND b.blocked_id=l.user_id) OR (b.blocker_id=l.user_id AND b.blocked_id=?)) ORDER BY l.created_at DESC LIMIT 40",[c.id,c.id])).rows;respond(res,200,{configured:!!provider,serverNow:clock(),lives:await Promise.all(rows.map(r=>view(r,c.id))),payments:{configured:false,reason:'merchant_not_configured'}});return true;}
  if(!provider)fail(503,'LIVE_DISABLED','خدمة البث غير متاحة حاليًا؛ تواصل مع إدارة التطبيق.');
  if(path==='/v1/lives'&&method==='POST'){
   await limit('live-start:'+c.id,5);const d=await readJson(req);fields(d,['title','requestId']);if(!uuid.test(d.requestId)||typeof d.title!=='string'||!d.title.trim()||[...d.title.trim()].length>80)fail(400,'VALIDATION','اكتب عنوانًا للبث حتى80 حرفًا.');
   const r=await database.transaction(async db=>{await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=?',[c.id]);const old=(await db.query('SELECT * FROM tomi_lives WHERE user_id=? AND request_id=?',[c.id,d.requestId])).rows[0];if(old){if(old.title!==d.title.trim())fail(409,'REQUEST_CHANGED','تغيّر طلب البث.');return old;}
    if((await db.query("SELECT 1 FROM tomi_lives WHERE user_id=? AND status='live'",[c.id])).rows.length)fail(409,'LIVE_ACTIVE','عندك بث قائم.');
    if((await db.query('SELECT 1 FROM tomi_active_calls WHERE user_id=? UNION SELECT 1 FROM tomi_voice_presence WHERE user_id=?',[c.id,c.id])).rows.length)fail(409,'AUDIO_BUSY','أنه المكالمة أو غادر الروم قبل البث.');
    const id=randomUUID(),now=clock();await db.query('INSERT INTO tomi_lives(id,user_id,session_hash,title,status,request_id,created_at,seen_at) VALUES(?,?,?,?,?,?,?,?)',[id,c.id,c.tokenHash,d.title.trim(),'live',d.requestId,now,now]);return live(db,id);});respond(res,201,{live:await view(r,c.id)});return true;
  }
  let m=/^\/v1\/lives\/([a-f0-9-]{36})\/(join|heartbeat|end|invite)$/.exec(path);
  if(m&&method==='POST'){
   const r=await live(database,m[1]);if(r.status!=='live')fail(409,'LIVE_ENDED','انتهى البث.');
   const owner=r.user_id===c.id;if(owner&&r.session_hash!==c.tokenHash)fail(409,'OTHER_DEVICE','البث من جهاز آخر.');
   if((await database.query('SELECT 1 FROM tomi_user_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)',[c.id,r.user_id,r.user_id,c.id])).rows.length)fail(403,'LIVE_BLOCKED','البث غير متاح.');
   const d=await readJson(req);
   if(m[2]==='join'){
    fields(d,[]);await limit('live-join:'+c.id,30);
    const result=await database.transaction(async db=>{
     let b=(await db.query("SELECT * FROM tomi_live_battles WHERE (a_id=? OR b_id=?) AND state='playing' AND ends_at>?",[r.id,r.id,clock()])).rows[0];
     for(const id of [...new Set(b?[b.a_id,b.b_id]:[r.id])].sort())await db.query('UPDATE tomi_lives SET seen_at=seen_at WHERE id=?',[id]);
     const fresh=await live(db,r.id);if(fresh.status!=='live')fail(409,'LIVE_ENDED','انتهى البث.');if(fresh.user_id===c.id&&fresh.session_hash!==c.tokenHash)fail(409,'OTHER_DEVICE','البث من جهاز آخر.');
     b=(await db.query("SELECT * FROM tomi_live_battles WHERE (a_id=? OR b_id=?) AND state='playing' AND ends_at>?",[r.id,r.id,clock()])).rows[0];
     let publish=fresh.user_id===c.id,primary=r.id;
     if(b){primary=b.a_id;const other=await live(db,b.a_id===r.id?b.b_id:b.a_id);if(other.status!=='live')fail(409,'LIVE_ENDED','انتهت الجولة.');if((await db.query('SELECT 1 FROM tomi_user_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)',[c.id,other.user_id,other.user_id,c.id])).rows.length)fail(403,'LIVE_BLOCKED','الجولة غير متاحة.');publish=publish||other.user_id===c.id&&other.session_hash===c.tokenHash;}
     if(publish&&(await db.query('SELECT 1 FROM tomi_active_calls WHERE user_id=? UNION SELECT 1 FROM tomi_voice_presence WHERE user_id=?',[c.id,c.id])).rows.length)fail(409,'AUDIO_BUSY','غادر الروم أو المكالمة أولًا.');
     await db.query('INSERT INTO tomi_live_watchers(user_id,live_id,session_hash,seen_at) VALUES(?,?,?,?) ON CONFLICT(user_id,live_id) DO UPDATE SET session_hash=excluded.session_hash,seen_at=excluded.seen_at',[c.id,r.id,c.tokenHash,clock()]);
     return {connection:await provider.grant(room(primary),'live-'+c.id+'-'+c.tokenHash.slice(0,16),publish)};
    });respond(res,200,{live:await view(r,c.id),...result});return true;
   }
   if(!owner&&m[2]==='heartbeat'){fields(d,[]);await database.query('UPDATE tomi_live_watchers SET seen_at=? WHERE user_id=? AND live_id=? AND session_hash=?',[clock(),c.id,r.id,c.tokenHash]);respond(res,200,{live:await view(r,c.id),serverNow:clock()});return true;}
   if(!owner)fail(403,'FORBIDDEN','لصاحب البث فقط.');
   if(m[2]==='heartbeat'){fields(d,[]);await database.query('UPDATE tomi_lives SET seen_at=? WHERE id=?',[clock(),r.id]);respond(res,200,{live:await view(r,c.id),serverNow:clock()});return true;}
   if(m[2]==='end'){fields(d,[]);await database.transaction(db=>finish(db,r.id));await sweep();await changed([r.id]);respond(res,200,{ok:true});return true;}
   fields(d,['targetId','mode']);if(!uuid.test(d.targetId)||!['taps','gifts','combined'].includes(d.mode))fail(400,'VALIDATION','اختار بثًا وطريقة احتساب الجولة.');
   const b=await database.transaction(async db=>{const pair=[r.id,d.targetId].sort();for(const id of pair)await db.query('UPDATE tomi_lives SET seen_at=seen_at WHERE id=?',[id]);const other=await live(db,d.targetId);if(other.status!=='live'||other.user_id===c.id)fail(409,'LIVE_UNAVAILABLE','البث غير متاح.');
    if((await db.query('SELECT 1 FROM tomi_user_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)',[c.id,other.user_id,other.user_id,c.id])).rows.length)fail(403,'LIVE_BLOCKED','البث غير متاح.');
    if((await db.query("SELECT 1 FROM tomi_live_battles WHERE (a_id IN (?,?) OR b_id IN (?,?)) AND state IN('invited','playing')",[...pair,...pair])).rows.length)fail(409,'BATTLE_BUSY','أحد البثين عنده دعوة أو جولة.');
    const id=randomUUID();await db.query('INSERT INTO tomi_live_battles(id,a_id,b_id,mode,state,created_at,ends_at) VALUES(?,?,?,?,?,?,?)',[id,r.id,other.id,'combined','invited',clock(),clock()+30000]);return battle(db,id);});await changed([b.a_id,b.b_id]);respond(res,201,{battleId:b.id});return true;
  }
  m=/^\/v1\/lives\/battles\/([a-f0-9-]{36})\/(accept|decline|support)$/.exec(path);if(m&&method==='POST'){
   const d=await readJson(req);await limit('live-action:'+c.id,300);
   const result=await database.transaction(async db=>{
    await db.query('UPDATE tomi_live_battles SET a_score=a_score WHERE id=?',[m[1]]);const b=await battle(db,m[1]),a=await live(db,b.a_id),z=await live(db,b.b_id);
    if(m[2]!=='support'){fields(d,[]);if(z.user_id!==c.id||z.session_hash!==c.tokenHash)fail(403,'FORBIDDEN','الدعوة للطرف الآخر فقط.');if(b.state!=='invited'||Number(b.ends_at)<=clock()||a.status!=='live'||z.status!=='live')fail(409,'BATTLE_EXPIRED','انتهت الدعوة.');await db.query('UPDATE tomi_live_battles SET state=?,ends_at=? WHERE id=?',[m[2]==='accept'?'playing':'declined',clock()+300000,b.id]);return {ok:true};}
    fields(d,['targetId','requestId','gift','count']);if(d.count!==undefined&&(!Number.isInteger(d.count)||d.count<1||d.count>10||d.gift!==undefined))fail(400,'VALIDATION','عدد التكبيس غير صحيح.');if(!uuid.test(d.requestId)||![a.id,z.id].includes(d.targetId))fail(400,'VALIDATION','دعم غير صحيح.');
    const old=(await db.query('SELECT * FROM tomi_live_actions WHERE user_id=? AND request_id=?',[c.id,d.requestId])).rows[0];const points=d.gift===undefined?(d.count??1):d.gift;
    if(old){if(old.battle_id!==b.id||old.target_id!==d.targetId||Number(old.points)!==points)fail(409,'REQUEST_CHANGED','تغيّر الدعم.');return {ok:true,repeated:true};}
    if(b.state!=='playing'||Number(b.ends_at)<=clock()||a.status!=='live'||z.status!=='live')fail(409,'BATTLE_ENDED','انتهت الجولة.');if([a.user_id,z.user_id].includes(c.id))fail(403,'SELF_SUPPORT','المشاهدون يدعمون طرفي الجولة.');
    for(const host of [a,z])if((await db.query('SELECT 1 FROM tomi_user_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)',[c.id,host.user_id,host.user_id,c.id])).rows.length)fail(403,'LIVE_BLOCKED','الجولة غير متاحة.');
    if(d.gift!==undefined){
     if(![100,500,1000].includes(points))fail(400,'VALIDATION','اختار هدية.');
     const changed=await db.query('UPDATE tomi_room_wallets SET coins=coins-? WHERE user_id=? AND coins>=?',[points,c.id,points]);if(changed.changes!==1)fail(409,'INSUFFICIENT_COINS','الرصيد التجريبي غير كافٍ.');
    }
    await db.query('INSERT INTO tomi_live_actions(user_id,request_id,battle_id,target_id,kind,points,created_at) VALUES(?,?,?,?,?,?,?)',[c.id,d.requestId,b.id,d.targetId,d.gift===undefined?'tap':'gift',points,clock()]);
    await db.query(`UPDATE tomi_live_battles SET ${d.targetId===a.id?'a_score':'b_score'}=${d.targetId===a.id?'a_score':'b_score'}+? WHERE id=?`,[points,b.id]);return{ok:true};
   });const updated=await battle(database,m[1]);await changed([updated.a_id,updated.b_id]);respond(res,200,result);return true;
  }
  return false;
 }};
}
