import {once} from 'node:events';
import WebSocket from 'ws';
import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture,people,password} from './fixtures/platform-api.mjs';
import {liveSlots,chooseLiveResult,livePayout,validateLiveChips,createLiveRoulette} from '../src/live_roulette.mjs';
import {charismaLevels,charismaStatus} from '../src/charisma_catalog.mjs';
async function ready(t){
 let time=Date.now();const clock=()=>time,f=await fixture(t,{liveRouletteClock:clock,liveRouletteAutoTick:false}),p=await people(f);
 for(const table of ['bets','requests','last','daily','awards','award_days','rounds'])await f.db.query('DELETE FROM tomi_live_roulette_'+table);
 await f.db.query("UPDATE tomi_live_roulette_state SET data='{}',revision=0 WHERE id=1");await f.db.query("UPDATE tomi_roulette_config SET mode='everyone'");
 const r=(await f.req(p.member,'POST','/v1/rooms',{requestId:randomUUID(),title:'العجلة المشتركة',capacity:10,seatCount:4})).data.room;
 for(const a of [p.member,p.mod])assert.equal((await f.req(a,'POST',`/v1/rooms/${r.id}/join`,{})).status,200);
 const base=`/v1/rooms/${r.id}/live-roulette`,state=async(a=p.member)=>{const r=await f.req(a,'GET',base);assert.equal(r.status,200,JSON.stringify(r));return r.data;};
 const step=async ms=>{time+=ms;await f.server.sweepLiveRoulette();},control=async(mode,slot)=>{const c=(await f.req(p.owner,'GET','/v1/admin/live-roulette')).data;return f.req(p.owner,'POST','/v1/admin/live-roulette',{requestId:randomUUID(),expectedRevision:c.controlRevision,mode,...(slot===undefined?{}:{slot})});};
 const bet=async(a,chips,extra={})=>f.req(a,'POST',base+'/bet',{requestId:randomUUID(),roundId:(await state(a)).roundId,chips,...extra});
 return {f,...p,r,base,clock,state,step,control,bet};
}
test('1.6 roulette exact 1000-point boundaries, independent draws, salads and per-cell payouts',()=>{
 assert.equal(liveSlots.reduce((n,s)=>n+s.weight,0),1000);let base=0;for(const s of liveSlots){for(const n of [base,base+s.weight-1])assert.equal(chooseLiveResult({mode:'random'},false,()=>n).slot,s.slot);base+=s.weight;}
 assert.equal(chooseLiveResult({mode:'slot',slot:7}).multiplier,45);
 for(const category of ['fruit','meat']){const result=chooseLiveResult({mode:category+'_salad'},false,()=>0),chips=liveSlots.map(s=>({slot:s.slot,denomination:20}));assert.equal(result.kind,'salad');assert.equal(result.category,category);assert.equal(livePayout(chips,result),category==='fruit'?400:1900);}
 assert.equal(chooseLiveResult({mode:'random'},true,()=>0).kind,'salad');
 for(const chips of [[],[{slot:8,denomination:20}],[{slot:0,denomination:1}],[{slot:0,denomination:20,payout:999}],Array(81).fill({slot:0,denomination:20})])assert.throws(()=>validateLiveChips(chips));
});
test('1.6 charisma tier boundaries follow supplied stars, diamonds and crowns independently from donor XP',()=>{
 for(const t of charismaLevels){const c=charismaStatus(t.minimum);assert.equal(c.level,t.level);assert.equal(c.icon,t.icon);if(t.level>0)assert.equal(charismaStatus(t.minimum-1).level,t.level-1);}
 assert.equal(charismaStatus(0).level,0);assert.equal(charismaStatus(20000000).level,15);assert.equal(charismaStatus(20000000).next,null);
});
test('1.6 shared wheel membership, app-owner authorization and permission revocation are enforced',async t=>{
 const {f,owner,member,mod,base,state,bet}=await ready(t);const one=await state(),two=await state(mod);assert.equal(one.roundId,two.roundId);assert.equal(one.phase,'betting');assert.equal(one.result,null);assert.equal(one.slots.length,8);assert.deepEqual(one.denominations,[20,100,1000,5000]);assert.equal((await f.req(owner,'GET',base)).status,403);assert.equal((await f.req(null,'GET',base)).status,401);assert.equal((await f.req(member,'GET','/v1/admin/live-roulette')).status,403);
 await f.db.query('INSERT INTO tomi_roulette_access(user_id,allowed,updated_at) VALUES(?,0,?)',[member.user.id,new Date().toISOString()]);assert.equal((await bet(member,[{slot:0,denomination:20}])).status,403);assert.equal((await state()).coins,1000);
});
test('1.6 identical concurrent stakes debit once, reject changed receipts and never reveal another player stake',async t=>{
 const {f,member,mod,base,state}=await ready(t),round=await state(),body={requestId:randomUUID(),roundId:round.roundId,chips:[{slot:0,denomination:20}]};
 const rs=await Promise.all([1,2].map(()=>f.req(member,'POST',base+'/bet',body)));assert.ok(rs.every(r=>r.status===200),JSON.stringify(rs));assert.equal((await state()).coins,980);assert.equal((await state()).ownBets.length,1);
 assert.equal((await f.req(member,'POST',base+'/bet',{...body,chips:[{slot:1,denomination:20}]})).status,409);assert.equal((await f.req(member,'POST',base+'/bet',{...body,coins:9999})).status,400);
 const other=await state(mod);assert.deepEqual(other.ownBets,[]);assert.equal(other.slots[0].hotRank,1);assert.ok(other.slots.every(s=>!Object.hasOwn(s,'totalBet')));
 await f.restart();assert.equal((await f.req(member,'POST',base+'/bet',body)).data.receipt.replayed,true);assert.equal((await state()).coins,980);
});
test('1.6 timed settlement is shared, credits the fixed multiplier once, persists after restart and repeats last chips',async t=>{
 const {f,member,mod,base,state,control,step,bet}=await ready(t);assert.equal((await control('slot',2)).status,200);await step(42001);const round=await state();assert.equal(round.controlled,true);assert.equal(round.result,null);
 assert.equal((await bet(member,[{slot:2,denomination:20}])).status,200);assert.equal((await bet(mod,[{slot:0,denomination:20}])).status,200);await step(30000);
 const a=await state(),b=await state(mod);assert.equal(a.phase,'spinning');assert.deepEqual(a.result,b.result);assert.equal(a.result.slot,2);assert.equal(a.coins,1080);assert.equal(b.coins,980);assert.equal(a.myResult.payout,100);assert.equal(a.winners[0].user.id,member.user.id);
 await f.restart();await f.server.sweepLiveRoulette();assert.equal((await state()).coins,1080);await step(7000);assert.equal((await state()).phase,'results');await step(5000);const next=await state();assert.notEqual(next.roundId,round.roundId);
 const repeated=await f.req(member,'POST',base+'/bet',{requestId:randomUUID(),roundId:next.roundId,repeat:true});assert.equal(repeated.status,200,JSON.stringify(repeated));assert.deepEqual(repeated.data.receipt.chips,[{slot:2,denomination:20}]);assert.equal(repeated.data.state.coins,1060);
 // Ranking tracks gross winnings even when the existing wallet ceiling limits credit.
 await f.db.query('UPDATE tomi_room_wallets SET coins=8999999999999 WHERE user_id=?',[member.user.id]);
 const capState=JSON.parse((await f.db.query('SELECT data FROM tomi_live_roulette_state')).rows[0].data);capState.control={mode:'slot',slot:2};await f.db.query('UPDATE tomi_live_roulette_state SET data=?',[JSON.stringify(capState)]);
 await step(30000);const capped=await state();assert.equal(capped.coins,9000000000000);assert.equal(capped.myResult.payout,1);
 const ledger=(await f.db.query('SELECT payout,gross_payout FROM tomi_live_roulette_bets WHERE round_id=? AND user_id=?',[next.roundId,member.user.id])).rows[0];assert.equal(Number(ledger.gross_payout),100);assert.equal(Number(ledger.payout),1);
 assert.equal(Number((await f.db.query('SELECT SUM(total_payout) n FROM tomi_live_roulette_daily WHERE user_id=?',[member.user.id])).rows[0].n),200);
});
test('1.6 ended, malformed and unaffordable stakes never debit or move into a later round',async t=>{
 const {f,member,base,state,step,bet}=await ready(t);assert.equal((await bet(member,[{slot:0,denomination:5000}])).status,409);assert.equal((await state()).coins,1000);
 const old=await state();await step(30001);const result=await f.req(member,'POST',base+'/bet',{roundId:old.roundId,requestId:randomUUID(),chips:[{slot:0,denomination:20}]});assert.equal(result.status,409);assert.equal((await state()).coins,1000);await step(12000);assert.equal((await f.req(member,'POST',base+'/bet',{roundId:old.roundId,requestId:randomUUID(),chips:[{slot:0,denomination:20}]})).status,409);
});
test('1.6 owner controls only the next unopened round, with audited idempotent receipts and revision checks',async t=>{
 const {f,owner,state}=await ready(t),before=await state(),cfg=(await f.req(owner,'GET','/v1/admin/live-roulette')).data,body={requestId:randomUUID(),expectedRevision:cfg.controlRevision,mode:'meat_salad'};
 const rs=await Promise.all([1,2].map(()=>f.req(owner,'POST','/v1/admin/live-roulette',body)));assert.ok(rs.every(r=>r.status===200));assert.equal(Number((await f.db.query("SELECT COUNT(*) n FROM tomi_admin_audit WHERE action='live_roulette_control'")).rows[0].n),1);const after=await state();assert.equal(after.roundId,before.roundId);assert.equal(after.controlled,false);
 assert.equal((await f.req(owner,'POST','/v1/admin/live-roulette',{...body,requestId:randomUUID()})).status,409);assert.equal((await f.req(owner,'POST','/v1/admin/live-roulette',{...body,mode:'slot',slot:8})).status,400);
});
test('1.6 rare category results pay every matched cell and persist the next two-to-six-hour schedule',async t=>{
 const {f,member,state,bet,step,clock}=await ready(t);await state();const row=(await f.db.query('SELECT data FROM tomi_live_roulette_state')).rows[0],s=JSON.parse(row.data);s.saladNextAt=clock()-1;await f.db.query('UPDATE tomi_live_roulette_state SET data=?',[JSON.stringify(s)]);
 await bet(member,liveSlots.map(s=>({slot:s.slot,denomination:20})));await step(30000);const result=await state();assert.equal(result.result.kind,'salad');assert.equal(result.coins,840+(result.result.category==='fruit'?400:1900));const next=JSON.parse((await f.db.query('SELECT data FROM tomi_live_roulette_state')).rows[0].data).saladNextAt;assert.ok(next>=clock()+7200000&&next<=clock()+21600000);await f.restart();assert.equal(JSON.parse((await f.db.query('SELECT data FROM tomi_live_roulette_state')).rows[0].data).saladNextAt,next);
});
test('1.6 Baghdad daily top-three awards are credited once and stay separate from gift and recharge progress',async t=>{
 const {f,member,mod,owner,state,step,clock}=await ready(t);await state();for(const a of [owner,mod])await f.req(a,'GET','/v1/rooms/wallet');const yesterday=new Date(clock()+10800000-86400000).toISOString().slice(0,10);
 for(const [a,payout] of [[member,30000],[mod,20000],[owner,10000]])await f.db.query('INSERT INTO tomi_live_roulette_daily(day,user_id,total_bet,total_payout,wins) VALUES(?,?,20,?,1)',[yesterday,a.user.id,payout]);
 // A phase transition processes rollover even if no users open the leaderboard.
 await step(30000);assert.equal((await state()).coins,3000);assert.equal((await state(mod)).coins,2000);assert.equal(Number((await f.db.query('SELECT coins FROM tomi_room_wallets WHERE user_id=?',[owner.user.id])).rows[0].coins),1500);
 await f.restart();await step(7000);assert.equal((await state()).coins,3000);assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_live_roulette_awards')).rows[0].n),3);assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_contribution_credits')).rows[0].n),0);
});
test('1.6 independent coordinators settle one persisted round without double credit',async t=>{
 const {f,member,state,control,step,clock,bet}=await ready(t);await control('slot',0);await step(42001);await bet(member,[{slot:0,denomination:20}]);
 const replica=createLiveRoulette({database:f.db,ownerUserId:null,clock:()=>clock()+30000,autoTick:false,emit:()=>{},usersByIds:async()=>new Map()});await Promise.all([replica.advance(),replica.advance()]);replica.close();assert.equal(Number((await f.db.query('SELECT coins FROM tomi_room_wallets WHERE user_id=?',[member.user.id])).rows[0].coins),1080);
 await step(30000);assert.equal((await state()).coins,1080);
});
test('1.6 erasing a bettor removes private roulette records and cannot recreate their wallet during settlement',async t=>{
 const {f,member,mod,state,step,bet}=await ready(t);await bet(member,[{slot:0,denomination:20}]);const erased=await f.req(member,'POST','/v1/account/deletion',{password,confirmation:'حذف حسابي',requestId:randomUUID(),receiptToken:'x'.repeat(43)});assert.equal(erased.status,202,JSON.stringify(erased));
 const before=await f.db.query('SELECT coins FROM tomi_room_wallets WHERE user_id=?',[member.user.id]);await step(30000);assert.equal((await f.req(mod,'GET',`/v1/rooms/${(await f.db.query("SELECT id FROM tomi_voice_rooms LIMIT 1")).rows[0].id}/live-roulette`)).status,403);const after=await f.db.query('SELECT coins FROM tomi_room_wallets WHERE user_id=?',[member.user.id]);assert.deepEqual(after.rows,before.rows);
 for(const table of ['bets','requests','last','daily','awards'])assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_live_roulette_'+table+' WHERE user_id=?',[member.user.id])).rows[0].n),0);
});

test('1.6 settlement racing owner credits and account erasure preserves one payout and erases private records',async t=>{
 const {f,member,mod,owner,control,state,step,clock,bet}=await ready(t);await control('slot',0);await step(42001);await bet(member,[{slot:0,denomination:20}]);await bet(mod,[{slot:0,denomination:20}]);
 const replica=createLiveRoulette({database:f.db,clock:()=>clock()+30000,autoTick:false,emit:()=>{},usersByIds:async()=>new Map()});
 const [_,grant,erased]=await Promise.all([replica.advance(),f.command(owner,'add_coins',mod.user.id,{amount:100}),f.req(member,'POST','/v1/account/deletion',{password,confirmation:'حذف حسابي',requestId:randomUUID(),receiptToken:'v'.repeat(43)})]);replica.close();assert.equal(grant.status,200,JSON.stringify(grant));assert.equal(erased.status,202,JSON.stringify(erased));
 assert.equal(Number((await f.db.query('SELECT coins FROM tomi_room_wallets WHERE user_id=?',[mod.user.id])).rows[0].coins),1180);
 for(const table of ['bets','requests','last','daily','awards'])assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_live_roulette_'+table+' WHERE user_id=?',[member.user.id])).rows[0].n),0);
 await f.restart();await f.server.sweepLiveRoulette();assert.equal(Number((await f.db.query('SELECT coins FROM tomi_room_wallets WHERE user_id=?',[mod.user.id])).rows[0].coins),1180);
});

test('1.6.1 podium belongs to this round only, ranks three winners deterministically and lasts five seconds',async t=>{
 const {f,member,mod,owner,r,state,control,step,bet}=await ready(t),fourth=await f.register('fourth_winner');
 for(const a of [owner,fourth])assert.equal((await f.req(a,'POST',`/v1/rooms/${r.id}/join`,{})).status,200);
 await control('slot',0);await step(42001);const first=await state();
 for(const [a,amount] of [[member,100],[mod,20],[owner,20],[fourth,20]])assert.equal((await bet(a,[{slot:0,denomination:amount}])).status,200);
 await step(30000);const result=await state();assert.equal(result.winnersRoundId,first.roundId);assert.equal(result.winners.length,3);
 const tied=[mod,owner,fourth].map(a=>a.user.id).sort();assert.deepEqual(result.winners.map(w=>w.user.id),[member.user.id,...tied.slice(0,2)]);assert.deepEqual(result.winners.map(w=>w.payout),[500,100,100]);
 await step(7000);const shown=await state();assert.equal(shown.phase,'results');assert.equal(shown.resultsEndsAt-shown.serverTime,5000);await control('slot',1);
 await step(4999);assert.equal((await state()).phase,'results');await step(1);const next=await state();assert.notEqual(next.roundId,first.roundId);assert.deepEqual(next.winners,[]);assert.equal(next.myResult,null);
 await bet(mod,[{slot:1,denomination:20}]);await step(30000);const second=await state();assert.equal(second.winnersRoundId,next.roundId);assert.deepEqual(second.winners.map(w=>w.user.id),[mod.user.id]);
 assert.equal(second.recentRounds[0].roundId,next.roundId);assert.equal(second.recentRounds[1].roundId,first.roundId);assert.equal(second.recentRounds[1].payout,500);
});
test('1.6.1 cached HOT ranks refresh after a new committed wager without exposing another account bets',async t=>{
 const {f,member,mod,state,bet,step}=await ready(t);await bet(member,[{slot:0,denomination:20}]);const before=await state(mod);assert.equal(before.slots[0].hotRank,1);await state(mod);
 await bet(mod,[{slot:7,denomination:100}]);const after=await state();assert.equal(after.slots[7].hotRank,1);assert.equal(after.slots[0].hotRank,2);assert.deepEqual(after.ownBets,[{slot:0,denomination:20}]);assert.equal(after.coins,980);assert.ok(after.slots.every(s=>!Object.hasOwn(s,'totalBet')));
 const erased=await f.req(mod,'POST','/v1/account/deletion',{password,confirmation:'حذف حسابي',requestId:randomUUID(),receiptToken:'p'.repeat(43)});assert.equal(erased.status,202);await step(1000);const cleaned=await state();assert.equal(cleaned.slots[7].hotRank,0);assert.equal(cleaned.slots[0].hotRank,1);
});

test('1.6.1 accepted wagers notify active room peers promptly without publishing stake data',async t=>{
 const {f,member,mod,owner,state,bet}=await ready(t);await state();
 const sockets=[];
 try{
  for(const actor of [mod,owner]){const w=new WebSocket(f.base.replace('http:','ws:')+'/v1/chat/socket');sockets.push(w);await once(w,'open');const ready=once(w,'message');w.send(JSON.stringify({type:'authenticate',token:actor.token}));assert.equal(JSON.parse((await ready)[0]).type,'chat.ready');}
  const outside=[];sockets[1].on('message',v=>outside.push(JSON.parse(v)));
  let timeout;const notified=new Promise((resolve,reject)=>{timeout=setTimeout(()=>reject(Error('No committed wager update')),1500);sockets[0].once('message',v=>resolve(JSON.parse(v)));});
  try{assert.equal((await bet(member,[{slot:3,denomination:20}])).status,200);assert.deepEqual(await notified,{type:'roulette.live'});}finally{clearTimeout(timeout);}
  assert.deepEqual(outside,[]);assert.equal((await state(mod)).slots[3].hotRank,1);
 }finally{await Promise.all(sockets.map(async w=>{if(w.readyState===WebSocket.CLOSED)return;const end=once(w,'close');w.terminate();await end;}));}
});
