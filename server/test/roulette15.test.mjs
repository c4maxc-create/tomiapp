import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture,people,password} from './fixtures/platform-api.mjs';
import {defaultPrizes,validatePrizes,drawPrize,sampleUsers,rouletteDay} from '../src/roulette.mjs';
async function ready(t,advanced=false){
 const f=await fixture(t),p=await people(f);
 await f.db.query("UPDATE tomi_roulette_config SET revision=0,mode='everyone',daily_limit=5,prizes='[]' WHERE id=1");
 const r=advanced?await f.create(p.member):(await f.req(p.member,'POST','/v1/rooms',{requestId:randomUUID(),title:'مدار الحظ',capacity:10,seatCount:4})).data.room;
 assert.ok(r?.id);assert.equal((await f.req(p.member,'POST',`/v1/rooms/${r.id}/join`,{})).status,200);
 const base=`/v1/rooms/${r.id}/roulette`;
 const admin=async(action,extra={})=>{const cfg=(await f.req(p.owner,'GET','/v1/admin/roulette')).data.config;return f.req(p.owner,'POST','/v1/admin/roulette/actions',{requestId:randomUUID(),action,expectedRevision:cfg.revision,...extra});};
 return {f,...p,r,base,admin,spin:(nonce=randomUUID())=>f.req(p.member,'POST',base+'/spin',{requestId:nonce})};
}
test('1.5 weighted boundaries, zero-weight exclusion, secure sample uniqueness and Baghdad midnight',()=>{
 const p=validatePrizes(defaultPrizes);for(const [n,i]of [[0,0],[39,0],[40,1],[99,3]])assert.equal(drawPrize(p,()=>n),i);
 assert.equal(drawPrize([{weight:0},{weight:1}],()=>0),1);assert.throws(()=>validatePrizes(p.map(v=>({...v,weight:0}))));assert.throws(()=>validatePrizes([p[0],p[0]]));
 for(let n=0;n<30;n++){const a=Array.from({length:1000},(_,i)=>i),s=sampleUsers(a,200);assert.equal(new Set(s).size,200);assert.equal(a.length,1000);assert.deepEqual(a,Array.from({length:1000},(_,i)=>i));}
 assert.equal(rouletteDay(Date.parse('2026-10-29T20:59:59.999Z')),'2026-10-29');assert.equal(rouletteDay(Date.parse('2026-10-29T21:00:00.000Z')),'2026-10-30');
});
test('1.5 only app owner controls wheel; unauthenticated, outside-room and wrong-session access is denied',async t=>{
 const {f,owner,member,mod,r,base}=await ready(t);
 for(const a of [member,mod]){assert.equal((await f.req(a,'GET','/v1/admin/roulette')).status,403);assert.equal((await f.req(a,'GET','/v1/admin/roulette/candidates')).status,403);assert.equal((await f.req(a,'POST','/v1/admin/roulette/actions',{requestId:randomUUID(),action:'grant',expectedRevision:0,users:[member.user.id]})).status,403);}
 assert.equal((await f.req(owner,'GET',base)).status,403);assert.equal((await f.req(null,'GET',base)).status,401);
 assert.equal((await f.req(member,'GET',base)).data.config.mode,'everyone');
 const logged=(await f.req(null,'POST','/v1/auth/login',{username:member.user.username,password})).data;
 assert.equal((await f.req(logged,'POST',base+'/spin',{requestId:randomUUID()})).status,403);
});
test('1.5 duplicate spins credit once, survive restart, enforce quotas across rooms, and reject forged outcomes',async t=>{
 const {f,owner,member,r,base,spin}=await ready(t),nonce=randomUUID();
 const rs=await Promise.all([spin(nonce),spin(nonce)]);assert.ok(rs.every(x=>x.status===200),JSON.stringify(rs));assert.equal(rs[0].data.coins,rs[1].data.coins);assert.equal((await f.req(member,'GET',base)).data.remaining,4);
 await f.restart();assert.equal((await spin(nonce)).data.replayed,true);assert.equal((await f.req(member,'GET',base+'/receipts/'+nonce)).data.coins,rs[0].data.coins);
 assert.equal((await f.req(member,'POST',base+'/spin',{requestId:randomUUID(),index:0,coins:9999})).status,400);
 for(let i=0;i<4;i++)assert.equal((await spin()).status,200);assert.equal((await spin()).data.error.code,'ROULETTE_LIMIT');
 const old=(await f.req(member,'GET',`/v1/rooms/${r.id}`)).data.room;
 await f.req(member,'POST',`/v1/rooms/${r.id}/leave`,{identity:old.members.find(m=>m.user.id===member.user.id).identity});
 const other=await f.create(owner);assert.equal((await f.req(member,'POST',`/v1/rooms/${other.id}/join`,{})).status,200);
 assert.equal((await f.req(member,'POST',`/v1/rooms/${other.id}/roulette/spin`,{requestId:nonce})).status,409);
 assert.equal((await f.req(member,'POST',`/v1/rooms/${other.id}/roulette/spin`,{requestId:randomUUID()})).data.error.code,'ROULETTE_LIMIT');
 await f.db.query('UPDATE tomi_roulette_daily SET day=? WHERE user_id=?',['2000-01-01',member.user.id]);assert.equal((await f.req(member,'POST',`/v1/rooms/${other.id}/roulette/spin`,{requestId:randomUUID()})).status,200);
});
test('1.5 selected/public modes and bulk grants/revocations take effect immediately and preserve prior rewards',async t=>{
 const {f,member,mod,base,admin,spin}=await ready(t);
 assert.equal((await admin('configure',{mode:'selected',dailyLimit:7,prizes:defaultPrizes})).status,200);assert.equal((await spin()).status,403);
 assert.equal((await admin('grant',{users:[member.user.username,mod.user.id]})).data.count,2);assert.equal((await spin()).status,200);
 assert.equal((await admin('revoke',{users:[member.user.id,mod.user.username]})).status,200);assert.equal((await spin()).status,403);
 await admin('configure',{mode:'everyone',dailyLimit:7,prizes:defaultPrizes});assert.equal((await spin()).status,403);
 await admin('grant',{users:['@'+member.user.username]});assert.equal((await spin()).status,200);
 assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_roulette_spins WHERE user_id=?',[member.user.id])).rows[0].n),2);
});
test('1.5 contribution distribution is sampled, audited, atomic and idempotent; ranking total differs from pool size',async t=>{
 const {f,owner,member,mod,admin}=await ready(t);
 await f.command(owner,'add_coins',member.user.id,{amount:100});await f.command(owner,'add_coins',mod.user.id,{amount:200});
 const list=(await f.req(owner,'GET','/v1/admin/roulette/candidates?criterion=credits&poolSize=1000')).data;assert.equal(list.total,2);assert.deepEqual(list.items.map(x=>x.credits),[200,100]);
 const cfg=(await f.req(owner,'GET','/v1/admin/roulette')).data.config,body={requestId:randomUUID(),expectedRevision:cfg.revision,action:'random',criterion:'credits',poolSize:1000,count:1};
 const rs=await Promise.all([1,2].map(()=>f.req(owner,'POST','/v1/admin/roulette/actions',body)));assert.ok(rs.every(r=>r.status===200),JSON.stringify(rs));assert.deepEqual(rs[0].data.selectedIds,rs[1].data.selectedIds);assert.ok([member.user.id,mod.user.id].includes(rs[0].data.selectedIds[0]));
 assert.equal(Number((await f.db.query("SELECT COUNT(*) n FROM tomi_admin_audit WHERE action='roulette_random'")).rows[0].n),1);
 assert.equal((await f.req(owner,'POST','/v1/admin/roulette/actions',{...body,count:2})).status,409);assert.equal((await admin('random',{criterion:'credits',poolSize:1000,count:3})).data.error.code,'ROULETTE_POOL');
 const page=(await f.req(owner,'GET','/v1/admin/roulette/candidates?criterion=credits&poolSize=1')).data;assert.equal(page.total,2);assert.equal(page.poolCount,1);
 const before=Number((await f.db.query('SELECT COUNT(*) n FROM tomi_roulette_access')).rows[0].n);assert.equal((await admin('grant',{users:[member.user.id,'doesnotexist15']})).status,404);assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_roulette_access')).rows[0].n),before);
});
test('1.5 server enforces configured prizes and rejects invalid weights, stale revisions and suspended recipients',async t=>{
 const {f,owner,member,mod,admin,spin}=await ready(t),prizes=defaultPrizes.map((p,i)=>({...p,coins:77,weight:i===2?1:0}));
 assert.equal((await admin('configure',{mode:'everyone',dailyLimit:2,prizes})).status,200);const result=await spin();assert.equal(result.data.index,2);assert.equal(result.data.prize.coins,77);assert.equal(result.data.coins,1077);
 assert.equal((await admin('configure',{mode:'everyone',dailyLimit:2,prizes:prizes.map(p=>({...p,weight:0}))})).status,400);
 assert.equal((await f.req(owner,'POST','/v1/admin/roulette/actions',{requestId:randomUUID(),action:'revoke',expectedRevision:0,users:[member.user.id]})).status,409);
 await f.command(owner,'suspend_user',mod.user.id);assert.equal((await admin('grant',{users:[member.user.id,mod.user.id]})).status,409);
});
test('1.5 advanced room levels derive from durable lifetime gifts; free rooms retain no levels',async t=>{
 const {f,member,r}=await ready(t,true);assert.equal(r.hasLevels,true);assert.equal(r.level,1);assert.equal(r.levelNext,1000);
 await f.db.query('INSERT INTO tomi_room_support(id,room_id,sender_id,recipient_id,request_id,gift_id,quantity,unit_price,total,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)',[randomUUID(),r.id,member.user.id,member.user.id,randomUUID(),'diamond',1,5000,5000,new Date().toISOString()]);
 let live=(await f.req(member,'GET',`/v1/rooms/${r.id}`)).data.room;assert.equal(live.level,3);assert.equal(live.levelXp,5000);assert.equal(live.levelNext,15000);
 await f.db.query('UPDATE tomi_room_support SET total=3000000 WHERE room_id=?',[r.id]);await f.restart();live=(await f.req(member,'GET',`/v1/rooms/${r.id}`)).data.room;assert.equal(live.level,10);assert.equal(live.levelNext,null);
 const other=await f.register('freelevels15'),free=(await f.req(other,'POST','/v1/rooms',{requestId:randomUUID(),title:'بدون مستويات',capacity:10,seatCount:4})).data.room;assert.equal(free.hasLevels,false);assert.equal(free.level,null);
});
test('1.5 leaving blocks play and account erasure removes roulette history, usage, access and contribution counters',async t=>{
 const {f,member,r,spin}=await ready(t);assert.equal((await spin()).status,200);
 const room=(await f.req(member,'GET',`/v1/rooms/${r.id}`)).data.room,identity=room.members.find(m=>m.user.id===member.user.id).identity;
 await f.req(member,'POST',`/v1/rooms/${r.id}/leave`,{identity});assert.equal((await spin()).status,403);
 const d=await f.req(member,'POST','/v1/account/deletion',{password,confirmation:'حذف حسابي',requestId:randomUUID(),receiptToken:'a'.repeat(43)});assert.equal(d.status,202,JSON.stringify(d));
 for(const table of ['tomi_roulette_spins','tomi_roulette_daily','tomi_roulette_access','tomi_contribution_credits'])assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM '+table+' WHERE user_id=?',[member.user.id])).rows[0].n),0);
});

test('1.5 cosmetic/charisma/empty prizes award atomically without inventing gift XP, changing avatars or charging coins',async t=>{
 const {f,member,admin,spin}=await ready(t);
 async function forced(p){const prizes=[{id:'chosen',label:'جائزتك',icon:'🎁',coins:0,weight:1,...p},{id:'other',label:'أخرى',icon:'✨',coins:0,weight:0}];assert.equal((await admin('configure',{mode:'everyone',dailyLimit:10,prizes})).status,200);const nonce=randomUUID(),one=await spin(nonce);assert.equal(one.status,200,JSON.stringify(one));assert.equal((await spin(nonce)).data.replayed,true);return one.data;}
 let p=await forced({kind:'charisma',coins:321});assert.equal(p.reward.balance,321);assert.equal(p.coins,1000);
 p=await forced({kind:'frame',styleId:'flame',days:7});const until=p.reward.expiresAt;
 const owned=(await f.db.query("SELECT * FROM tomi_room_cosmetics WHERE user_id=? AND kind='frame'",[member.user.id])).rows[0];assert.equal(owned.style_id,'flame');assert.equal(owned.equipped,0);assert.equal(owned.expires_at,until);
 p=await forced({kind:'entrance',styleId:'comet',days:3});assert.equal(p.reward.kind,'entrance');
 p=await forced({kind:'none'});assert.equal(p.reward.amount,0);assert.equal(p.coins,1000);
 const progress=(await f.db.query('SELECT spent,received FROM tomi_user_progress WHERE user_id=?',[member.user.id])).rows[0];assert.equal(Number(progress.spent),0);assert.equal(Number(progress.received),321);
 assert.equal((await f.req(member,'GET','/v1/me')).data.user.avatarPreset,'initials');
 assert.throws(()=>validatePrizes([{id:'a',label:'x',icon:'✨',coins:0,weight:1,kind:'frame',styleId:'forged',days:30},defaultPrizes[0]]));
 assert.throws(()=>validatePrizes([{id:'a',label:'x',icon:'✨',coins:0,weight:1,kind:'entrance',styleId:'comet',days:999},defaultPrizes[0]]));
});
test('1.5 owner can sample exactly 200 of 1000 ranked contributors, page all 1000, recover the group after restart and revoke it',async t=>{
 const {f,owner,admin}=await ready(t),ids=[],now=new Date().toISOString();
 await f.db.transaction(async db=>{for(let i=0;i<1000;i++){const uid=randomUUID();ids.push(uid);await db.query('INSERT INTO tomi_users(id,username,display_name,password_hash,recovery_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',[uid,'contrib15_'+i,'عضو '+i,'test-only','test-only',now,now]);await db.query('INSERT INTO tomi_contribution_credits(user_id,total) VALUES(?,?)',[uid,i+1]);}});
 const seen=[];let offset=0;
 while(offset!==null){const p=await f.req(owner,'GET',`/v1/admin/roulette/candidates?criterion=credits&poolSize=1000&offset=${offset}`);assert.equal(p.status,200);assert.equal(p.data.total,1000);assert.ok(p.data.items.length<=50);seen.push(...p.data.items.map(x=>x.id));offset=p.data.nextOffset;}
 assert.equal(new Set(seen).size,1000);assert.equal(seen[0],ids.at(-1));
 const result=await admin('random',{criterion:'credits',poolSize:1000,count:200});assert.equal(result.status,200,JSON.stringify(result));assert.equal(new Set(result.data.selectedIds).size,200);assert.ok(result.data.selectedIds.every(id=>ids.includes(id)));
 await f.restart();const groups=(await f.req(owner,'GET','/v1/admin/roulette/groups')).data.items;assert.equal(groups[0].receiptId,result.data.receiptId);assert.deepEqual(groups[0].selectedIds,result.data.selectedIds);
 assert.equal((await admin('revoke',{users:groups[0].selectedIds})).data.count,200);
 assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_roulette_access WHERE allowed=1')).rows[0].n),0);
});
test('1.5 spin, erasure and group update cannot deadlock or resurrect an erased recipient on PostgreSQL',async t=>{
 const {f,owner,member,admin,spin}=await ready(t);
 if(f.db.dialect==='postgres'){
  let release;const released=new Promise(r=>release=r);let locked;const acquired=new Promise(r=>locked=r);
  const held=f.db.transaction(async db=>{await db.query('SELECT pg_advisory_xact_lock(174115,1)');locked();await released;});await acquired;
  t.after(()=>release());
  async function waiting(fragment){const deadline=Date.now()+5000;while(Date.now()<deadline){const n=Number((await f.db.query("SELECT COUNT(*) n FROM pg_stat_activity WHERE wait_event='advisory' AND query LIKE ?",['%'+fragment+'%'])).rows[0].n);if(n>0)return;await new Promise(r=>setTimeout(r,15));}assert.fail('Expected advisory gate wait: '+fragment);}
  const turn=spin();await waiting('pg_advisory_xact_lock_shared(174115,1)');
  const erased=f.req(member,'POST','/v1/account/deletion',{password,confirmation:'حذف حسابي',requestId:randomUUID(),receiptToken:'b'.repeat(43)});await waiting('pg_advisory_xact_lock(172994,hashtext(');
  const group=admin('grant',{users:[member.user.id]});await waiting('pg_advisory_xact_lock_shared(172994,hashtext(');
  release();await held;const [a,b,c]=await Promise.all([turn,erased,group]);assert.equal(a.status,200,JSON.stringify(a));assert.equal(b.status,202,JSON.stringify(b));assert.equal(c.status,409,JSON.stringify(c));
 }else{
  const erased=await f.req(member,'POST','/v1/account/deletion',{password,confirmation:'حذف حسابي',requestId:randomUUID(),receiptToken:'b'.repeat(43)});assert.equal(erased.status,202);assert.equal((await admin('grant',{users:[member.user.id]})).status,409);
 }
 assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_roulette_access WHERE user_id=?',[member.user.id])).rows[0].n),0);
});
