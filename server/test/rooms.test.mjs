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

async function fixture(t,{disabled=false}={}){
 const dir=await mkdtemp(join(tmpdir(),'tomi-rooms-')),calls=[];let down=false,db,server,base;
 const provider={ensure:async()=>{if(down)throw Error('offline');},
  grant:async(r,m)=>({url:'wss://test.livekit.cloud',identity:m.identity,token:'test-only',publish:!!m.mic_allowed}),
  permissions:async(r,id,publish)=>{if(down)throw Error('offline');calls.push(['permission',id,publish]);},
  remove:async(r,id)=>{if(down)throw Error('offline');calls.push(['remove',id]);},close:async r=>{if(down)throw Error('offline');calls.push(['close',r.id]);}};
 async function start(reset=false){
  db=await openDatabase({connectionString:process.env.TEST_DATABASE_URL,sqliteFile:join(dir,'rooms.sqlite')});
  if(reset&&process.env.TEST_DATABASE_URL){const u=new URL(process.env.TEST_DATABASE_URL);assert.ok(['localhost','127.0.0.1'].includes(u.hostname)&&u.pathname==='/tomi_test');await db.query('DELETE FROM tomi_users');await db.query('DELETE FROM tomi_rate_limits');}
  server=await createApp({database:db,roomProvider:disabled?null:provider,roomAutoSweep:false,iceProvider:async()=>({}),callAutoSweep:false,pushAutoFlush:false,rateLimitMultiplier:50});
  server.listen(0,'127.0.0.1');await once(server,'listening');base='http://127.0.0.1:'+server.address().port;
 }
 async function stop(){const closed=once(server,'close');server.close();server.closeIdleConnections();await closed;await db.close();}
 await start(true);t.after(async()=>{await stop();await rm(dir,{recursive:true,force:true});});
 const api={get db(){return db;},get server(){return server;},calls,set down(v){down=v;},async restart(){await stop();await start();},
  async request(method,path,body,token){const r=await fetch(base+path,{method,headers:{...(body?{'content-type':'application/json'}:{}),...(token?{authorization:'Bearer '+token}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,data:await r.json()};},
  async register(name){const r=await this.request('POST','/v1/auth/register',{username:name,displayName:name,password:'test-only rooms passphrase'});assert.equal(r.status,201);return r.data;},
  async create(a,extra={}){const r=await this.request('POST','/v1/rooms',{requestId:randomUUID(),title:'غرفة تومي',capacity:10,seatCount:4,...extra},a.token);assert.equal(r.status,201,JSON.stringify(r.data));return r.data.room;},
  async act(a,r,action,body={}){return this.request('POST',`/v1/rooms/${r.id}/${action}`,body,a.token);},
  async get(a,r){return (await this.request('GET',`/v1/rooms/${r.id}`,null,a.token)).data.room;},
 };return api;
}
test('rooms persist; creation and joins are idempotent and session-bound; listeners cannot moderate',async t=>{
 const api=await fixture(t),a=await api.register('room_owner'),b=await api.register('room_guest');
 const requestId=randomUUID(),r=await api.create(a,{requestId});assert.equal((await api.create(a,{requestId})).id,r.id);
 assert.equal((await api.request('GET','/v1/rooms')).status,401);
 const owner=await api.act(a,r,'join'),guest=await api.act(b,r,'join');assert.equal(owner.data.room.members[0].seat,0);assert.equal(guest.data.connection.publish,false);
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
test('expired heartbeat and revoked sessions leave rooms; empty room closes after ten minutes',async t=>{
 const api=await fixture(t),a=await api.register('expire_owner'),b=await api.register('expire_guest'),r=await api.create(a);
 const own=await api.act(a,r,'join');await api.act(b,r,'join');await api.request('POST','/v1/auth/logout',{},b.token);assert.equal((await api.get(a,r)).memberCount,1);
 await api.db.query('UPDATE tomi_voice_members SET last_seen=? WHERE room_id=?',['2000-01-01T00:00:00.000Z',r.id]);await api.server.sweepRooms();assert.equal((await api.get(a,r)).memberCount,0);
 await api.db.query('UPDATE tomi_voice_rooms SET empty_since=? WHERE id=?',['2000-01-01T00:00:00.000Z',r.id]);await api.server.sweepRooms();assert.equal((await api.get(a,r)).state,'closed');
 assert.equal((await api.act(a,r,'join')).status,410);assert.ok(api.calls.some(v=>v[0]==='close'));assert.ok(own.data.connection.identity);
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
 const claim=(await api.act(a,r,'take-seat')).data.room;assert.equal(claim.members.find(m=>m.user.id===a.user.id).seat,0);
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
 assert.equal(Number((await api.db.query('SELECT COUNT(*) n FROM tomi_voice_jobs WHERE room_id=?',[r.id])).rows[0].n),1);
 assert.equal(Number((await api.db.query('SELECT needs_delete FROM tomi_voice_rooms WHERE id=?',[r.id])).rows[0].needs_delete),1);
 await api.server.flushRooms();
 assert.equal(Number((await api.db.query('SELECT COUNT(*) n FROM tomi_voice_jobs WHERE room_id=?',[r.id])).rows[0].n),0);
 assert.ok([one.identity,two.identity].every(id=>api.calls.some(v=>v[0]==='remove'&&v[1]===id)));
 assert.equal(Number((await api.db.query('SELECT needs_delete FROM tomi_voice_rooms WHERE id=?',[r.id])).rows[0].needs_delete),0);
});
