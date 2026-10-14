import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHmac} from 'node:crypto';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {once} from 'node:events';
import {openDatabase} from '../src/database.mjs';
import {createApp} from '../src/app.mjs';
import {iceFromEnvironment,turnLifetime} from '../src/ice.mjs';
const connectionString=process.env.TEST_DATABASE_URL;
if(connectionString){const u=new URL(connectionString);assert.ok(['localhost','127.0.0.1'].includes(u.hostname)&&u.pathname==='/tomi_test','Tests require a local tomi_test database');}
const provider=iceFromEnvironment({CALL_TURN_URLS:'turn:relay.example.com:3478?transport=udp',CALL_TURN_SECRET:'test-only-secret-'.repeat(3)});
const sdp='v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=fingerprint:sha-256 00:11\r\n';
async function fixture(t,{disabled=false,push=false}={}){
 const directory=await mkdtemp(join(tmpdir(),'tomi-calls-'));let db,server,base;const sent=[];
 async function start(){db=await openDatabase({connectionString:process.env.TEST_DATABASE_URL,sqliteFile:join(directory,'test.sqlite')});server=await createApp({database:db,iceProvider:disabled?null:provider,callAutoSweep:false,pushAutoFlush:false,pushSender:push?async d=>{sent.push(d);return 'sent';}:null,rateLimitMultiplier:20});server.listen(0,'127.0.0.1');await once(server,'listening');base='http://127.0.0.1:'+server.address().port;}
 async function stop(){const done=new Promise((resolve,reject)=>server.close(e=>e?reject(e):resolve()));server.closeIdleConnections();await done;await db.close();}
 await start();if(process.env.TEST_DATABASE_URL){await db.query('DELETE FROM tomi_users');await db.query('DELETE FROM tomi_rate_limits');}t.after(async()=>{await stop();await rm(directory,{recursive:true,force:true});});
 return{sent,get db(){return db;},get server(){return server;},async restart(){await stop();await start();},async request(method,path,body,token){const r=await fetch(base+path,{method,headers:{...(body!==undefined?{'content-type':'application/json'}:{}),...(token?{authorization:'Bearer '+token}:{})},...(body!==undefined?{body:JSON.stringify(body)}:{})});return{status:r.status,data:await r.json()};},async register(name){const r=await this.request('POST','/v1/auth/register',{username:name,displayName:name,password:'a long TOMI call testing password'});assert.equal(r.status,201);return r.data;},async login(a){return(await this.request('POST','/v1/auth/login',{username:a.user.username,password:'a long TOMI call testing password'})).data;}};
}
const thread=async(api,a,b)=>(await api.request('POST','/v1/chats',{userId:b.user.id},a.token)).data.conversation;
const start=(api,a,c,extra={})=>api.request('POST','/v1/calls',{conversationId:c.id,kind:'audio',requestId:randomUUID(),...extra},a.token);
const action=(api,a,call,type,body={})=>api.request('POST',`/v1/calls/${call.id}/${type}`,body,a.token);
const signal=(api,a,call,type,extra={})=>action(api,a,call,'signals',{type,requestId:randomUUID(),...extra});
test('calls enforce participant access, stable start and single active call per user',async t=>{
 const api=await fixture(t),a=await api.register('call_a'),b=await api.register('call_b'),z=await api.register('call_z'),c=await thread(api,a,b),requestId=randomUUID();
 const requests=await Promise.all([start(api,a,c,{requestId}),start(api,a,c,{requestId})]);assert.equal(requests[0].data.call.id,requests[1].data.call.id);const call=requests[0].data.call;assert.equal(call.state,'ringing');
 assert.equal((await api.request('GET',`/v1/calls/${call.id}`,undefined,z.token)).status,404);
 assert.equal((await action(api,a,call,'accept')).status,403);
 assert.equal((await start(api,a,c,{requestId,kind:'video'})).status,409);
 assert.equal((await start(api,b,c)).status,409);
 const other=await thread(api,z,b),busy=await start(api,z,other);assert.equal(busy.data.call.reason,'busy');assert.equal(busy.data.call.state,'ended');
 assert.equal(Number((await api.db.query('SELECT COUNT(*) n FROM tomi_active_calls')).rows[0].n),2);
});
test('accept binds one receiving session; another device cannot read ICE or signal',async t=>{
 const api=await fixture(t),a=await api.register('device_a'),b=await api.register('device_b'),b2=await api.login(b),c=await thread(api,a,b),call=(await start(api,a,c)).data.call;
 assert.equal((await action(api,b,call,'ice')).status,409);
 const answers=await Promise.all([action(api,b,call,'accept'),action(api,b2,call,'accept')]);assert.deepEqual(answers.map(x=>x.status).sort(),[200,409]);
 const owner=answers[0].status===200?b:b2,other=owner===b?b2:b;
 assert.equal((await action(api,owner,call,'ice')).status,200);assert.equal((await action(api,other,call,'ice')).status,409);
 assert.equal((await signal(api,other,call,'answer',{sdp})).status,409);
 assert.equal((await action(api,other,call,'end')).status,409);
});
test('offer answer and ICE persist in order, are private and delete on end',async t=>{
 const api=await fixture(t),a=await api.register('signal_a'),b=await api.register('signal_b'),c=await thread(api,a,b),call=(await start(api,a,c)).data.call,requestId=randomUUID();
 assert.equal((await signal(api,a,call,'candidate',{candidate:'candidate:one',sdpMid:'0',sdpMLineIndex:0})).status,409);
 const offer=await signal(api,a,call,'offer',{sdp,requestId});assert.equal(offer.status,200);assert.equal((await signal(api,a,call,'offer',{sdp,requestId})).data.sequence,offer.data.sequence);
 assert.equal((await signal(api,a,call,'offer',{sdp:sdp+'a=sendrecv\r\n',requestId})).status,409);
 const candidate={candidate:'candidate:one',sdpMid:'0',sdpMLineIndex:0};assert.equal((await signal(api,a,call,'candidate',candidate)).status,200);
 await action(api,b,call,'accept');assert.equal((await signal(api,b,call,'offer',{sdp})).status,403);assert.equal((await signal(api,b,call,'answer',{sdp})).status,200);
 await api.restart();const sync=await api.request('GET',`/v1/calls/${call.id}/signals?after=0`,undefined,b.token);assert.deepEqual(sync.data.signals.map(s=>s.type),['offer','candidate']);
 assert.equal((await api.request('GET',`/v1/calls/${call.id}/signals?after=${sync.data.nextAfter}`,undefined,b.token)).data.signals.length,0);
 await action(api,a,call,'connected');assert.equal((await action(api,b,call,'connected')).data.call.state,'connected');
 assert.equal((await action(api,a,call,'end')).data.call.reason,'ended');assert.equal((await action(api,a,call,'end')).status,200);
 assert.equal(Number((await api.db.query('SELECT COUNT(*) n FROM tomi_call_signals')).rows[0].n),0);
 assert.equal(Number((await api.db.query('SELECT COUNT(*) n FROM tomi_active_calls')).rows[0].n),0);
 assert.equal((await api.request('GET','/v1/calls',undefined,b.token)).data.calls[0].state,'ended');
});
test('missed, declined, cancelled and stale sessions release both participants',async t=>{
 const api=await fixture(t),a=await api.register('timeouts_a'),b=await api.register('timeouts_b'),c=await thread(api,a,b);
 let call=(await start(api,a,c)).data.call;await api.db.query('UPDATE tomi_calls SET ring_deadline=? WHERE id=?',['2000-01-01T00:00:00.000Z',call.id]);await api.server.sweepCalls();assert.equal((await api.request('GET',`/v1/calls/${call.id}`,undefined,a.token)).data.call.reason,'missed');
 call=(await start(api,a,c)).data.call;assert.equal((await action(api,b,call,'decline')).data.call.reason,'declined');
 call=(await start(api,a,c)).data.call;assert.equal((await action(api,a,call,'end')).data.call.reason,'cancelled');
 call=(await start(api,a,c)).data.call;await action(api,b,call,'accept');await api.db.query('UPDATE tomi_calls SET callee_seen=? WHERE id=?',['2000-01-01T00:00:00.000Z',call.id]);await api.restart();await api.server.sweepCalls();assert.equal((await api.request('GET',`/v1/calls/${call.id}`,undefined,a.token)).data.call.reason,'disconnected');
 assert.equal((await start(api,a,c)).status,201);
});
test('blocks and logout terminate calls; fresh calls with blocked peer are rejected',async t=>{
 const api=await fixture(t),a=await api.register('secure_a'),b=await api.register('secure_b'),c=await thread(api,a,b);let call=(await start(api,a,c)).data.call;
 await api.request('PUT','/v1/chat/blocks/'+a.user.id,{blocked:true},b.token);await api.server.sweepCalls();assert.equal((await api.request('GET',`/v1/calls/${call.id}`,undefined,a.token)).data.call.reason,'blocked');assert.equal((await start(api,a,c)).status,403);
 await api.request('PUT','/v1/chat/blocks/'+a.user.id,{blocked:false},b.token);call=(await start(api,a,c)).data.call;await action(api,b,call,'accept');await api.request('POST','/v1/auth/logout',{},b.token);assert.equal((await api.request('GET',`/v1/calls/${call.id}`,undefined,a.token)).data.call.reason,'session_ended');
});
test('TURN remains disabled without complete configuration and secrets never become client config',async t=>{
 assert.equal(iceFromEnvironment({}),null);assert.throws(()=>iceFromEnvironment({CALL_TURN_KEY_ID:'partial'}));assert.throws(()=>iceFromEnvironment({CALL_TURN_URLS:'https://not-turn',CALL_TURN_SECRET:'x'.repeat(32)}));
 const cfg=await provider({userId:randomUUID(),callId:randomUUID()}),relay=cfg.iceServers[0];assert.ok(Number(relay.username.split(':')[0])>=Math.floor(Date.now()/1000)+turnLifetime-2);assert.equal(relay.credential,createHmac('sha1','test-only-secret-'.repeat(3)).update(relay.username).digest('base64'));
 const api=await fixture(t,{disabled:true}),a=await api.register('disabled_a'),b=await api.register('disabled_b'),c=await thread(api,a,b);assert.equal((await start(api,a,c)).data.error.code,'CALLS_DISABLED');
 const cf=iceFromEnvironment({CALL_TURN_KEY_ID:'turn_key_test_id',CALL_TURN_API_TOKEN:'server-only-token-123456789',CALL_FORCE_RELAY:'true'},{fetcher:async(url,opts)=>{assert.ok(url.endsWith('/credentials/generate-ice-servers'));assert.equal(JSON.parse(opts.body).ttl,7500);return Response.json({iceServers:[{urls:['turns:turn.cloudflare.com:443?transport=tcp'],username:'temporary',credential:'temporary-password'}]});}});
 const result=await cf({});assert.equal(result.iceTransportPolicy,'relay');assert.ok(!JSON.stringify(result).includes('server-only'));
});
test('signals reject oversized descriptions, mismatched media and arbitrary payloads',async t=>{
 const api=await fixture(t),a=await api.register('bounds_a'),b=await api.register('bounds_b'),c=await thread(api,a,b),call=(await start(api,a,c)).data.call;
 assert.equal((await signal(api,a,call,'offer',{sdp:sdp+'x'.repeat(65536)})).status,400);
 assert.equal((await signal(api,a,call,'offer',{sdp:sdp+'m=video 9 RTP/SAVPF 96\r\n'})).status,400);
 assert.equal((await signal(api,a,call,'offer',{sdp,unexpected:'x'})).status,400);
 assert.equal((await signal(api,a,call,'candidate',{candidate:'x',sdpMid:'0',sdpMLineIndex:0})).status,400);
});
test('incoming call push is durable, deduplicated and suppressed after acceptance',async t=>{
 const api=await fixture(t,{push:true}),a=await api.register('callpush_a'),b=await api.register('callpush_b'),c=await thread(api,a,b);await api.request('PUT','/v1/push/device',{token:'call_device_token_1234567890',platform:'android'},b.token);
 const requestId=randomUUID(),call=(await start(api,a,c,{requestId})).data.call;await start(api,a,c,{requestId});await api.restart();await api.server.flushPush();await api.server.flushPush();assert.equal(api.sent.length,1);assert.equal(api.sent[0].callId,call.id);
 await action(api,b,call,'accept');await action(api,a,call,'end');const next=(await start(api,a,c)).data.call;await action(api,b,next,'accept');await api.server.flushPush();assert.equal(api.sent.length,1);
});
test('0.6 is an additive migration of the verified 0.5 schema',async()=>{
 const old=await readFile(new URL('fixtures/schema-0.5.sql',import.meta.url),'utf8'),current=await readFile(new URL('../schema.sql',import.meta.url),'utf8');assert.ok(current.startsWith(old));
});
