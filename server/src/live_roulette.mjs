import {randomInt,randomUUID} from 'node:crypto';
import {ApiError,digest} from './security.mjs';
import {rouletteDay} from './roulette.mjs';
import {welcomeCoins} from './room_catalog.mjs';
import {awardGameXp} from './game_progress.mjs';

// Ported from the supplied TOMI roulette, without its unrelated games or owner username.
export const liveSlots=Object.freeze([
 {slot:0,icon:'🍉',label:'بطيخ',category:'fruit',multiplier:5,chancePercent:19.4,weight:194},
 {slot:1,icon:'🍊',label:'برتقال',category:'fruit',multiplier:5,chancePercent:19.4,weight:194},
 {slot:2,icon:'🍎',label:'تفاح',category:'fruit',multiplier:5,chancePercent:19.4,weight:194},
 {slot:3,icon:'🥬',label:'خضار',category:'fruit',multiplier:5,chancePercent:19.4,weight:194},
 {slot:4,icon:'🐟',label:'سمك',category:'meat',multiplier:10,chancePercent:9.5,weight:95},
 {slot:5,icon:'🍔',label:'برغر',category:'meat',multiplier:15,chancePercent:7,weight:70},
 {slot:6,icon:'🍤',label:'روبيان',category:'meat',multiplier:25,chancePercent:3.8,weight:38},
 {slot:7,icon:'🍗',label:'دجاج',category:'meat',multiplier:45,chancePercent:2.1,weight:21},
]);
export const liveDenominations=Object.freeze([20,100,1000,5000]);
export const liveDailyPrizes=Object.freeze([2000,1000,500]);
const cap=9000000000000,betMs=30000,spinMs=7000,resultMs=5000;
const uuid=v=>typeof v==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(v);
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
function fields(d,names){if(Object.keys(d).some(k=>!names.includes(k)))fail(400,'VALIDATION','حقل غير مسموح.');}
const decode=v=>JSON.parse(v);
export function chooseLiveResult(control={mode:'random'},saladDue=false,draw=randomInt){
 let category=control.mode==='fruit_salad'?'fruit':control.mode==='meat_salad'?'meat':null;
 if(!category&&control.mode==='random'&&saladDue)category=draw(2)===0?'fruit':'meat';
 if(category){const cells=liveSlots.filter(s=>s.category===category);return {kind:'salad',category,slot:null,displaySlot:cells[draw(cells.length)].slot,icon:category==='fruit'?'🥗':'🍖',label:category==='fruit'?'سلطة فواكه':'سلطة لحوم'};}
 let item;
 if(control.mode==='slot')item=liveSlots[control.slot];
 else {let n=draw(1000);for(const cell of liveSlots){n-=cell.weight;if(n<0){item=cell;break;}}}
 if(!item)throw Error('Invalid roulette result');
 return {kind:'item',...item,displaySlot:item.slot};
}
export function livePayout(chips,result){return chips.reduce((sum,c)=>{const s=liveSlots[c.slot],hit=result.kind==='salad'?s.category===result.category:s.slot===result.slot;return sum+(hit?c.denomination*s.multiplier:0);},0);}
export function validateLiveChips(chips){
 if(!Array.isArray(chips)||!chips.length||chips.length>80||chips.some(c=>!c||Object.keys(c).some(k=>!['slot','denomination'].includes(k))||!Number.isInteger(c.slot)||c.slot<0||c.slot>7||!liveDenominations.includes(c.denomination)))fail(400,'VALIDATION','اختَر خانة ومبلغ 20 أو 100 أو 1000 أو 5000؛ حتى 80 قطعة في الجولة.');
 return chips.map(c=>({slot:c.slot,denomination:c.denomination}));
}
export function createLiveRoulette({database,ownerUserId,readJson,respond,limit,usersByIds,emit,clock=Date.now,autoTick=true,unbound=fn=>fn()}){
 let timer,broadcastTimer,working=null,closed=false,hotCache=null;
 async function broadcast(){if(closed)return;const ids=(await database.query("SELECT DISTINCT user_id FROM tomi_voice_members WHERE state='active' UNION SELECT user_id FROM tomi_roulette_watchers WHERE expires_at>?",[clock()])).rows.map(x=>x.user_id);if(!closed)emit(ids,{type:'roulette.live'});}
 function queueBroadcast(){if(closed||broadcastTimer)return;broadcastTimer=setTimeout(()=>{broadcastTimer=null;unbound(broadcast).catch(()=>{});},120);broadcastTimer.unref?.();}
 const owner=c=>{if(!ownerUserId||c.id!==ownerUserId)fail(403,'ADMIN_FORBIDDEN','هذا التحكم لمالك التطبيق فقط.');};
 async function row(db,lock=false){if(lock)await db.query('UPDATE tomi_live_roulette_state SET revision=revision WHERE id=1');const r=(await db.query('SELECT * FROM tomi_live_roulette_state WHERE id=1')).rows[0];return {s:decode(r.data),revision:Number(r.revision)};}
 async function save(db,s){return Number((await db.query('UPDATE tomi_live_roulette_state SET data=?,revision=revision+1 WHERE id=1 RETURNING revision',[JSON.stringify(s)])).rows[0].revision);}
 async function member(db,rid,c){
  if(rid===null){await db.query('INSERT INTO tomi_roulette_watchers(user_id,expires_at) VALUES(?,?) ON CONFLICT(user_id) DO UPDATE SET expires_at=excluded.expires_at WHERE tomi_roulette_watchers.expires_at<excluded.expires_at-5000',[c.id,clock()+15000]);return;}
  const r=(await db.query("SELECT r.state,m.session_hash,p.tier,p.last_owner_visit FROM tomi_voice_rooms r JOIN tomi_room_policy p ON p.room_id=r.id JOIN tomi_voice_members m ON m.room_id=r.id AND m.user_id=? AND m.state='active' WHERE r.id=?",[c.id,rid])).rows[0];
  if(!r||r.state!=='open'||r.session_hash!==c.tokenHash||r.tier==='advanced'&&Date.parse(r.last_owner_visit)<=Date.now()-60*86400000)fail(403,'ROOM_MEMBERSHIP','اللعبة متاحة أثناء وجودك داخل غرفة صوتية فقط.');
 }
 async function allowed(db,uid){const c=(await db.query('SELECT mode FROM tomi_roulette_config WHERE id=1')).rows[0],a=(await db.query('SELECT allowed FROM tomi_roulette_access WHERE user_id=?',[uid])).rows[0];return a?!!Number(a.allowed):c.mode==='everyone';}
 async function payoutCredit(db,uid,amount){const r=(await db.query('SELECT coins FROM tomi_room_wallets WHERE user_id=?',[uid])).rows[0];if(!r)return null;const updated=await db.query('UPDATE tomi_room_wallets SET coins=coins+? WHERE user_id=? AND coins=? AND NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts d WHERE d.user_id=?) RETURNING coins',[Math.min(amount,cap-Number(r.coins)),uid,Number(r.coins),uid]);
  if(updated.rows[0])return {coins:Number(updated.rows[0].coins),credited:Math.min(amount,cap-Number(r.coins))};
  // Another economy operation committed; lock and retry from its current balance.
  await db.query('UPDATE tomi_room_wallets SET coins=coins WHERE user_id=?',[uid]);const again=(await db.query('SELECT coins FROM tomi_room_wallets WHERE user_id=?',[uid])).rows[0];if(!again)return null;
  const value=Math.min(amount,cap-Number(again.coins)),next=(await db.query('UPDATE tomi_room_wallets SET coins=coins+? WHERE user_id=? AND NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts d WHERE d.user_id=?) RETURNING coins',[value,uid,uid])).rows[0];return next?{coins:Number(next.coins),credited:value}:null;
 }
 async function start(db,s,t){
  const control=s.nextControl??{mode:'random'};
  const next={...s,id:randomUUID(),day:rouletteDay(t),phase:'betting',startedAt:t,bettingEndsAt:t+betMs,spinEndsAt:t+betMs+spinMs,resultsEndsAt:t+betMs+spinMs+resultMs,result:null,control,nextControl:{mode:'random'},controlRevision:s.controlRevision??0,saladNextAt:s.saladNextAt??t+randomInt(7200000,21600001)};
  await db.query('INSERT INTO tomi_live_roulette_rounds(id,day,started_at) VALUES(?,?,?)',[next.id,next.day,t]);return next;
 }
 async function settle(db,s,t){
  const due=t>=s.saladNextAt,result=chooseLiveResult(s.control,due);
  if(s.control.mode==='random'&&due)s.saladNextAt=t+randomInt(7200000,21600001);
  const rows=(await db.query('SELECT * FROM tomi_live_roulette_bets WHERE round_id=? ORDER BY user_id',[s.id])).rows;
  for(const b of rows){const chips=decode(b.chips),gross=livePayout(chips,result),paid=await payoutCredit(db,b.user_id,gross);if(!paid)continue;
   await db.query('UPDATE tomi_live_roulette_bets SET payout=?,gross_payout=?,settled=1 WHERE round_id=? AND user_id=?',[paid.credited,gross,s.id,b.user_id]);
   await db.query('INSERT INTO tomi_live_roulette_last(user_id,chips) VALUES(?,?) ON CONFLICT(user_id) DO UPDATE SET chips=excluded.chips',[b.user_id,b.chips]);
   await db.query('INSERT INTO tomi_live_roulette_daily(day,user_id,total_bet,total_payout,wins) VALUES(?,?,?,?,?) ON CONFLICT(day,user_id) DO UPDATE SET total_bet=tomi_live_roulette_daily.total_bet+excluded.total_bet,total_payout=tomi_live_roulette_daily.total_payout+excluded.total_payout,wins=tomi_live_roulette_daily.wins+excluded.wins',[s.day,b.user_id,Number(b.total),gross,gross>0?1:0]);
   await awardGameXp(db,b.user_id,'roulette',s.id,10,t);
  }
  await db.query('UPDATE tomi_live_roulette_rounds SET result=?,settled_at=? WHERE id=? AND result IS NULL',[JSON.stringify(result),t,s.id]);return {...s,result,phase:'spinning'};
 }
 async function daily(db,s,t){
  const days=(await db.query('SELECT DISTINCT d.day FROM tomi_live_roulette_daily d WHERE d.day<? AND NOT EXISTS(SELECT 1 FROM tomi_live_roulette_award_days a WHERE a.day=d.day) ORDER BY d.day LIMIT 31',[rouletteDay(t)])).rows;
  for(const {day} of days){if(s.phase==='betting'&&s.day===day)continue;
   const winners=(await db.query('SELECT d.user_id FROM tomi_live_roulette_daily d WHERE d.day=? AND d.total_payout>0 AND NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts a WHERE a.user_id=d.user_id) ORDER BY d.total_payout DESC,d.wins DESC,d.user_id LIMIT 3',[day])).rows;
   // The singleton row lock serializes rollover across all API instances.
   await db.query('INSERT INTO tomi_live_roulette_award_days(day,created_at) VALUES(?,?)',[day,t]);
   for(let i=0;i<winners.length;i++){const w=winners[i],paid=await payoutCredit(db,w.user_id,liveDailyPrizes[i]);if(paid)await db.query('INSERT INTO tomi_live_roulette_awards(day,user_id,rank,prize,credited) VALUES(?,?,?,?,?)',[day,w.user_id,i+1,liveDailyPrizes[i],paid.credited]);}
  }
 }
 function shouldAdvance(s,t){return !s.id||t>=(s.phase==='betting'?s.bettingEndsAt:s.phase==='spinning'?s.spinEndsAt:s.resultsEndsAt)||s.awardDay!==rouletteDay(t);}
 async function advance(){
  if(working)return working;
  working=unbound(async()=>{const peek=await row(database);if(!shouldAdvance(peek.s,clock()))return;
   let changed=false;await database.transaction(async db=>{let {s}=await row(db,true);const t=clock();if(!shouldAdvance(s,t))return;
    // Use the same sorted account/wallet order as gifts and owner finance.
    // Background settlement never takes erasure gates after the wheel gate.
    const affected=new Set((await db.query('SELECT user_id FROM tomi_live_roulette_bets WHERE round_id=?',[s.id??''])).rows.map(r=>r.user_id));
    const dates=(await db.query('SELECT DISTINCT d.day FROM tomi_live_roulette_daily d WHERE d.day<? AND NOT EXISTS(SELECT 1 FROM tomi_live_roulette_award_days a WHERE a.day=d.day) ORDER BY d.day LIMIT 31',[rouletteDay(t)])).rows;
    for(const {day} of dates)for(const r of (await db.query('SELECT user_id FROM tomi_live_roulette_daily WHERE day=? AND total_payout>0 AND NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts a WHERE a.user_id=tomi_live_roulette_daily.user_id) ORDER BY total_payout DESC,wins DESC,user_id LIMIT 3',[day])).rows)affected.add(r.user_id);
    for(const uid of [...affected].sort())await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=?',[uid]);
    for(const uid of [...affected].sort())await db.query('UPDATE tomi_room_wallets SET coins=coins WHERE user_id=?',[uid]);
    if(!s.id)s=await start(db,s,t);
    if(s.phase==='betting'&&t>=s.bettingEndsAt)s=await settle(db,s,t);
    if(s.phase==='spinning'&&t>=s.spinEndsAt)s.phase='results';
    if(s.phase==='results'&&t>=s.resultsEndsAt)s=await start(db,s,t);
    await daily(db,s,t);s.awardDay=rouletteDay(t);await save(db,s);changed=true;
   });if(changed)await broadcast();
  }).finally(()=>{working=null;});return working;
 }
 function startTimer(){if(autoTick&&!timer&&!closed){timer=setInterval(()=>advance().catch(()=>{}),1000);timer.unref?.();}}
 async function profileRows(rows,viewer,db=database){const users=await usersByIds(rows.map(r=>r.user_id),viewer,db);return rows.filter(r=>users.has(r.user_id)).map(r=>({...r,user:users.get(r.user_id)}));}
 async function snapshot(rid,c){await member(database,rid,c);await advance();startTimer();return database.transaction(async db=>{
  await member(db,rid,c);const {s,revision}=await row(db),own=(await db.query('SELECT * FROM tomi_live_roulette_bets WHERE round_id=? AND user_id=?',[s.id,c.id])).rows[0];
  // Public HOT ranks are reused only for this committed wheel revision.
  if(!hotCache||hotCache.revision!==revision||hotCache.roundId!==s.id||clock()<hotCache.cachedAt||clock()-hotCache.cachedAt>=1000){
   const hot=(await db.query('SELECT chips FROM tomi_live_roulette_bets WHERE round_id=?',[s.id])).rows,totals=Array(8).fill(0);for(const b of hot)for(const chip of decode(b.chips))totals[chip.slot]+=chip.denomination;
   const ranked=totals.map((n,slot)=>({n,slot})).filter(x=>x.n>0).sort((a,b)=>b.n-a.n||a.slot-b.slot).slice(0,3);hotCache={revision,roundId:s.id,cachedAt:clock(),rank:new Map(ranked.map((x,i)=>[x.slot,i+1]))};
  }
  const rank=hotCache.rank;
  const rounds=(await db.query('SELECT * FROM tomi_live_roulette_rounds WHERE result IS NOT NULL ORDER BY started_at DESC,id DESC LIMIT 8')).rows;
  const history=rounds.length?(await db.query('SELECT round_id,total,payout,gross_payout FROM tomi_live_roulette_bets WHERE user_id=? AND round_id IN('+rounds.map(()=>'?').join(',')+')',[c.id,...rounds.map(r=>r.id)])).rows:[],byRound=new Map(history.map(b=>[b.round_id,b]));
  const recent=rounds.map(r=>{const b=byRound.get(r.id);return {roundId:r.id,day:r.day,result:decode(r.result),totalBet:Number(b?.total??0),payout:Number(b?.payout??0),grossPayout:Number(b?.gross_payout??0),participated:!!b};});
  const winners=s.result?await profileRows((await db.query('SELECT user_id,total,payout FROM tomi_live_roulette_bets WHERE round_id=? AND payout>0 ORDER BY payout DESC,user_id LIMIT 3',[s.id])).rows,c.id,db):[];
  let wallet=(await db.query('SELECT coins FROM tomi_room_wallets WHERE user_id=?',[c.id])).rows[0];
  if(!wallet){await db.query('INSERT INTO tomi_room_wallets(user_id,coins,next_claim) VALUES(?,?,?) ON CONFLICT(user_id) DO NOTHING',[c.id,welcomeCoins,new Date(Date.now()+86400000).toISOString()]);wallet=(await db.query('SELECT coins FROM tomi_room_wallets WHERE user_id=?',[c.id])).rows[0];}
  const coins=Number(wallet.coins),last=(await db.query('SELECT chips FROM tomi_live_roulette_last WHERE user_id=?',[c.id])).rows[0];
  return {roundId:s.id,revision,day:s.day,phase:s.phase,serverTime:clock(),startedAt:s.startedAt,bettingEndsAt:s.bettingEndsAt,spinEndsAt:s.spinEndsAt,resultsEndsAt:s.resultsEndsAt,result:s.result,controlled:s.control.mode!=='random',slots:liveSlots.map(x=>({...x,hotRank:rank.get(x.slot)??0})),denominations:liveDenominations,dailyPrizes:liveDailyPrizes,allowed:await allowed(db,c.id),coins,ownBets:own?decode(own.chips):[],lastBets:last?decode(last.chips):[],recentRounds:recent,winnersRoundId:s.id,winners:winners.map(w=>({user:w.user,payout:Number(w.payout),totalBet:Number(w.total)})),myResult:s.result?recent.find(r=>r.roundId===s.id)??null:null};
 });}
 async function receipt(db,c,d,fingerprint){const r=(await db.query('SELECT * FROM tomi_live_roulette_requests WHERE user_id=? AND request_id=?',[c.id,d.requestId])).rows[0];if(!r)return null;if(r.fingerprint!==fingerprint)fail(409,'REQUEST_CHANGED','محتوى المحاولة تغيّر؛ استخدم طلبًا جديدًا.');return decode(r.result);}
 async function remember(db,c,d,fp,result){await db.query('INSERT INTO tomi_live_roulette_requests(user_id,request_id,fingerprint,result,created_at) VALUES(?,?,?,?,?)',[c.id,d.requestId,fp,JSON.stringify(result),clock()]);}
 async function bet(rid,c,d){fields(d,['requestId','roundId','chips','repeat']);if(!uuid(d.requestId)||!uuid(d.roundId)||d.repeat!==undefined&&d.repeat!==true||d.repeat&&d.chips!==undefined)fail(400,'VALIDATION','طلب الرهان غير صحيح.');if(!d.repeat)validateLiveChips(d.chips);
  const fp=digest(JSON.stringify([d.roundId,d.repeat===true,d.chips??null]));await advance();
  return database.transaction(async db=>{await member(db,rid,c);const {s}=await row(db,true),old=await receipt(db,c,d,fp);if(old)return {...old,replayed:true};
   if(!await allowed(db,c.id))fail(403,'ROULETTE_ACCESS','الروليت غير مفعّلة لحسابك.');if(d.roundId!==s.id||s.phase!=='betting'||clock()>=s.bettingEndsAt)fail(409,'ROULETTE_CLOSED','انتهت الجولة؛ لم يُخصم رهان جديد.');
   let chips=d.chips;if(d.repeat){const last=(await db.query('SELECT chips FROM tomi_live_roulette_last WHERE user_id=?',[c.id])).rows[0];chips=last?decode(last.chips):[];}chips=validateLiveChips(chips);
   const before=(await db.query('SELECT chips,total FROM tomi_live_roulette_bets WHERE round_id=? AND user_id=?',[s.id,c.id])).rows[0],all=[...(before?decode(before.chips):[]),...chips];if(all.length>80)fail(400,'ROULETTE_CHIPS','وصلت حد 80 قطعة لهذه الجولة.');const amount=chips.reduce((a,c)=>a+c.denomination,0);
   await db.query('INSERT INTO tomi_room_wallets(user_id,coins,next_claim) VALUES(?,?,?) ON CONFLICT(user_id) DO NOTHING',[c.id,welcomeCoins,new Date(Date.now()+86400000).toISOString()]);
   const wallet=(await db.query('UPDATE tomi_room_wallets SET coins=coins-? WHERE user_id=? AND coins>=? RETURNING coins',[amount,c.id,amount])).rows[0];if(!wallet)fail(409,'INSUFFICIENT_COINS','رصيدك غير كافٍ.');
   await db.query('INSERT INTO tomi_live_roulette_bets(round_id,user_id,chips,total) VALUES(?,?,?,?) ON CONFLICT(round_id,user_id) DO UPDATE SET chips=excluded.chips,total=excluded.total',[s.id,c.id,JSON.stringify(all),Number(before?.total??0)+amount]);
   await save(db,s);const result={requestId:d.requestId,roundId:s.id,amount,chips,coinsAfterBet:Number(wallet.coins)};await remember(db,c,d,fp,result);return result;
  });
 }
 async function handle(req,res,url,c){const room=url.pathname.match(/^\/v1\/rooms\/([a-f0-9-]{36})\/live-roulette(?:\/(bet|leaderboard))?$/),lobby=url.pathname.match(/^\/v1\/games\/live-roulette(?:\/(bet|leaderboard))?$/),m=room??(lobby?[lobby[0],null,lobby[1]]:null),admin=url.pathname==='/v1/admin/live-roulette';if(!m&&!admin)return false;
  if(admin){owner(c);await advance();if(req.method==='GET'){const {s}=await row(database);respond(res,200,{nextControl:s.nextControl,controlRevision:s.controlRevision,currentControl:s.control,roundId:s.id});return true;}
   if(req.method==='POST'){await limit('roulette-live-control:'+c.id,20);const d=await readJson(req);fields(d,['requestId','expectedRevision','mode','slot']);if(!uuid(d.requestId)||!Number.isSafeInteger(d.expectedRevision)||!['random','slot','fruit_salad','meat_salad'].includes(d.mode)||d.mode==='slot'&&(!Number.isInteger(d.slot)||d.slot<0||d.slot>7)||d.mode!=='slot'&&d.slot!==undefined)fail(400,'VALIDATION','اختَر عشوائيًا أو خانة أو سلطة.');
    const fp=digest(JSON.stringify(['control',d.expectedRevision,d.mode,d.slot??null])),r=await database.transaction(async db=>{const {s}=await row(db,true),old=await receipt(db,c,d,fp);if(old)return {...old,replayed:true};if(d.expectedRevision!==s.controlRevision)fail(409,'ROULETTE_CHANGED','تغيّر التحكم؛ حدّث الصفحة.');s.nextControl={mode:d.mode,...(d.mode==='slot'?{slot:d.slot}:{})};s.controlRevision++;await save(db,s);const result={nextControl:s.nextControl,controlRevision:s.controlRevision};await remember(db,c,d,fp,result);await db.query('INSERT INTO tomi_admin_audit(id,actor_id,action,target_type,target_id,reason,details,created_at) VALUES(?,?,?,?,?,?,?,?)',[randomUUID(),c.id,'live_roulette_control','roulette',s.id,'تحديد الجولة القادمة',JSON.stringify(result),new Date(clock()).toISOString()]);return result;});respond(res,200,r);return true;
   }
  }else if(req.method==='GET'&&!m[2]){respond(res,200,await snapshot(m[1],c));return true;}
  else if(req.method==='POST'&&m[2]==='bet'){await limit('live-roulette-bet:'+c.id,120);const result=await bet(m[1],c,await readJson(req));if(!result.replayed)queueBroadcast();respond(res,200,{receipt:result,state:await snapshot(m[1],c)});return true;}
  else if(req.method==='GET'&&m[2]==='leaderboard'){await member(database,m[1],c);await advance();const day=rouletteDay(clock()),rows=(await database.query('SELECT user_id,total_bet,total_payout,wins FROM tomi_live_roulette_daily WHERE day=? AND total_payout>0 AND NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts a WHERE a.user_id=tomi_live_roulette_daily.user_id) ORDER BY total_payout DESC,wins DESC,user_id LIMIT 20',[day])).rows;respond(res,200,{day,prizes:liveDailyPrizes,users:await profileRows(rows,c.id)});return true;}
  fail(405,'METHOD','العملية غير متاحة.');
 }
 return {handle,advance,close(){closed=true;if(timer)clearInterval(timer);if(broadcastTimer)clearTimeout(broadcastTimer);}};
}
