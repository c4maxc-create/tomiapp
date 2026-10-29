import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {once} from 'node:events';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {openDatabase} from '../src/database.mjs';
import {createApp} from '../src/app.mjs';
import {roomProviderFromEnvironment} from '../src/room_provider.mjs';
import {TokenVerifier} from 'livekit-server-sdk';

import {fixture} from './fixtures/room-api.mjs';
test('rooms persist; creation and joins are idempotent and session-bound; listeners cannot moderate',async t=>{
 const api=await fixture(t),a=await api.register('room_owner'),b=await api.register('room_guest');
 const requestId=randomUUID(),r=await api.create(a,{requestId});assert.equal((await api.create(a,{requestId})).id,r.id);
 assert.equal((await api.request('GET','/v1/rooms')).status,401);
 const owner=await api.act(a,r,'join'),guest=await api.act(b,r,'join');assert.equal(owner.data.room.members[0].seat,-1);assert.equal(guest.data.connection.publish,false);
 assert.equal((await api.act(b,r,'join')).data.connection.identity,guest.data.connection.identity);
 assert.equal((await api.act(b,r,'moderate',{targetId:a.user.id,operation:'kick'})).status,403);
 const other=(await api.request('POST','/v1/auth/login',{username:'room_guest',password:'test-only rooms passphrase'})).data;
 assert.equal((await api.act(other,r,'join')).data.error.code,'ROOM_OTHER_DEVICE');
 await api.restart();assert.equal((await api.get(a,r)).memberCount,2);
 assert.equal((await api.act(b,r,'leave',{identity:guest.data.connection.identity})).status,200);assert.equal((await api.get(a,r)).memberCount,1);
});
test('mic requests, approval, mute, roles and kick enforce server permissions and protect owner',async t=>{
 const api=await fixture(t),a=await api.register('stage_owner'),b=await api.register('stage_guest'),c=await api.register('stage_third'),r=await api.create(a);
 await api.act(a,r,'join');await api.act(b,r,'join');await api.act(c,r,'join');
 const mod=(as,target,operation,seat)=>api.act(as,r,'moderate',{targetId:target.user.id,operation,...(seat===undefined?{}:{seat})});
 assert.equal((await mod(a,b,'approve')).status,409);await api.act(b,r,'request-mic');
 let live=(await mod(a,b,'approve',1)).data.room;assert.equal(live.members.find(m=>m.user.id===b.user.id).micAllowed,true);
 assert.ok(api.calls.some(v=>v[0]==='permission'&&v[2]));
 live=(await mod(a,b,'mute')).data.room;assert.equal(live.members.find(m=>m.user.id===b.user.id).micAllowed,false);assert.equal(api.calls.at(-1)[2],false);
 await mod(a,b,'allow-mic');await mod(a,b,'promote');assert.equal((await mod(b,c,'promote')).status,403);assert.equal((await mod(b,a,'kick')).status,403);
 await api.act(c,r,'request-mic');assert.equal((await mod(b,c,'approve',1)).status,409);assert.equal((await mod(b,c,'approve',2)).status,200);
 assert.equal((await mod(b,c,'kick')).status,200);assert.equal((await api.act(c,r,'join')).data.error.code,'ROOM_KICKED');
 assert.equal((await api.act(b,r,'close')).status,403);await mod(a,b,'demote');assert.equal((await mod(b,c,'kick')).status,403);
});
test('provider outages keep durable moderation jobs and restart replays desired permissions',async t=>{
 const api=await fixture(t),a=await api.register('retry_owner'),b=await api.register('retry_guest'),r=await api.create(a);
 await api.act(a,r,'join');await api.act(b,r,'join');await api.act(b,r,'request-mic');
 api.down=true;const r1=await api.act(a,r,'moderate',{targetId:b.user.id,operation:'approve'});assert.equal(r1.data.room.moderationPending,true);
 await api.act(a,r,'moderate',{targetId:b.user.id,operation:'kick'});await api.restart();
 assert.ok(Number((await api.db.query('SELECT COUNT(*) n FROM tomi_voice_jobs')).rows[0].n)>0);
 api.down=false;await api.server.flushRooms();assert.equal(api.calls.at(-1)[0],'remove');assert.equal((await api.get(a,r)).moderationPending,false);
});
test('capacity and one-room/call exclusivity are atomic; no leaked duplicate membership',async t=>{
 const api=await fixture(t),a=await api.register('limit_owner'),b=await api.register('limit_guest'),c=await api.register('limit_third'),r=await api.create(a,{capacity:2,seatCount:2});
 await api.act(a,r,'join');const joins=await Promise.all([api.act(b,r,'join'),api.act(c,r,'join')]);assert.deepEqual(joins.map(j=>j.status).sort(),[200,409]);
 const another=await api.create(b);assert.equal((await api.act(a,another,'join')).data.error.code,'ROOM_BUSY');
 const thread=(await api.request('POST','/v1/chats',{userId:b.user.id},a.token)).data.conversation;
 assert.equal((await api.request('POST','/v1/calls',{conversationId:thread.id,requestId:randomUUID(),kind:'audio'},a.token)).data.error.code,'ROOM_BUSY');
});
test('expired heartbeat and revoked sessions leave rooms; empty room preserves its identity and settings',async t=>{
 const api=await fixture(t),a=await api.register('expire_owner'),b=await api.register('expire_guest'),r=await api.create(a);
 const own=await api.act(a,r,'join');await api.act(b,r,'join');await api.request('POST','/v1/auth/logout',{},b.token);assert.equal((await api.get(a,r)).memberCount,1);
 await api.db.query('UPDATE tomi_voice_members SET last_seen=? WHERE room_id=?',['2000-01-01T00:00:00.000Z',r.id]);await api.server.sweepRooms();assert.equal((await api.get(a,r)).memberCount,0);
 await api.db.query('UPDATE tomi_voice_rooms SET empty_since=? WHERE id=?',['2000-01-01T00:00:00.000Z',r.id]);await api.server.sweepRooms();assert.equal((await api.get(a,r)).state,'open');
 assert.equal((await api.act(a,r,'join')).status,200);assert.ok(!api.calls.some(v=>v[0]==='close'));assert.ok(own.data.connection.identity);
});
test('blocked peers cannot share a room; disabled setup preserves all other APIs',async t=>{
 const api=await fixture(t),a=await api.register('block_owner'),b=await api.register('block_guest'),r=await api.create(a);await api.act(a,r,'join');
 await api.request('PUT','/v1/chat/blocks/'+b.user.id,{blocked:true},a.token);assert.equal((await api.act(b,r,'join')).data.error.code,'ROOM_BLOCKED');
 assert.equal((await api.request('GET','/v1/rooms',null,b.token)).data.rooms.length,0);
 const off=await fixture(t,{disabled:true}),x=await off.register('disabled_rooms');assert.equal((await off.request('GET','/v1/rooms/settings',null,x.token)).data.configured,false);
 assert.equal((await off.request('POST','/v1/rooms',{requestId:randomUUID(),title:'غرفة',capacity:10,seatCount:4},x.token)).data.error.code,'ROOMS_DISABLED');
 assert.equal((await off.request('GET','/v1/me',null,x.token)).status,200);
});
test('Cloud grants allow only microphone, never admin/data/camera; incomplete and self-hosted settings fail',async()=>{
 assert.equal(roomProviderFromEnvironment({}),null);assert.throws(()=>roomProviderFromEnvironment({ROOM_LIVEKIT_URL:'wss://test.livekit.cloud'}));
 const env={ROOM_LIVEKIT_URL:'wss://test.livekit.cloud',ROOM_LIVEKIT_API_KEY:'test-only-key',ROOM_LIVEKIT_API_SECRET:'test-only-secret-'.repeat(3)};
 assert.throws(()=>roomProviderFromEnvironment({...env,ROOM_LIVEKIT_URL:'wss://private.example.com'}));
 const provider=roomProviderFromEnvironment(env,{client:{}}),r={id:randomUUID()},m={identity:randomUUID(),seat:null,mic_allowed:0};
 for(const publish of [false,true]){
  const grant=await provider.grant(r,{...m,seat:publish?1:null,mic_allowed:publish?1:0});
  const payload=await new TokenVerifier(env.ROOM_LIVEKIT_API_KEY,env.ROOM_LIVEKIT_API_SECRET).verify(grant.token);
  assert.equal(payload.video.canPublish,publish);assert.deepEqual(payload.video.canPublishSources,['microphone']);assert.equal(payload.video.canPublishData,false);assert.ok(!payload.video.roomAdmin);assert.equal(payload.sub,m.identity);assert.ok(payload.exp-Math.floor(Date.now()/1000)<=60);
  assert.ok(!JSON.stringify(grant).includes(env.ROOM_LIVEKIT_API_SECRET));
 }
});
test('owner and moderators can return to an empty mic seat; listeners cannot claim it',async t=>{
 const api=await fixture(t),a=await api.register('return_owner'),b=await api.register('return_guest'),r=await api.create(a);
 await api.act(a,r,'join');await api.act(b,r,'join');await api.act(a,r,'leave-seat');
 assert.equal((await api.act(b,r,'take-seat')).status,403);
 const claim=(await api.act(a,r,'take-seat')).data.room;assert.equal(claim.members.find(m=>m.user.id===a.user.id).seat,-1);
 await api.act(a,r,'moderate',{targetId:b.user.id,operation:'promote'});
 assert.equal((await api.act(b,r,'take-seat')).status,200);
});
test('a stale leave cannot remove a new room connection and private calls exclude joining',async t=>{
 const api=await fixture(t),a=await api.register('stale_owner'),b=await api.register('stale_guest'),r=await api.create(a);
 const one=(await api.act(a,r,'join')).data.connection;await api.act(a,r,'leave',{identity:one.identity});
 const two=(await api.act(a,r,'join')).data.connection;assert.notEqual(two.identity,one.identity);
 await api.act(a,r,'leave',{identity:one.identity});assert.equal((await api.get(a,r)).memberCount,1);
 await api.act(a,r,'leave',{identity:two.identity});
 const thread=(await api.request('POST','/v1/chats',{userId:b.user.id},a.token)).data.conversation;
 const call=await api.request('POST','/v1/calls',{conversationId:thread.id,requestId:randomUUID(),kind:'audio'},a.token);assert.equal(call.status,201);
 assert.equal((await api.act(b,r,'join')).data.error.code,'CALL_BUSY');
});
test('0.7 appends voice rooms without changing the accepted 0.6.1 schema',async()=>{
 const {readFile}=await import('node:fs/promises');
 const old=await readFile(new URL('./fixtures/schema-0.6.1.sql',import.meta.url),'utf8');
 const current=await readFile(new URL('../schema.sql',import.meta.url),'utf8');
 assert.ok(current.startsWith(old.trimEnd()));
});
test('closing retains every token removal until acknowledged, even after SFU DeleteRoom',async t=>{
 const api=await fixture(t),a=await api.register('close_owner'),b=await api.register('close_guest'),r=await api.create(a);
 const one=(await api.act(a,r,'join')).data.connection,two=(await api.act(b,r,'join')).data.connection;
 await api.act(a,r,'close');
 assert.equal(Number((await api.db.query('SELECT COUNT(*) n FROM tomi_voice_jobs WHERE room_id=?',[r.id])).rows[0].n),0);
 assert.equal(Number((await api.db.query('SELECT needs_delete FROM tomi_voice_rooms WHERE id=?',[r.id])).rows[0].needs_delete),0);
 await api.server.flushRooms();
 assert.equal(Number((await api.db.query('SELECT COUNT(*) n FROM tomi_voice_jobs WHERE room_id=?',[r.id])).rows[0].n),0);
 assert.ok([one.identity,two.identity].every(id=>api.calls.some(v=>v[0]==='remove'&&v[1]===id)));
 assert.equal(Number((await api.db.query('SELECT needs_delete FROM tomi_voice_rooms WHERE id=?',[r.id])).rows[0].needs_delete),0);
});

test('owner seat and capacity stay reserved while absent and every reentry returns to the same place',async t=>{
 const api=await fixture(t),a=await api.register('fixed_owner'),b=await api.register('fixed_guest'),c=await api.register('fixed_third'),r=await api.create(a,{capacity:2,seatCount:2});
 const one=await api.act(a,r,'join');assert.equal(one.data.room.members[0].seat,-1);
 await api.act(a,r,'leave',{identity:one.data.connection.identity});await api.act(b,r,'join');
 assert.equal((await api.act(c,r,'join')).data.error.code,'ROOM_FULL');
 const two=await api.act(a,r,'join');assert.equal(two.data.room.members.find(m=>m.user.id===a.user.id).seat,-1);
 await api.act(a,r,'moderate',{targetId:b.user.id,operation:'promote'});
 assert.equal((await api.act(b,r,'take-seat',{seat:-1})).data.error.code,'ROOM_RESERVED_SEAT');
 await api.act(b,r,'request-mic');assert.equal((await api.act(a,r,'moderate',{targetId:b.user.id,operation:'approve',seat:-1})).status,403);
 assert.equal((await api.act(a,r,'seat-control',{seat:-1,operation:'unlock'})).status,403);
 await api.act(a,r,'leave-seat');const muted=await api.get(a,r);assert.equal(muted.members.find(m=>m.user.id===a.user.id).seat,-1);
 assert.equal(muted.members.find(m=>m.user.id===a.user.id).micAllowed,false);
});
test('upgrading a seated 0.7 owner changes only their seat and preserves the SFU identity',async t=>{
 const api=await fixture(t),a=await api.register('upgrade_owner'),r=await api.create(a),one=await api.act(a,r,'join');
 await api.db.query('UPDATE tomi_voice_members SET seat=0 WHERE room_id=? AND user_id=?',[r.id,a.user.id]);
 const updated=await api.get(a,r);assert.equal(updated.members[0].seat,-1);assert.equal(updated.members[0].identity,one.data.connection.identity);
 const old=await (await import('node:fs/promises')).readFile(new URL('./fixtures/schema-0.7.sql',import.meta.url),'utf8');
 const fresh=await (await import('node:fs/promises')).readFile(new URL('../schema.sql',import.meta.url),'utf8');assert.ok(fresh.startsWith(old.trimEnd()));
});
test('gifts debit exactly once, persist a receipt and account support across restart, and reject changed retries',async t=>{
 const api=await fixture(t),a=await api.register('gift_owner'),b=await api.register('gift_guest'),r=await api.create(a);
 await api.act(a,r,'join');await api.act(b,r,'join');const body={requestId:randomUUID(),recipientId:b.user.id,giftId:'diamond',quantity:3};
 const one=await api.act(a,r,'gift',body);assert.equal(one.status,200,JSON.stringify(one.data));assert.equal(one.data.wallet.coins,700);
 assert.equal(one.data.room.hasLevels,true);assert.equal(one.data.room.features.level,undefined);assert.equal(one.data.room.features.xp,undefined);
 const replay=await api.act(a,r,'gift',body);assert.equal(replay.data.receiptId,one.data.receiptId);assert.equal(replay.data.wallet.coins,700);
 assert.equal((await api.act(a,r,'gift',{...body,quantity:4})).data.error.code,'REQUEST_CHANGED');
 await api.restart();const live=await api.get(b,r);assert.equal(live.features.xp,undefined);assert.equal(live.features.events.filter(e=>e.kind==='gift').length,1);
 assert.equal((await api.request('GET','/v1/rooms/wallet',null,a.token)).data.wallet.coins,700);
 const ranking=await api.request('GET',`/v1/rooms/${r.id}/ranking`,null,b.token);assert.equal(ranking.data.leaders[0].points,300);
});
test('simultaneous gift sends cannot overspend; failure leaves no receipt, XP or feed entry',async t=>{
 const api=await fixture(t),a=await api.register('race_owner'),b=await api.register('race_guest'),r=await api.create(a);
 await api.act(a,r,'join');await api.act(b,r,'join');
 const results=await Promise.all(Array.from({length:2},()=>api.act(a,r,'gift',{requestId:randomUUID(),recipientId:b.user.id,giftId:'rocket',quantity:1})));
 assert.deepEqual(results.map(v=>v.status).sort(),[200,409]);assert.equal(results.find(v=>v.status===409).data.error.code,'ROOM_COINS_LOW');
 const live=await api.get(a,r);assert.equal(live.features.xp,undefined);assert.equal(live.features.events.filter(e=>e.kind==='gift').length,1);
 assert.equal((await api.request('GET','/v1/rooms/wallet',null,a.token)).data.wallet.coins,0);
});
test('gifts require active membership and a present recipient; values and wallet claims are server controlled',async t=>{
 const api=await fixture(t),a=await api.register('guard_owner'),b=await api.register('guard_guest'),r=await api.create(a);
 await api.act(a,r,'join');let body={requestId:randomUUID(),recipientId:b.user.id,giftId:'rose',quantity:1};
 assert.equal((await api.act(a,r,'gift',body)).data.error.code,'ROOM_RECIPIENT_LEFT');assert.equal((await api.act(b,r,'gift',{...body,recipientId:a.user.id})).status,403);
 await api.act(b,r,'join');
 for(const patch of [{quantity:0},{quantity:100},{giftId:'free'},{quantity:1.5},{price:0}])assert.equal((await api.act(a,r,'gift',{...body,...patch})).status,400);
 const claims=await Promise.all([api.request('POST','/v1/rooms/wallet/claim',{},a.token),api.request('POST','/v1/rooms/wallet/claim',{},a.token)]);
 assert.ok(claims.every(v=>v.data.claimed===false));
 await api.db.query('UPDATE tomi_room_wallets SET next_claim=? WHERE user_id=?',['2000-01-01T00:00:00.000Z',a.user.id]);
 const later=await Promise.all([api.request('POST','/v1/rooms/wallet/claim',{},a.token),api.request('POST','/v1/rooms/wallet/claim',{},a.token)]);
 assert.equal(later.filter(v=>v.data.claimed).length,1);assert.equal(later[0].data.wallet.coins<=1500,true);
 assert.equal((await api.request('GET','/v1/rooms/wallet',null,a.token)).data.wallet.coins,1500);
});
test('all ten level boundaries advance precisely and level ten is capped while XP keeps accumulating',async()=>{
 const {roomLevel,levelThresholds}=await import('../src/room_catalog.mjs');
 assert.equal(roomLevel(0).level,1);
 for(let i=1;i<10;i++){assert.equal(roomLevel(levelThresholds[i]-1).level,i);const r=roomLevel(levelThresholds[i]);assert.equal(r.level,i+1);assert.equal(r.progress,i===9?1:0);}
 assert.equal(roomLevel(999999).level,10);assert.equal(roomLevel(999999).remaining,0);assert.equal(roomLevel(999999).next,null);
});
test('owner settings persist, password is hashed, only owner edits, and public chat obeys room switches',async t=>{
 const api=await fixture(t),a=await api.register('option_owner'),b=await api.register('option_guest'),r=await api.create(a);await api.act(a,r,'join');
 let live=await api.act(a,r,'settings',{title:'أهل السالفة',announcement:'هلا بالكل',background:'dusk',theme:'rose',companionEnabled:false,password:'test-room-pass',chatDisabled:true});assert.equal(live.status,200,JSON.stringify(live.data));
 assert.equal(live.data.room.title,'أهل السالفة');assert.ok(!JSON.stringify(live.data).includes('test-room-pass'));
 const stored=(await api.db.query('SELECT password_hash FROM tomi_room_options WHERE room_id=?',[r.id])).rows[0].password_hash;assert.match(stored,/^scrypt\$/);
 assert.equal((await api.act(b,r,'join')).data.error.code,'ROOM_PASSWORD');assert.equal((await api.act(b,r,'join',{password:'wrong'})).status,403);
 assert.equal((await api.act(b,r,'join',{password:'test-room-pass'})).status,200);
 assert.equal((await api.act(b,r,'settings',{chatDisabled:false})).status,403);
 assert.equal((await api.act(b,r,'message',{requestId:randomUUID(),text:'هلا'})).data.error.code,'ROOM_CHAT_DISABLED');
 await api.act(a,r,'settings',{chatDisabled:false,password:''});const msg={requestId:randomUUID(),text:'مرحبا بالجميع'};
 assert.equal((await api.act(b,r,'message',msg)).status,200);assert.equal((await api.act(b,r,'message',msg)).status,200);
 assert.equal((await api.act(b,r,'message',{...msg,text:'changed'})).data.error.code,'REQUEST_CHANGED');
 await api.restart();const saved=await api.get(a,r);assert.equal(saved.features.background,'dusk');assert.equal(saved.features.passwordRequired,false);
 assert.equal(saved.features.events.filter(e=>e.kind==='message').length,1);assert.equal(saved.features.announcement,'هلا بالكل');
});
test('seat locks, seat mute and explicit invitations apply on server, never permitting the owner seat',async t=>{
 const api=await fixture(t),a=await api.register('seat_owner'),b=await api.register('seat_guest'),r=await api.create(a);await api.act(a,r,'join');await api.act(b,r,'join');await api.act(b,r,'request-mic');
 await api.act(a,r,'seat-control',{seat:0,operation:'lock'});
 assert.equal((await api.act(a,r,'moderate',{targetId:b.user.id,operation:'approve',seat:0})).data.error.code,'ROOM_SEAT_LOCKED');
 assert.equal((await api.act(b,r,'seat-control',{seat:0,operation:'unlock'})).status,403);
 assert.equal((await api.act(a,r,'invite',{targetId:b.user.id,seat:-1})).status,403);
 assert.equal((await api.act(a,r,'invite',{targetId:b.user.id,seat:-2})).status,200);
 assert.equal((await api.get(b,r)).features.invitation.seat,-2);
 let live=await api.act(b,r,'answer-invite',{accept:true});assert.equal(live.data.room.members.find(m=>m.user.id===b.user.id).seat,-2);
 await api.act(a,r,'seat-control',{seat:-2,operation:'mute'});assert.equal((await api.get(b,r)).members.find(m=>m.user.id===b.user.id).micAllowed,false);
 assert.equal((await api.act(a,r,'moderate',{targetId:b.user.id,operation:'allow-mic'})).data.error.code,'ROOM_SEAT_MUTED');
 await api.act(a,r,'seat-control',{seat:-2,operation:'allow'});assert.equal((await api.get(b,r)).members.find(m=>m.user.id===b.user.id).micAllowed,true);
 const c=await api.register('seat_other_mod');await api.act(c,r,'join');
 await api.act(a,r,'moderate',{targetId:b.user.id,operation:'promote'});await api.act(a,r,'moderate',{targetId:c.user.id,operation:'promote'});
 assert.equal((await api.act(c,r,'seat-control',{seat:-2,operation:'mute'})).status,403);
 await api.act(a,r,'settings',{companionEnabled:false});assert.equal((await api.get(b,r)).members.find(m=>m.user.id===b.user.id).seat,null);
 assert.equal((await api.act(a,r,'invite',{targetId:b.user.id,seat:-2})).status,403);
});
test('blacklist unban, offline moderator revocation and audit log require owner authority',async t=>{
 const api=await fixture(t),a=await api.register('admin_owner'),b=await api.register('admin_guest'),r=await api.create(a);await api.act(a,r,'join');const guest=await api.act(b,r,'join');
 await api.act(a,r,'moderate',{targetId:b.user.id,operation:'promote'});await api.act(b,r,'leave',{identity:guest.data.connection.identity});
 let admin=(await api.request('GET',`/v1/rooms/${r.id}/administration`,null,a.token)).data;assert.equal(admin.members[0].role,'moderator');
 await api.act(a,r,'administration',{targetId:b.user.id,operation:'revoke-mod'});await api.act(b,r,'join');
 assert.equal((await api.request('GET',`/v1/rooms/${r.id}/administration`,null,b.token)).status,403);
 await api.act(a,r,'moderate',{targetId:b.user.id,operation:'kick'});assert.equal((await api.act(b,r,'join')).status,403);
 await api.act(a,r,'administration',{targetId:b.user.id,operation:'unban'});assert.equal((await api.act(b,r,'join')).status,200);
 admin=(await api.request('GET',`/v1/rooms/${r.id}/administration`,null,a.token)).data;assert.ok(admin.audit.some(e=>e.action==='unban'));assert.ok(admin.audit.some(e=>e.action==='revoke-mod'));
});
test('room images enforce scope and ownership, attach once, obey image disable and safely replace',async t=>{
 let verifies=0;const storage={readUrl:key=>'https://private.example.test/'+key,verify:async()=>{verifies++;return {width:100,height:120};},delete:async()=>{}};
 const api=await fixture(t,{storage}),a=await api.register('image_owner'),b=await api.register('image_guest'),r=await api.create(a);
 await api.act(a,r,'join');await api.act(b,r,'join');
 async function upload(user,prefix='posts'){
  const id=randomUUID();await api.db.query('INSERT INTO tomi_image_uploads(id,user_id,object_key,content_type,byte_length,content_md5,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?)',
   [id,user.user.id,`tomi/${prefix}/${user.user.id}/${id}.png`,'image/png',100,'test-md5','2026-01-01T00:00:00.000Z','2099-01-01T00:00:00.000Z']);return id;
 }
 const image=await upload(a);
 assert.equal((await api.act(b,r,'message',{requestId:randomUUID(),text:'',imageUploadId:image})).status,400);
 const wrong=await upload(a,'avatars');assert.equal((await api.act(a,r,'message',{requestId:randomUUID(),text:'',imageUploadId:wrong})).status,400);
 const msg={requestId:randomUUID(),text:'صورة الغرفة',imageUploadId:image};
 assert.equal((await api.act(a,r,'message',msg)).status,200);const count=verifies;
 assert.equal((await api.act(a,r,'message',msg)).status,200);assert.equal(verifies,count);
 assert.equal((await api.get(b,r)).features.events.at(-1).image.width,100);
 assert.equal((await api.act(a,r,'gift',{requestId:msg.requestId,recipientId:b.user.id,giftId:'rose',quantity:1})).data.error.code,'REQUEST_CHANGED');
 const cover=await upload(a);assert.equal((await api.act(a,r,'settings',{imageUploadId:cover})).status,200);
 assert.equal((await api.get(b,r)).features.image.height,120);
 await api.act(a,r,'settings',{picture:'moon',imageUploadId:null,imagesDisabled:true});
 assert.equal((await api.db.query('SELECT state FROM tomi_image_uploads WHERE id=?',[cover])).rows[0].state,'deleting');
 const blocked=await upload(b);assert.equal((await api.act(b,r,'message',{requestId:randomUUID(),text:'',imageUploadId:blocked})).data.error.code,'ROOM_IMAGES_DISABLED');
 assert.equal((await api.db.query('SELECT state FROM tomi_image_uploads WHERE id=?',[blocked])).rows[0].state,'pending');
});
test('opening a real 0.7 database preserves accounts, sessions and rooms and adds empty 0.8 ledgers',async t=>{
 const dir=await mkdtemp(join(tmpdir(),'tomi-upgrade08-')),file=join(dir,'old.sqlite');t.after(()=>rm(dir,{recursive:true,force:true}));
 const {DatabaseSync}=await import('node:sqlite'),{readFile}=await import('node:fs/promises');
 const old=new DatabaseSync(file);old.exec(await readFile(new URL('./fixtures/schema-0.7.sql',import.meta.url),'utf8'));
 const user=randomUUID(),room=randomUUID(),time=new Date().toISOString();
 old.prepare('INSERT INTO tomi_users(id,username,display_name,password_hash,recovery_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?)').run(user,'old_account','حساب محفوظ','test-hash','test-recovery',time,time);
 old.prepare('INSERT INTO tomi_sessions(token_hash,user_id,auth_version,created_at,expires_at) VALUES(?,?,?,?,?)').run('test-old-session',user,1,time,'2099-01-01T00:00:00.000Z');
 old.prepare('INSERT INTO tomi_voice_rooms(id,title,owner_id,capacity,seat_count,created_at) VALUES(?,?,?,?,?,?)').run(room,'غرفتي القديمة',user,20,8,time);old.close();
 const db=await openDatabase({sqliteFile:file});t.after(()=>db.close());
 assert.equal((await db.query('SELECT display_name FROM tomi_users WHERE id=?',[user])).rows[0].display_name,'حساب محفوظ');
 assert.equal((await db.query('SELECT token_hash FROM tomi_sessions')).rows[0].token_hash,'test-old-session');
 assert.equal((await db.query('SELECT id,title FROM tomi_voice_rooms')).rows[0].id,room);
 assert.equal(Number((await db.query('SELECT COUNT(*) n FROM tomi_room_gifts')).rows[0].n),0);
});
