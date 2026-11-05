import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHmac,randomBytes} from 'node:crypto';
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
 const crossing=await start(api,b,c);assert.equal(crossing.status,201);assert.equal(crossing.data.call.id,call.id);assert.equal(crossing.data.call.state,'connecting');
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

const videoSdp=sdp+'m=video 9 UDP/TLS/RTP/SAVPF 96\r\na=sendrecv\r\n';
async function connectedFixture(t) {
 const api=await fixture(t),a=await api.register('media_a'),b=await api.register('media_b'),z=await api.register('media_z');
 const c=await thread(api,a,b),call=(await start(api,a,c)).data.call;
 assert.equal((await signal(api,a,call,'offer',{sdp})).status,200);
 await action(api,b,call,'accept');assert.equal((await signal(api,b,call,'answer',{sdp})).status,200);
 await action(api,a,call,'connected');const live=(await action(api,b,call,'connected')).data.call;
 return {api,a,b,z,call:live};
}
test('video changes require peer consent and both ready cameras before SDP',async t=>{
 const {api,a,b,z,call}=await connectedFixture(t),requestId=randomUUID();
 const ask=()=>action(api,a,call,'media-request',{kind:'video',requestId});
 const first=await ask();assert.equal(first.data.call.kind,'audio');assert.equal(first.data.call.mediaChange.state,'pending');assert.equal((await ask()).data.call.mediaChange.revision,1);
 const m=first.data.call.mediaChange;
 assert.equal((await action(api,z,call,'media-response',{requestId,accept:true})).status,404);
 assert.equal((await action(api,a,call,'media-response',{requestId,accept:true})).status,403);
 assert.equal((await action(api,b,call,'media-ready',{requestId,ready:true})).status,409);
 assert.equal((await signal(api,a,call,'offer',{sdp:videoSdp,revision:m.revision})).status,409);
 const accepted=await action(api,b,call,'media-response',{requestId,accept:true});assert.equal(accepted.data.call.kind,'audio');assert.equal(accepted.data.call.mediaChange.state,'accepted');
 const duplicate=await action(api,b,call,'media-request',{requestId:randomUUID(),kind:'video'});assert.equal(duplicate.status,409);
 assert.equal((await action(api,a,call,'media-ready',{requestId,ready:true})).data.call.kind,'audio');
 const both=await action(api,b,call,'media-ready',{requestId,ready:true});assert.equal(both.data.call.kind,'video');assert.equal(both.data.call.mediaChange.state,'negotiating');
 assert.equal((await signal(api,b,call,'offer',{sdp:videoSdp,revision:m.revision})).status,403);
 const offer=await signal(api,a,call,'offer',{sdp:videoSdp,revision:m.revision});assert.equal(offer.status,200);
 assert.equal((await action(api,a,call,'media-applied',{requestId})).status,409);
 assert.equal((await signal(api,b,call,'answer',{sdp:videoSdp,revision:m.revision})).status,200);
 assert.equal((await action(api,a,call,'media-applied',{requestId})).status,200);
 const applied=await action(api,b,call,'media-applied',{requestId});assert.equal(applied.data.call.mediaChange.state,'applied');assert.equal(applied.data.call.connectedAt,call.connectedAt);assert.equal(applied.data.call.id,call.id);
 assert.equal((await action(api,b,call,'media-response',{requestId,accept:true})).status,200);
 const signals=await api.request('GET',`/v1/calls/${call.id}/signals?after=0`,undefined,b.token);assert.deepEqual(signals.data.signals.map(s=>s.revision),[0,1]);
});
test('the callee can request video and owns that SDP offer round after a restart',async t=>{
 const {api,a,b,call}=await connectedFixture(t),requestId=randomUUID();
 const asked=await action(api,b,call,'media-request',{requestId,kind:'video'});const revision=asked.data.call.mediaChange.revision;
 await api.restart();
 const pending=await api.request('GET',`/v1/calls/${call.id}`,undefined,a.token);assert.equal(pending.data.call.mediaChange.requestedByMe,false);
 await action(api,a,call,'media-response',{requestId,accept:true});await action(api,a,call,'media-ready',{requestId,ready:true});await action(api,b,call,'media-ready',{requestId,ready:true});
 assert.equal((await signal(api,a,call,'offer',{sdp:videoSdp,revision})).status,403);
 assert.equal((await signal(api,b,call,'offer',{sdp:videoSdp,revision})).status,200);
 assert.equal((await signal(api,a,call,'answer',{sdp:videoSdp,revision})).status,200);
 const secondDevice=await api.login(b);assert.equal((await action(api,secondDevice,call,'media-cancel',{requestId})).status,409);
});
test('refusal, cancellation, timeout and denied camera preserve the audio call',async t=>{
 const {api,a,b,call}=await connectedFixture(t);
 for(const outcome of ['declined','cancelled','expired','failed']) {
  const requestId=randomUUID();await action(api,a,call,'media-request',{requestId,kind:'video'});
  let result;
  if(outcome==='declined')result=await action(api,b,call,'media-response',{requestId,accept:false});
  if(outcome==='cancelled')result=await action(api,a,call,'media-cancel',{requestId});
  if(outcome==='expired') {
   await api.db.query('UPDATE tomi_call_media_changes SET deadline=? WHERE call_id=? AND request_id=?',['2000-01-01T00:00:00.000Z',call.id,requestId]);
   result=await api.request('GET',`/v1/calls/${call.id}`,undefined,a.token);
  }
  if(outcome==='failed') {
   await action(api,b,call,'media-response',{requestId,accept:true});await action(api,a,call,'media-ready',{requestId,ready:true});
   result=await action(api,b,call,'media-ready',{requestId,ready:false});
  }
  assert.equal(result.data.call.state,'connected');assert.equal(result.data.call.kind,'audio');assert.equal(result.data.call.mediaChange.state,outcome);
  const revision=result.data.call.mediaChange.revision;
  assert.equal((await signal(api,a,call,'offer',{sdp:videoSdp,revision})).status,409);
  assert.equal((await action(api,a,call,'heartbeat')).status,200);
 }
});
test('returning to audio stops video and a fresh upgrade needs consent again',async t=>{
 const {api,a,b,call}=await connectedFixture(t),requestId=randomUUID();
 await action(api,a,call,'media-request',{requestId,kind:'video'});await action(api,b,call,'media-response',{requestId,accept:true});
 await action(api,a,call,'media-ready',{requestId,ready:true});await action(api,b,call,'media-ready',{requestId,ready:true});
 await signal(api,a,call,'offer',{sdp:videoSdp,revision:1});await signal(api,b,call,'answer',{sdp:videoSdp,revision:1});
 await action(api,a,call,'media-applied',{requestId});await action(api,b,call,'media-applied',{requestId});
 const audio=await action(api,b,call,'media-request',{requestId:randomUUID(),kind:'audio'});assert.equal(audio.data.call.kind,'audio');assert.equal(audio.data.call.state,'connected');
 assert.equal((await signal(api,a,call,'offer',{sdp:videoSdp,revision:1})).status,409);
 const next=await action(api,b,call,'media-request',{requestId:randomUUID(),kind:'video'});assert.equal(next.data.call.mediaChange.state,'pending');assert.equal(next.data.call.kind,'audio');
 await action(api,a,call,'end');assert.equal(Number((await api.db.query('SELECT COUNT(*) n FROM tomi_call_signals WHERE call_id=?',[call.id])).rows[0].n),0);
 assert.equal((await api.request('GET',`/v1/calls/${call.id}`,undefined,b.token)).data.call.mediaChange.state,'cancelled');
});
test('SDP rounds reject unbounded revisions and media commands reject unknown fields',async t=>{
 const {api,a,call}=await connectedFixture(t);
 for(const revision of [-1,31,1.2,'1'])assert.equal((await signal(api,a,call,'offer',{sdp:videoSdp,revision})).status,400);
 assert.equal((await action(api,a,call,'media-request',{requestId:randomUUID(),kind:'video',camera:true})).status,400);
 assert.equal((await action(api,a,call,'media-request',{requestId:randomUUID(),kind:'invalid'})).status,400);
});
test('0.6 is an additive migration of the verified 0.5 schema',async()=>{
 const old=await readFile(new URL('fixtures/schema-0.5.sql',import.meta.url),'utf8'),current=await readFile(new URL('../schema.sql',import.meta.url),'utf8');assert.ok(current.startsWith(old));
});

test('0.9 call devices negotiate session bindings and cancel every ringing device durably',async t=>{
 const api=await fixture(t,{push:true}),a=await api.register('mobile09_a'),b=await api.register('mobile09_b'),b2=await api.login(b),c=await thread(api,a,b);
 const token1='mobile09_device_token_123456789',token2='mobile09_device_token_987654321';
 const first=await api.request('PUT','/v1/push/device',{token:token1,platform:'android',callProtocol:2},b.token),second=await api.request('PUT','/v1/push/device',{token:token2,platform:'android',callProtocol:2},b2.token);
 assert.match(first.data.bindingId,/^[a-f0-9]{64}$/);assert.notEqual(first.data.bindingId,second.data.bindingId);
 assert.equal((await api.request('PUT','/v1/push/device',{token:token1,platform:'ios',callProtocol:2},b.token)).status,400);
 const call=(await start(api,a,c)).data.call;await api.server.flushPush();
 assert.equal(api.sent.length,2);assert.ok(api.sent.every(x=>x.callProtocol===2&&!x.cancel&&x.expiresAt===Date.parse(call.ringDeadline)));
 assert.deepEqual(new Set(api.sent.map(x=>x.bindingId)),new Set([first.data.bindingId,second.data.bindingId]));
 await action(api,b,call,'accept');await api.restart();await api.server.flushPush();await api.server.flushPush();
 const cancels=api.sent.filter(x=>x.cancel);assert.equal(cancels.length,2);assert.ok(cancels.every(x=>x.callId===call.id));
 assert.equal(Number((await api.db.query('SELECT COUNT(*) AS n FROM tomi_call_push_cancel_receipts')).rows[0].n),2);
});
test('0.9 a cancelled unsent call sends no stale ring and logout detaches cancellation',async t=>{
 const api=await fixture(t,{push:true}),a=await api.register('cancel09_a'),b=await api.register('cancel09_b'),c=await thread(api,a,b),token='cancel09_device_token_123456789';
 await api.request('PUT','/v1/push/device',{token,platform:'android',callProtocol:2},b.token);
 const call=(await start(api,a,c)).data.call;await action(api,a,call,'end');await api.server.flushPush();
 assert.equal(api.sent.length,1);assert.equal(api.sent[0].cancel,true);
 const next=(await start(api,a,c)).data.call;await api.request('POST','/v1/auth/logout',{},b.token);await action(api,a,next,'end');await api.server.flushPush();assert.equal(api.sent.length,1);
});
test('0.9 migration appends to the exact verified 0.8 database schema',async()=>{
 const old=(await readFile(new URL('fixtures/schema-0.8.sql',import.meta.url),'utf8')).trim();
 const current=await readFile(new URL('../schema.sql',import.meta.url),'utf8');assert.ok(current.startsWith(old));
});

test('crossed calls merge one table, retry after restart, and bind the receiving device',async t=>{
 const api=await fixture(t),a=await api.register('cross_a'),b=await api.register('cross_b'),c=await thread(api,a,b),nonce=randomUUID();
 const outcomes=await Promise.all([start(api,a,c),start(api,b,c,{requestId:nonce})]);
 assert.ok(outcomes.every(r=>r.status===201));assert.equal(outcomes[0].data.call.id,outcomes[1].data.call.id);
 const call=outcomes.find(r=>r.data.call.state==='connecting').data.call;
 assert.equal(Number((await api.db.query('SELECT COUNT(*) n FROM tomi_calls')).rows[0].n),1);
 assert.equal(Number((await api.db.query('SELECT COUNT(*) n FROM tomi_active_calls')).rows[0].n),2);
 const bCall=outcomes[1].data.call;
 await api.restart();const replay=await start(api,b,c,{requestId:nonce});assert.equal(replay.data.call.id,bCall.id);assert.equal(replay.status,200);
 assert.equal((await start(api,b,c,{requestId:nonce,kind:'video'})).status,409);
 const other=await api.login(b);assert.equal((await start(api,other,c,{requestId:nonce})).status,409);
 const aliasOwner=(await api.db.query('SELECT user_id FROM tomi_call_cross_requests')).rows[0].user_id,erased=[a,b].find(u=>u.user.id===aliasOwner);
 const deletion=await api.request('POST','/v1/account/deletion',{requestId:randomUUID(),receiptToken:randomBytes(32).toString('base64url'),password:'a long TOMI call testing password',confirmation:'حذف حسابي'},erased.token);assert.equal(deletion.status,202,JSON.stringify(deletion));assert.equal(Number((await api.db.query('SELECT COUNT(*) n FROM tomi_call_cross_requests WHERE user_id=?',[aliasOwner])).rows[0].n),0);
});
