import {randomInt,randomUUID} from 'node:crypto';
import {ApiError,digest} from './security.mjs';
import {welcomeCoins} from './room_catalog.mjs';
import {roomShop} from './room_policy.mjs';
export const defaultPrizes=Object.freeze([
 {id:'spark',label:'شرارة',icon:'✨',coins:5,weight:40},
 {id:'moon',label:'هلال',icon:'🌙',coins:10,weight:30},
 {id:'star',label:'نجمة',icon:'⭐',coins:20,weight:20},
 {id:'crown',label:'تاج تومي',icon:'👑',coins:50,weight:10},
]);
const fail=(s,c,m)=>{throw new ApiError(s,c,m);};
const uuid=v=>typeof v==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(v);
const stamp=()=>new Date().toISOString();
export const rouletteDay=(time=Date.now())=>new Date(time+10800000).toISOString().slice(0,10);
export function validatePrizes(items){
 if(!Array.isArray(items)||items.length<2||items.length>8)fail(400,'VALIDATION','اختَر من 2 إلى 8 جوائز.');
 const ids=new Set();
 for(const p of items){
  if(!p||typeof p!=='object'||Object.keys(p).some(k=>!['id','label','icon','coins','weight','kind','styleId','days'].includes(k))||!/^[-a-z0-9]{1,24}$/.test(p.id??'')||ids.has(p.id)||typeof p.label!=='string'||!p.label.trim()||[...p.label].length>32||typeof p.icon!=='string'||!p.icon.trim()||[...p.icon].length>8||!Number.isSafeInteger(p.coins)||p.coins<0||p.coins>10000||!Number.isSafeInteger(p.weight)||p.weight<0||p.weight>10000)fail(400,'VALIDATION','بيانات الجوائز غير صحيحة.');
  const kind=p.kind??'coins';
  if(!['coins','charisma','frame','entrance','none'].includes(kind))fail(400,'VALIDATION','نوع الجائزة غير صحيح.');
  if(['frame','entrance'].includes(kind)&&(!roomShop.some(v=>v.kind===kind&&v.id===p.styleId)||!Number.isInteger(p.days)||p.days<1||p.days>30))fail(400,'VALIDATION','اختَر إطارًا أو تأثيرًا متاحًا لمدة 1 إلى 30 يومًا.');
  ids.add(p.id);
 }
 if(!items.some(p=>p.weight>0))fail(400,'VALIDATION','يجب أن تكون فرصة جائزة واحدة على الأقل أكبر من صفر.');
 return items.map(p=>({...p,label:p.label.trim()}));
}
export function drawPrize(prizes,draw=randomInt){
 const total=prizes.reduce((n,p)=>n+p.weight,0);let n=draw(total);
 for(let i=0;i<prizes.length;i++){n-=prizes[i].weight;if(n<0)return i;}
 throw Error('Invalid prize weights');
}
export function sampleUsers(ids,count,draw=randomInt){
 const a=[...ids];for(let i=0;i<count;i++){const j=i+draw(a.length-i);[a[i],a[j]]=[a[j],a[i]];}return a.slice(0,count);
}
export function createRoulette({database,ownerUserId,readJson,respond,limit,accountGate}){
 const owner=c=>{if(!ownerUserId||c.id!==ownerUserId)fail(403,'ADMIN_FORBIDDEN','إعدادات الروليت لمالك التطبيق فقط.');};
 async function config(db){const r=(await db.query('SELECT * FROM tomi_roulette_config WHERE id=1')).rows[0];return {revision:Number(r.revision),mode:r.mode,dailyLimit:Number(r.daily_limit),prizes:r.prizes==='[]'?defaultPrizes:JSON.parse(r.prizes)};}
 // Shared advisory gates allow independent players to spin concurrently on PostgreSQL.
 async function gate(db,exclusive){if(database.dialect==='postgres')await db.query('SELECT '+(exclusive?'pg_advisory_xact_lock':'pg_advisory_xact_lock_shared')+'(174115,1)');}
 async function membership(db,rid,c,lock=false){
  if(lock)await db.query('UPDATE tomi_voice_rooms SET revision=revision WHERE id=?',[rid]);
  const row=(await db.query("SELECT r.state,p.tier,p.last_owner_visit,m.session_hash FROM tomi_voice_rooms r JOIN tomi_room_policy p ON p.room_id=r.id JOIN tomi_voice_members m ON m.room_id=r.id AND m.user_id=? AND m.state='active' WHERE r.id=?",[c.id,rid])).rows[0];
  if(!row||row.state!=='open'||row.session_hash!==c.tokenHash||row.tier==='advanced'&&Date.parse(row.last_owner_visit)<=Date.now()-60*86400000)fail(403,'ROOM_MEMBERSHIP','الروليت متاحة أثناء وجودك في غرفة صوتية فقط.');
 }
 async function eligibility(db,cfg,uid){const r=(await db.query('SELECT allowed FROM tomi_roulette_access WHERE user_id=?',[uid])).rows[0];return r?!!Number(r.allowed):cfg.mode==='everyone';}
 async function state(db,rid,c){await membership(db,rid,c);const cfg=await config(db),allowed=await eligibility(db,cfg,c.id),day=rouletteDay(),r=(await db.query('SELECT used FROM tomi_roulette_daily WHERE user_id=? AND day=?',[c.id,day])).rows[0];
  const recent=(await db.query('SELECT result FROM tomi_roulette_spins WHERE user_id=? ORDER BY created_at DESC,request_id DESC LIMIT 10',[c.id])).rows.map(x=>JSON.parse(x.result));
  return {config:cfg,allowed,remaining:Math.max(0,cfg.dailyLimit-Number(r?.used??0)),day,recent};
 }
 async function candidates(db,criterion='combined',poolSize=1000){
  if(!['combined','credits','support','activity'].includes(criterion))fail(400,'VALIDATION','معيار المساهمة غير صحيح.');
  const since=new Date(Date.now()-30*86400000).toISOString();
  const score={credits:'credits',support:'support',activity:'activity',combined:'credits+support+activity*10'}[criterion];
  const cte=`WITH contributions AS (
   SELECT u.id,u.username,u.display_name,COALESCE(c.total,0) credits,COALESCE(p.spent,0) support,
   (SELECT COUNT(*) FROM tomi_chat_messages m WHERE m.sender_id=u.id AND m.created_at>=? AND m.deleted_at IS NULL)+
   (SELECT COUNT(*) FROM tomi_posts p WHERE p.user_id=u.id AND p.created_at>=?) activity,
   a.allowed FROM tomi_users u LEFT JOIN tomi_contribution_credits c ON c.user_id=u.id
   LEFT JOIN tomi_user_progress p ON p.user_id=u.id LEFT JOIN tomi_roulette_access a ON a.user_id=u.id
   WHERE NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts d WHERE d.user_id=u.id)
   AND NOT EXISTS(SELECT 1 FROM tomi_account_restrictions r WHERE r.user_id=u.id AND r.suspended=1)
  ), ranked AS (SELECT *,(${score}) score FROM contributions) `;
  const total=Number((await db.query('SELECT * FROM ('+cte+'SELECT COUNT(*) n FROM ranked WHERE score>0) counted',[since,since])).rows[0].n);
  const rows=(await db.query('SELECT * FROM ('+cte+'SELECT * FROM ranked WHERE score>0 ORDER BY score DESC,id LIMIT ?) ranked_pool',[since,since,poolSize])).rows;
  return {total,items:rows.map(r=>({id:r.id,username:r.username,displayName:r.display_name,credits:Number(r.credits),support:Number(r.support),activity:Number(r.activity),score:Number(r.score),override:r.allowed===null?null:!!Number(r.allowed)}))};
 }
 async function command(c,d){
  owner(c);if(!uuid(d.requestId)||!['configure','grant','revoke','random'].includes(d.action))fail(400,'VALIDATION','طلب الروليت غير صحيح.');
  const allowed=['requestId','action','expectedRevision',...(d.action==='configure'?['mode','dailyLimit','prizes']:d.action==='random'?['criterion','poolSize','count']:['users'])];
  if(Object.keys(d).some(k=>!allowed.includes(k)))fail(400,'VALIDATION','حقل غير مسموح.');
  const fingerprint=digest(JSON.stringify(Object.fromEntries(Object.keys(d).sort().map(k=>[k,d[k]]))));
  return database.transaction(async db=>{
   // Account-erasure gates precede the global configuration gate. A queued
   // deletion can never create an inverse gate cycle with an in-flight spin.
   const saved=(await db.query('SELECT fingerprint,result FROM tomi_roulette_requests WHERE actor_id=? AND request_id=?',[c.id,d.requestId])).rows[0];
   if(saved){if(saved.fingerprint!==fingerprint)fail(409,'REQUEST_CHANGED','محتوى الطلب تغيّر.');return {...JSON.parse(saved.result),replayed:true};}
   let selected=[];
   if(d.action!=='configure'){
    if(d.action==='random'){
     if(!Number.isSafeInteger(d.poolSize)||d.poolSize<1||d.poolSize>10000||!Number.isSafeInteger(d.count)||d.count<1||d.count>d.poolSize||d.count>1000)fail(400,'VALIDATION','المجموعة حتى 10000 والاختيار حتى 1000 شخص.');
     const pool=await candidates(db,d.criterion,d.poolSize);if(pool.items.length<d.count)fail(409,'ROULETTE_POOL','عدد المساهمين المؤهلين أقل من المطلوب.');
     selected=sampleUsers(pool.items.map(x=>x.id),d.count);
    }else{
     if(!Array.isArray(d.users)||!d.users.length||d.users.length>1000||d.users.some(x=>typeof x!=='string'||x.length>40))fail(400,'VALIDATION','أدخل حتى 1000 معرّف أو اسم مستخدم.');
     for(const raw of [...new Set(d.users)]){const key=raw.trim().replace(/^@/,'').toLowerCase(),r=(await db.query('SELECT id FROM tomi_users WHERE '+(uuid(key)?'id':'username')+'=?',[key])).rows[0];if(!r)fail(404,'NOT_FOUND','لم نجد الحساب: '+key);selected.push(r.id);}
     selected=[...new Set(selected)];
    }
    for(const uid of [...selected].sort())await accountGate(db,uid);
   }
   await gate(db,true);const old=(await db.query('SELECT fingerprint,result FROM tomi_roulette_requests WHERE actor_id=? AND request_id=?',[c.id,d.requestId])).rows[0];
   if(old){if(old.fingerprint!==fingerprint)fail(409,'REQUEST_CHANGED','لا تغيّر محتوى طلب معلّق؛ تحقّق من نتيجته.');return {...JSON.parse(old.result),replayed:true};}
   const cfg=await config(db);if(d.expectedRevision!==cfg.revision)fail(409,'ROULETTE_CHANGED','تغيّرت إعدادات الروليت؛ حدّث الصفحة.');
   if(d.action==='configure'){
    if(!['everyone','selected'].includes(d.mode)||!Number.isSafeInteger(d.dailyLimit)||d.dailyLimit<1||d.dailyLimit>100)fail(400,'VALIDATION','عدد المحاولات من 1 إلى 100 يوميًا.');
    const prizes=validatePrizes(d.prizes);await db.query('UPDATE tomi_roulette_config SET mode=?,daily_limit=?,prizes=? WHERE id=1',[d.mode,d.dailyLimit,JSON.stringify(prizes)]);
   }else{
    for(const uid of [...selected].sort()){
     await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=?',[uid]);
     if((await db.query('SELECT 1 FROM tomi_deleted_accounts WHERE user_id=?',[uid])).rows.length)fail(409,'ACCOUNT_DELETED','أحد الحسابات محذوف.');
     if(d.action!=='revoke'&&(await db.query('SELECT 1 FROM tomi_account_restrictions WHERE user_id=? AND suspended=1',[uid])).rows.length)fail(409,'ACCOUNT_SUSPENDED','أحد الحسابات موقوف.');
     await db.query('INSERT INTO tomi_roulette_access(user_id,allowed,updated_at) VALUES(?,?,?) ON CONFLICT(user_id) DO UPDATE SET allowed=excluded.allowed,updated_at=excluded.updated_at',[uid,d.action==='revoke'?0:1,stamp()]);
    }
   }
   await db.query('UPDATE tomi_roulette_config SET revision=revision+1 WHERE id=1');
   const result={action:d.action,createdAt:stamp(),config:await config(db),selectedIds:selected,count:selected.length,receiptId:randomUUID()};
   await db.query('INSERT INTO tomi_roulette_requests(actor_id,request_id,fingerprint,result,action,created_at) VALUES(?,?,?,?,?,?)',[c.id,d.requestId,fingerprint,JSON.stringify(result),d.action,result.createdAt]);
   await db.query('INSERT INTO tomi_admin_audit(id,actor_id,action,target_type,target_id,reason,details,created_at) VALUES(?,?,?,?,?,?,?,?)',[result.receiptId,c.id,'roulette_'+d.action,'roulette','roulette','إدارة الروليت',JSON.stringify({before:cfg,after:result.config,selectedIds:selected}),stamp()]);
   return result;
  });
 }
 async function handle(request,response,url,current){
  const path=url.pathname,method=request.method;
  if(path==='/v1/admin/roulette'&&method==='GET'){owner(current);respond(response,200,{config:await config(database)});return true;}
  if(path==='/v1/admin/roulette/candidates'&&method==='GET'){
   owner(current);await limit('roulette-candidates:'+current.id,30);const n=Number(url.searchParams.get('poolSize')??1000),offset=Number(url.searchParams.get('offset')??0);
   if(!Number.isInteger(n)||n<1||n>10000||!Number.isInteger(offset)||offset<0||offset>10000)fail(400,'VALIDATION','الصفحة غير صحيحة.');
   const p=await candidates(database,url.searchParams.get('criterion')??'combined',n);respond(response,200,{total:p.total,poolCount:p.items.length,items:p.items.slice(offset,offset+50),nextOffset:offset+50<p.items.length?offset+50:null});return true;
  }
  if(path==='/v1/admin/roulette/groups'&&method==='GET'){
   owner(current);const rows=(await database.query("SELECT result FROM tomi_roulette_requests WHERE action IN('random','grant') ORDER BY created_at DESC,request_id DESC LIMIT 20")).rows;
   respond(response,200,{items:rows.map(r=>JSON.parse(r.result)).map(r=>({receiptId:r.receiptId,createdAt:r.createdAt,count:r.count,selectedIds:r.selectedIds}))});return true;
  }
  if(path==='/v1/admin/roulette/actions'&&method==='POST'){owner(current);await limit('roulette-admin:'+current.id,30);respond(response,200,await command(current,await readJson(request,262144)));return true;}
  const m=/^\/v1\/rooms\/([a-f0-9-]{36})\/roulette(?:\/(spin|receipts\/([a-f0-9-]{36})))?$/.exec(path);
  if(!m||!uuid(m[1]))return false;
  if(!m[2]&&method==='GET'){respond(response,200,await state(database,m[1],current));return true;}
  if(m[3]&&method==='GET'){
   if(!uuid(m[3]))fail(400,'VALIDATION','إيصال غير صحيح.');await membership(database,m[1],current);
   const r=(await database.query('SELECT result FROM tomi_roulette_spins WHERE user_id=? AND request_id=? AND room_id=?',[current.id,m[3],m[1]])).rows[0];if(!r)fail(404,'NOT_FOUND','لم تُسجّل هذه المحاولة.');respond(response,200,JSON.parse(r.result));return true;
  }
  if(m[2]!=='spin'||method!=='POST')return false;
  await limit('roulette-spin:'+current.id,30);const d=await readJson(request);
  if(!uuid(d.requestId)||Object.keys(d).some(k=>k!=='requestId'))fail(400,'VALIDATION','طلب المحاولة غير صحيح.');
  const result=await database.transaction(async db=>{
   await gate(db,false);await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=?',[current.id]);
   await membership(db,m[1],current,true);
   const old=(await db.query('SELECT room_id,result FROM tomi_roulette_spins WHERE user_id=? AND request_id=?',[current.id,d.requestId])).rows[0];
   if(old){if(old.room_id!==m[1])fail(409,'REQUEST_CHANGED','هذه المحاولة مرتبطة بغرفة أخرى.');return {...JSON.parse(old.result),replayed:true};}
   const cfg=await config(db);if(!await eligibility(db,cfg,current.id))fail(403,'ROULETTE_ACCESS','الروليت غير مفعّلة لحسابك حاليًا.');
   const day=rouletteDay();await db.query('INSERT INTO tomi_roulette_daily(user_id,day) VALUES(?,?) ON CONFLICT(user_id,day) DO NOTHING',[current.id,day]);
   const counter=(await db.query('UPDATE tomi_roulette_daily SET used=used+1 WHERE user_id=? AND day=? AND used<? RETURNING used',[current.id,day,cfg.dailyLimit])).rows[0];
   if(!counter)fail(409,'ROULETTE_LIMIT','اكتملت محاولات اليوم؛ تتجدد منتصف الليل بتوقيت بغداد.');
   const index=drawPrize(cfg.prizes),prize=cfg.prizes[index],kind=prize.kind??'coins';
   await db.query('INSERT INTO tomi_room_wallets(user_id,coins,next_claim) VALUES(?,?,?) ON CONFLICT(user_id) DO NOTHING',[current.id,welcomeCoins,new Date(Date.now()+86400000).toISOString()]);
   const coinAward=kind==='coins'?prize.coins:0;
   const w=(await db.query('UPDATE tomi_room_wallets SET coins=coins+? WHERE user_id=? AND coins+?<=9000000000000 RETURNING coins',[coinAward,current.id,coinAward])).rows[0];
   if(!w)fail(409,'ROULETTE_BALANCE','الرصيد وصل الحد الأعلى.');
   let reward={kind,amount:kind==='none'?0:prize.coins};
   if(kind==='charisma'){
    await db.query('INSERT INTO tomi_user_progress(user_id) VALUES(?) ON CONFLICT(user_id) DO NOTHING',[current.id]);
    const p=(await db.query('UPDATE tomi_user_progress SET received=received+? WHERE user_id=? AND received+?<=9000000000000 RETURNING received',[prize.coins,current.id,prize.coins])).rows[0];
    if(!p)fail(409,'ROULETTE_BALANCE','الكرزما وصلت الحد الأعلى.');reward.balance=Number(p.received);
   }
   if(['frame','entrance'].includes(kind)){
    const old=(await db.query('SELECT expires_at,equipped FROM tomi_room_cosmetics WHERE user_id=? AND kind=? AND style_id=?',[current.id,kind,prize.styleId])).rows[0];
    const expiresAt=new Date(Math.max(Date.now(),Date.parse(old?.expires_at??'')||0)+prize.days*86400000).toISOString();
    await db.query('INSERT INTO tomi_room_cosmetics(user_id,kind,style_id,expires_at,equipped) VALUES(?,?,?,?,0) ON CONFLICT(user_id,kind,style_id) DO UPDATE SET expires_at=excluded.expires_at',[current.id,kind,prize.styleId,expiresAt]);
    reward={kind,styleId:prize.styleId,days:prize.days,expiresAt};
   }
   const result={reward,requestId:d.requestId,roomId:m[1],prize,index,prizes:cfg.prizes,configRevision:cfg.revision,coins:Number(w.coins),remaining:cfg.dailyLimit-Number(counter.used),day,createdAt:stamp()};
   await db.query('INSERT INTO tomi_roulette_spins(user_id,request_id,room_id,result,created_at) VALUES(?,?,?,?,?)',[current.id,d.requestId,m[1],JSON.stringify(result),result.createdAt]);return result;
  });respond(response,200,result);return true;
 }
 return {handle};
}
