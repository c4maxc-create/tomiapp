import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture,people,password} from './fixtures/platform-api.mjs';

test('1.4 owner balance adjustments are atomic, bounded, audited and idempotent under concurrent retry and restart',async t=>{
 const f=await fixture(t),{owner,member,mod}=await people(f),requestId=randomUUID();
 for(const a of [member,mod])assert.equal((await f.command(a,'add_coins',member.user.id,{amount:500})).status,403);
 const results=await Promise.all([1,2].map(()=>f.command(owner,'add_coins',member.user.id,{amount:500,requestId})));
 assert.ok(results.every(x=>x.status===200),JSON.stringify(results));assert.equal(results[0].data.receiptId,results[1].data.receiptId);assert.equal(await f.auditCount(),1);
 const coins=async()=>Number((await f.db.query('SELECT coins FROM tomi_room_wallets WHERE user_id=?',[member.user.id])).rows[0].coins);
 assert.equal(await coins(),1500);
 assert.equal((await f.command(owner,'withdraw_coins',member.user.id,{amount:200,expectedRevision:1})).status,200);assert.equal(await coins(),1300);
 assert.equal((await f.command(owner,'withdraw_coins',member.user.id,{amount:1400,expectedRevision:2})).data.error.code,'ADMIN_BALANCE');
 assert.equal((await f.command(owner,'add_coins',member.user.id,{amount:5})).status,409);
 const details=JSON.parse((await f.db.query("SELECT details FROM tomi_admin_audit WHERE action='withdraw_coins'")).rows[0].details);assert.equal(details.before.coins,1500);assert.equal(details.after.coins,1300);
 assert.equal((await f.command(owner,'add_coins',owner.user.id,{amount:1})).status,200);
 await f.restart();assert.equal((await f.command(owner,'add_coins',member.user.id,{amount:500,requestId})).data.replayed,true);assert.equal(await coins(),1300);
 assert.equal((await f.command(owner,'add_coins',member.user.id,{amount:501,requestId})).status,409);
});
test('1.4 charisma withdrawal preserves lifetime gift history and sender XP while new self gifts add normally',async t=>{
 const f=await fixture(t),{owner,member}=await people(f);
 const room=(await f.req(member,'POST','/v1/rooms',{requestId:randomUUID(),title:'غرفة الكارزما',capacity:10,seatCount:4})).data.room;
 await f.req(member,'POST',`/v1/rooms/${room.id}/join`,{});
 const gift=()=>f.req(member,'POST',`/v1/rooms/${room.id}/gift`,{requestId:randomUUID(),giftId:'diamond',quantity:1,recipientId:member.user.id});
 assert.equal((await gift()).status,200);
 const before=(await f.req(member,'GET','/v1/me')).data.user.identity;
 assert.equal((await f.command(owner,'withdraw_charisma',member.user.id,{amount:40})).status,200);
 assert.equal((await f.command(owner,'add_charisma',member.user.id,{amount:15,expectedRevision:1})).status,200);
 assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_room_all_gifts WHERE sender_id=?',[member.user.id])).rows[0].n),1);
 await f.restart();const after=(await f.req(member,'GET','/v1/me')).data.user.identity;assert.equal(after.charisma,before.charisma-25);assert.equal(after.xp,before.xp);
 assert.equal((await gift()).status,200);assert.equal((await f.req(member,'GET','/v1/me')).data.user.identity.charisma,before.charisma*2-25);
});
test('1.4 scoped moderators can review reports and ban members only when granted; protected staff and owner remain protected',async t=>{
 const f=await fixture(t),{owner,member,mod}=await people(f),other=await f.register('staffother14');
 await f.db.query("INSERT INTO tomi_platform_roles(user_id,role,revision,granted_by,updated_at) VALUES(?,'moderator',0,?,?)",[mod.user.id,owner.user.id,new Date().toISOString()]);
 const legacy=(await f.req(mod,'GET','/v1/moderation/access')).data;assert.ok(legacy.permissions.includes('reports'));assert.ok(!legacy.permissions.includes('bans'));
 assert.equal((await f.command(owner,'grant_moderator',mod.user.id,{permissions:['reports','bans']})).status,200);
 assert.deepEqual((await f.req(mod,'GET','/v1/moderation/access')).data.permissions,['reports','bans']);
 for(const p of ['/v1/admin/reports','/v1/admin/users'])assert.equal((await f.req(mod,'GET',p)).status,200,p);
 for(const p of ['/v1/admin/metrics','/v1/admin/audit','/v1/admin/rooms','/v1/admin/staff'])assert.equal((await f.req(mod,'GET',p)).status,403,p);
 assert.equal((await f.command(mod,'suspend_user',member.user.id)).status,200);
 assert.equal((await f.command(mod,'restore_user',member.user.id,{expectedRevision:1})).status,200);
 assert.equal((await f.command(mod,'add_coins',member.user.id,{amount:1})).status,403);
 assert.equal((await f.command(mod,'grant_moderator',other.user.id,{permissions:['bans']})).status,403);
 assert.equal((await f.command(mod,'suspend_user',owner.user.id)).status,403);
 await f.command(owner,'grant_moderator',other.user.id,{permissions:['reports']});assert.equal((await f.command(mod,'suspend_user',other.user.id)).status,403);
 assert.equal((await f.command(owner,'grant_moderator',mod.user.id,{permissions:['reports'],expectedRevision:1})).status,200);
 assert.equal((await f.command(mod,'suspend_user',member.user.id,{expectedRevision:2})).status,403);
 await f.restart();assert.deepEqual((await f.req(mod,'GET','/v1/moderation/access')).data.permissions,['reports']);
 assert.equal((await f.command(owner,'revoke_moderator',mod.user.id,{expectedRevision:2})).status,200);assert.equal((await f.req(mod,'GET','/v1/admin/reports')).status,403);
});
test('1.4 invalid privilege escalation and malformed/overflowing amounts leave data unchanged',async t=>{
 const f=await fixture(t),{owner,member,mod}=await people(f);
 for(const permissions of [['economy'],['owner'],['reports','reports'],['staff']])assert.equal((await f.command(owner,'grant_moderator',mod.user.id,{permissions})).status,400);
 for(const amount of [-1,0,0.5,'100',9000000000001])assert.equal((await f.command(owner,'add_coins',member.user.id,{amount})).status,400);
 assert.equal((await f.command(owner,'add_coins',member.user.id,{amount:9000000000000})).status,409);assert.equal(await f.auditCount(),0);
 assert.equal((await f.req(owner,'GET','/v1/admin/users?q=member12')).data.items[0].state.coins,1000);
});
test('1.4 special-account badge survives restart and can be revoked without granting platform permissions',async t=>{
 const f=await fixture(t),{owner,member,mod}=await people(f);
 assert.equal((await f.command(mod,'mark_special',member.user.id)).status,403);assert.equal((await f.command(owner,'mark_special',member.user.id)).status,200);
 assert.equal((await f.req(mod,'GET','/v1/users/'+member.user.id)).data.user.identity.special,true);
 assert.equal((await f.req(member,'GET','/v1/moderation/access')).data.role,'member');await f.restart();
 assert.equal((await f.req(member,'GET','/v1/me')).data.user.identity.special,true);
 assert.equal((await f.command(owner,'unmark_special',member.user.id,{expectedRevision:1})).status,200);assert.equal((await f.req(member,'GET','/v1/me')).data.user.identity.special,false);
});
test('1.4 managed-account creation preserves owner session, hides credentials from audit/receipts and never resets a password on retry',async t=>{
 const f=await fixture(t),{owner,member}=await people(f),target=randomUUID(),requestId=randomUUID(),password='managed account secret14';
 const body={requestId,username:'managed14',displayName:'حساب مميز',password,special:true};
 assert.equal((await f.command(member,'create_account',target,body)).status,403);
 const result=await f.command(owner,'create_account',target,body);assert.equal(result.status,200,JSON.stringify(result));assert.ok(result.data.recoveryCode);assert.equal(result.data.token,undefined);
 const replay=await f.command(owner,'create_account',target,{...body,password:'different request password14'});assert.equal(replay.data.replayed,true);assert.equal(replay.data.recoveryCode,undefined);
 const logged=await f.req(null,'POST','/v1/auth/login',{username:'managed14',password});assert.equal(logged.status,200);assert.equal(logged.data.user.identity.special,true);
 assert.equal((await f.req(owner,'GET','/v1/moderation/access')).data.role,'owner');
 const text=JSON.stringify((await f.db.query('SELECT * FROM tomi_admin_requests')).rows)+JSON.stringify((await f.db.query('SELECT * FROM tomi_admin_audit')).rows);assert.ok(!text.includes(password)&&!text.includes(result.data.recoveryCode));
 assert.equal((await f.command(owner,'create_account',randomUUID(),{...body,requestId:randomUUID()})).status,409);
 const state=(await f.req(owner,'GET','/v1/admin/users?q=managed14')).data.items[0].state;assert.equal(state.special,true);assert.equal(state.role,'member');
});
test('1.4 posts-only moderators can manage posts independently of report permissions',async t=>{
 const f=await fixture(t),{owner,member,mod}=await people(f),post=await f.post(member);
 await f.command(owner,'grant_moderator',mod.user.id,{permissions:['posts']});
 assert.equal((await f.req(mod,'GET','/v1/admin/reports')).status,403);
 const list=await f.req(mod,'GET','/v1/admin/posts');assert.equal(list.status,200,JSON.stringify(list));assert.equal(list.data.items[0].id,post.id);
 assert.equal((await f.command(mod,'hide_post',post.id)).status,200);
 assert.equal((await f.req(mod,'GET','/v1/admin/posts')).data.items[0].hidden,true);
});

test('1.4 privacy erasure removes special status and delegated permissions; owner cannot recreate erased account state',async t=>{
 const f=await fixture(t),{owner,member}=await people(f);
 await f.command(owner,'mark_special',member.user.id);
 await f.command(owner,'grant_moderator',member.user.id,{permissions:['reports']});
 const result=await f.req(member,'POST','/v1/account/deletion',{requestId:randomUUID(),receiptToken:'a'.repeat(43),confirmation:'حذف حسابي',password});
 assert.equal(result.status,202,JSON.stringify(result));
 for(const table of ['tomi_staff_permissions','tomi_admin_profiles'])assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM '+table+' WHERE user_id=?',[member.user.id])).rows[0].n),0);
 assert.equal((await f.command(owner,'mark_special',member.user.id,{expectedRevision:1})).status,410);
});
