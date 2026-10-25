import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {once} from 'node:events';
import {request as httpRequest} from 'node:http';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {openDatabase} from '../src/database.mjs';
import {createApp} from '../src/app.mjs';
import {moderationOwner} from '../src/moderation.mjs';
import {iceFromEnvironment} from '../src/ice.mjs';
import {digest} from '../src/security.mjs';

const password='test-only moderation12 passphrase',connectionString=process.env.TEST_DATABASE_URL;
if(connectionString){const u=new URL(connectionString);assert.ok(['localhost','127.0.0.1'].includes(u.hostname)&&u.pathname==='/tomi_test','Use only local tomi_test');}
async function fixture(t){
  const dir=await mkdtemp(join(tmpdir(),'tomi12-'));let db,server,base,ownerUserId=null,providerFails=false;
  const removed=[],provider={ensure:async()=>{},grant:async(r,m)=>({url:'wss://test.livekit.cloud',identity:m.identity,token:'test-only'}),permissions:async()=>{},remove:async(r,id)=>{if(providerFails)throw Error('Offline');removed.push(id);},close:async()=>{if(providerFails)throw Error('Offline');}};
  async function start(reset=false){db=await openDatabase({connectionString,sqliteFile:join(dir,'state.sqlite')});if(reset&&connectionString){await db.query('DELETE FROM tomi_users');await db.query('DELETE FROM tomi_admin_audit');await db.query('DELETE FROM tomi_rate_limits');}server=await createApp({database:db,ownerUserId,roomProvider:provider,iceProvider:iceFromEnvironment({CALL_TURN_URLS:'turn:relay.example.com:3478',CALL_TURN_SECRET:'test-only-'.repeat(5)}),roomAutoSweep:false,callAutoSweep:false,pushAutoFlush:false,rateLimitMultiplier:100});server.listen(0,'127.0.0.1');await once(server,'listening');base='http://127.0.0.1:'+server.address().port;}
  async function stop(){const done=once(server,'close');server.close();server.closeIdleConnections();await done;await db.close();}
  await start(true);t.after(async()=>{await stop();await rm(dir,{recursive:true,force:true});});
  return {get db(){return db;},get server(){return server;},get base(){return base;},removed,set providerFails(value){providerFails=value;},async restart(owner=ownerUserId){await stop();ownerUserId=owner;await start();},
    async req(a,method,path,body){const r=await fetch(base+path,{method,headers:{...(a?{authorization:'Bearer '+a.token}:{}),...(body!==undefined?{'content-type':'application/json'}:{})},...(body!==undefined?{body:JSON.stringify(body)}:{})});return {status:r.status,data:await r.json()};},
    async register(username){const r=await this.req(null,'POST','/v1/auth/register',{username,displayName:username,password});assert.equal(r.status,201);return r.data;},
    async post(a){const r=await this.req(a,'POST','/v1/posts',{text:'نص بلاغ اختبار خاص',requestId:randomUUID()});assert.equal(r.status,201);return r.data.post;},
    async report(a,type,targetId,extra={}){return this.req(a,'POST','/v1/reports',{requestId:randomUUID(),targetType:type,targetId,reason:'harassment',description:'وصف خاص للبلاغ',...extra});},
    async command(a,action,targetId,extra={}){return this.req(a,'POST','/v1/admin/actions',{requestId:randomUUID(),action,targetId,reason:'سبب اختبار إجراء الإدارة',expectedRevision:0,...extra});},
    async create(a){await this.req(a,'GET','/v1/rooms/wallet');await db.query('UPDATE tomi_room_wallets SET coins=coins+5799 WHERE user_id=?',[a.user.id]);const r=await this.req(a,'POST','/v1/rooms',{title:'غرفة اختبار الإدارة',requestId:randomUUID(),capacity:10,seatCount:4,tier:'advanced',acceptTerms:true});assert.equal(r.status,201);return r.data.room;},
    async auditCount(){return Number((await db.query('SELECT COUNT(*) n FROM tomi_admin_audit')).rows[0].n);},
  };
}
async function people(f){const owner=await f.register('owner12'),member=await f.register('member12'),mod=await f.register('moderator12');await f.restart(owner.user.id);return {owner,member,mod};}

test('0.12 owner is explicit server configuration and no ordinary account can grant itself a role',async t=>{
  assert.equal(moderationOwner({}),null);assert.throws(()=>moderationOwner({TOMI_OWNER_USER_ID:'owner_username'}));
  const f=await fixture(t),a=await f.register('first12');assert.equal((await f.req(a,'GET','/v1/moderation/access')).data.role,'member');assert.equal((await f.req(a,'GET','/v1/admin/metrics')).status,403);
  await assert.rejects(createApp({database:f.db,ownerUserId:randomUUID()}),/existing active account/);
  assert.equal((await f.command(a,'grant_moderator',a.user.id)).status,403);assert.equal((await f.req(a,'PATCH','/v1/me',{username:a.user.username,displayName:'first12',bio:'',avatarPreset:'initials',role:'owner'})).status,400);
  await f.restart(a.user.id);assert.equal((await f.req(a,'GET','/v1/moderation/access')).data.role,'owner');assert.equal((await f.command(a,'revoke_moderator',a.user.id)).status,403);
});
test('0.12 reports are private, concurrent retries are unique and active duplicates share the tracked report',async t=>{
  const f=await fixture(t),{owner,member,mod}=await people(f),post=await f.post(member),nonce=randomUUID();
  const results=await Promise.all([f.report(mod,'post',post.id,{requestId:nonce}),f.report(mod,'post',post.id,{requestId:nonce})]);assert.equal(results[0].data.report.id,results[1].data.report.id);
  const rid=results[0].data.report.id;assert.equal((await f.report(mod,'post',post.id)).data.duplicate,true);assert.equal((await f.report(mod,'post',post.id,{requestId:nonce,description:'تغيير النص'})).status,409);
  assert.equal((await f.req(member,'GET','/v1/reports/'+rid)).status,404);assert.equal((await f.req(owner,'GET','/v1/reports')).data.items.length,0);
  await f.command(owner,'review_report',rid,{status:'reviewing',note:'ملاحظة داخلية سرية',publicMessage:'بدأت المراجعة'});
  const mine=(await f.req(mod,'GET','/v1/reports/'+rid)).data.report;assert.equal(mine.status,'reviewing');assert.equal(mine.publicMessage,'بدأت المراجعة');assert.ok(!('note' in mine)&&!('snapshot' in mine)&&!('reviewerId' in mine));
  assert.equal((await f.req(mod,'GET','/v1/admin/reports/'+rid)).status,403);
  assert.equal((await f.req(owner,'GET','/v1/admin/reports/'+rid)).data.report.note,'ملاحظة داخلية سرية');
  assert.equal((await f.report(member,'account',member.user.id)).status,400);
});
test('0.12 report receipt survives target deletion and private evidence stays available to staff',async t=>{
  const f=await fixture(t),{owner,member,mod}=await people(f),p=await f.post(member),nonce=randomUUID(),r=await f.report(mod,'post',p.id,{requestId:nonce});
  await f.req(member,'DELETE','/v1/posts/'+p.id);const replay=await f.report(mod,'post',p.id,{requestId:nonce});assert.equal(replay.status,201);assert.equal(replay.data.report.id,r.data.report.id);
  const detail=await f.req(owner,'GET','/v1/admin/reports/'+r.data.report.id);assert.equal(detail.data.target,null);assert.equal(detail.data.report.snapshot.text,p.text);assert.equal((await f.report(mod,'post',p.id)).status,404);
});
test('0.12 platform moderator permissions are distinct, versioned, protected and revoked live',async t=>{
  const f=await fixture(t),{owner,member,mod}=await people(f),nonce=randomUUID();assert.equal((await f.command(owner,'grant_moderator',mod.user.id,{requestId:nonce})).status,200);
  assert.equal((await f.command(owner,'grant_moderator',mod.user.id,{requestId:nonce})).data.replayed,true);assert.equal(await f.auditCount(),1);
  assert.equal((await f.req(mod,'GET','/v1/moderation/access')).data.role,'moderator');assert.equal((await f.command(mod,'suspend_user',member.user.id)).status,403);assert.equal((await f.req(mod,'GET','/v1/admin/staff')).status,403);
  const p=await f.post(owner);assert.equal((await f.command(mod,'hide_post',p.id)).status,403);assert.equal((await f.command(owner,'suspend_user',mod.user.id)).data.error.code,'ADMIN_STAFF');
  assert.equal((await f.command(owner,'revoke_moderator',mod.user.id,{expectedRevision:1})).status,200);assert.equal((await f.req(mod,'GET','/v1/admin/reports')).status,403);assert.equal((await f.command(owner,'grant_moderator',mod.user.id,{expectedRevision:0})).status,409);
  await f.restart();assert.equal((await f.req(mod,'GET','/v1/moderation/access')).data.role,'member');
});
test('0.12 hidden posts disappear from reads, likes, comments and every feed without losing their rows',async t=>{
  const f=await fixture(t),{owner,member,mod}=await people(f),p=await f.post(member);await f.command(owner,'grant_moderator',mod.user.id);
  assert.equal((await f.command(mod,'hide_post',p.id)).status,200);
  for(const query of ['', '?scope=mine','?scope=following','?userId='+member.user.id])assert.equal((await f.req(member,'GET','/v1/posts'+query)).data.posts.length,0);
  assert.equal((await f.req(owner,'GET','/v1/posts/'+p.id)).status,404);assert.equal((await f.req(member,'PUT','/v1/posts/'+p.id+'/like',{liked:true})).status,404);assert.equal((await f.req(member,'GET','/v1/posts/'+p.id+'/comments')).status,404);
  assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_posts WHERE id=?',[p.id])).rows[0].n),1);
  assert.equal((await f.command(mod,'restore_post',p.id,{expectedRevision:1})).status,200);assert.equal((await f.req(member,'GET','/v1/posts/'+p.id)).data.post.text,p.text);
});
test('0.12 stable admin receipts cannot undo a later restore and replay remains available after deletion',async t=>{
  const f=await fixture(t),{owner,member}=await people(f),p=await f.post(member),nonce=randomUUID();
  const first=await f.command(owner,'hide_post',p.id,{requestId:nonce});assert.equal(first.status,200);await f.command(owner,'restore_post',p.id,{expectedRevision:1});
  const replay=await f.command(owner,'hide_post',p.id,{requestId:nonce});assert.equal(replay.data.receiptId,first.data.receiptId);assert.equal((await f.req(member,'GET','/v1/posts/'+p.id)).status,200);assert.equal(await f.auditCount(),2);
  assert.equal((await f.command(owner,'hide_post',p.id,{requestId:nonce,reason:'تغيير السبب الأصلي'})).status,409);assert.equal((await f.command(owner,'hide_post',p.id)).status,409);
  await f.req(member,'DELETE','/v1/posts/'+p.id);assert.equal((await f.command(owner,'hide_post',p.id,{requestId:nonce})).data.replayed,true);
});
test('0.12 report transitions use revisions, separate notes, linked targets and safe reopen rules',async t=>{
  const f=await fixture(t),{owner,member,mod}=await people(f),p=await f.post(member),r=(await f.report(mod,'post',p.id)).data.report;
  assert.equal((await f.command(owner,'review_report',r.id,{status:'resolved',note:'تمت المراجعة',publicMessage:'اكتملت المعالجة'})).status,200);
  assert.equal((await f.command(owner,'review_report',r.id,{status:'dismissed'})).status,409);
  const newer=(await f.report(mod,'post',p.id)).data.report;assert.notEqual(newer.id,r.id);
  assert.equal((await f.command(owner,'review_report',r.id,{expectedRevision:1,status:'open'})).data.error.code,'REPORT_ALREADY_OPEN');
  assert.equal((await f.command(owner,'hide_post',p.id,{reportId:newer.id})).status,200);const other=await f.post(member);assert.equal((await f.command(owner,'hide_post',other.id,{reportId:newer.id})).data.error.code,'REPORT_ACTION_MISMATCH');
});
test('0.12 suspending an account atomically revokes sessions, ends calls and closes owned rooms with durable provider jobs',async t=>{
  const f=await fixture(t),{owner,member,mod}=await people(f),peer=await f.register('callpeer12'),room=await f.create(member);
  await f.req(mod,'POST',`/v1/rooms/${room.id}/join`,{});const thread=(await f.req(member,'POST','/v1/chats',{userId:peer.user.id})).data.conversation;
  const call=(await f.req(member,'POST','/v1/calls',{conversationId:thread.id,kind:'audio',requestId:randomUUID()})).data.call;assert.ok(call);
  f.providerFails=true;const suspended=await f.command(owner,'suspend_user',member.user.id);assert.equal(suspended.status,200,JSON.stringify(suspended.data));
  assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_sessions WHERE user_id=?',[member.user.id])).rows[0].n),0);
  assert.equal((await f.db.query('SELECT state FROM tomi_calls WHERE id=?',[call.id])).rows[0].state,'ended');assert.equal((await f.db.query('SELECT state FROM tomi_voice_rooms WHERE id=?',[room.id])).rows[0].state,'closed');
  assert.ok(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_voice_jobs')).rows[0].n)>0);assert.equal((await f.req(member,'GET','/v1/me')).status,401);
  assert.equal((await f.req(null,'POST','/v1/auth/login',{username:member.user.username,password})).data.error.code,'ACCOUNT_SUSPENDED');
  assert.equal((await f.req(null,'POST','/v1/auth/recover',{username:member.user.username,password,recoveryCode:member.recoveryCode})).data.error.code,'ACCOUNT_SUSPENDED');
  f.providerFails=false;await f.restart();for(let i=0;i<3;i++)await f.server.flushRooms();assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_voice_jobs')).rows[0].n),0);
  assert.equal((await f.command(owner,'restore_user',member.user.id,{expectedRevision:1})).status,200);const logged=await f.req(null,'POST','/v1/auth/login',{username:member.user.username,password});assert.equal(logged.status,200);assert.equal((await f.req(member,'GET','/v1/me')).status,401);assert.equal((await f.db.query('SELECT state FROM tomi_voice_rooms WHERE id=?',[room.id])).rows[0].state,'closed');
});
test('0.12 suspension hides account search, feed posts and ranking entries without erasing gifts',async t=>{
  const f=await fixture(t),{owner,member,mod}=await people(f),room=await f.create(mod);await f.post(member);await f.req(mod,'POST',`/v1/rooms/${room.id}/join`,{});await f.req(member,'POST',`/v1/rooms/${room.id}/join`,{});
  await f.req(member,'POST',`/v1/rooms/${room.id}/gift`,{giftId:'diamond',quantity:1,recipientId:mod.user.id,requestId:randomUUID()});
  assert.equal((await f.req(owner,'GET','/v1/community/ranking')).data.leaders.length,1);await f.command(owner,'suspend_user',member.user.id);
  assert.equal((await f.req(owner,'GET','/v1/users?q=member12')).data.users.length,0);assert.equal((await f.req(owner,'GET','/v1/posts')).data.posts.length,0);assert.equal((await f.req(owner,'GET','/v1/community/ranking')).data.leaders.length,0);
  assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_room_all_gifts')).rows[0].n),1);
});
test('0.12 a call request authenticated before suspension cannot create a late call after the ban commits',async t=>{
  const f=await fixture(t),{owner,member,mod}=await people(f),thread=(await f.req(member,'POST','/v1/chats',{userId:mod.user.id})).data.conversation;
  const body=JSON.stringify({conversationId:thread.id,requestId:randomUUID(),kind:'audio'});
  let incoming;
  const result=new Promise((resolve,reject)=>{
    incoming=httpRequest(f.base+'/v1/calls',{method:'POST',headers:{authorization:'Bearer '+member.token,'content-type':'application/json','content-length':Buffer.byteLength(body)}},response=>{const chunks=[];response.on('data',c=>chunks.push(c));response.on('end',()=>resolve({status:response.statusCode,data:JSON.parse(Buffer.concat(chunks).toString())}));});incoming.on('error',reject);incoming.write(body.slice(0,-6));
  });
  let started=false;
  for(let i=0;i<100&&!started;i++){started=(await f.db.query('SELECT 1 FROM tomi_rate_limits WHERE bucket_key=?',[digest('call-start:'+member.user.id)])).rows.length>0;if(!started)await new Promise(r=>setTimeout(r,5));}
  assert.equal(started,true);assert.equal((await f.command(owner,'suspend_user',member.user.id)).status,200);incoming.end(body.slice(-6));assert.equal((await result).status,401);
  assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_calls')).rows[0].n),0);
  assert.equal((await f.req(mod,'POST','/v1/calls',{conversationId:thread.id,requestId:randomUUID(),kind:'audio'})).status,403);
});
test('0.12 room closure works without joining and provider failures do not clear pending revocations',async t=>{
  const f=await fixture(t),{owner,member,mod}=await people(f),r=await f.create(member);await f.req(member,'POST',`/v1/rooms/${r.id}/join`,{});await f.command(owner,'grant_moderator',mod.user.id);f.providerFails=true;
  assert.equal((await f.command(mod,'close_room',r.id)).status,200);assert.equal((await f.req(member,'GET','/v1/rooms')).data.rooms.length,0);assert.ok(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_voice_jobs')).rows[0].n)>0);
  assert.equal((await f.command(member,'close_room',r.id)).status,403);f.providerFails=false;for(let i=0;i<3;i++)await f.server.flushRooms();assert.ok(f.removed.length>0);
});
test('0.12 report and audit keyset pages are private and do not skip equal timestamps',async t=>{
  const f=await fixture(t),{owner,member}=await people(f),stamp='2026-01-01T00:00:00.000Z';
  for(let i=0;i<25;i++){const rid=randomUUID();await f.db.query('INSERT INTO tomi_reports(id,reporter_id,target_type,target_id,subject_user_id,reason,description,snapshot,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?)',[rid,member.user.id,'account',randomUUID(),owner.user.id,'other','text','{}',stamp,stamp]);}
  const seen=[];let cursor;do{const data=(await f.req(member,'GET','/v1/reports'+(cursor?'?before='+encodeURIComponent(cursor):''))).data;seen.push(...data.items.map(r=>r.id));cursor=data.nextBefore;}while(cursor);assert.equal(seen.length,25);assert.equal(new Set(seen).size,25);assert.equal((await f.req(owner,'GET','/v1/reports')).data.items.length,0);
  assert.equal((await f.req(owner,'GET','/v1/admin/reports?status=forged')).status,400);assert.equal((await f.req(owner,'GET','/v1/admin/audit?before=bad')).status,400);
});
test('0.12 metrics are authorized aggregate measurements and never include request URLs, bodies or credentials',async t=>{
  const f=await fixture(t),{owner,member}=await people(f);await f.req(member,'GET','/not-a-route?secret=never-in-metrics');const original=f.db.query;
  f.db.query=async(sql,args)=>{if(sql==='SELECT 1 AS ready')throw Error('not logged secret');return original(sql,args);};assert.equal((await f.req(null,'GET','/health')).status,503);f.db.query=original;
  const result=await f.req(owner,'GET','/v1/admin/metrics');assert.equal(result.status,200);assert.ok(result.data.requests.serverErrors>=1);assert.ok(result.data.process.rssBytes>0);assert.equal(result.data.scope,'this_api_process');
  const encoded=JSON.stringify(result.data);for(const forbidden of ['never-in-metrics',owner.token,member.token,'password_hash','recovery_hash'])assert.ok(!encoded.includes(forbidden));assert.equal((await f.req(member,'GET','/v1/admin/metrics')).status,403);
});
test('0.12 strict report/action validation never changes ledger or audit on denied inputs',async t=>{
  const f=await fixture(t),{owner,member}=await people(f),p=await f.post(member);
  for(const change of [{targetType:'message'},{targetId:'forged'},{reason:'forged'},{role:'owner'},{description:'x'.repeat(1001)}])assert.equal((await f.report(owner,'post',p.id,change)).status,400);
  assert.equal((await f.command(owner,'hide_post',p.id,{expectedRevision:-1})).status,400);assert.equal((await f.command(owner,'hide_post',p.id,{xp:9000})).status,400);assert.equal(await f.auditCount(),0);
});
test('0.12 exact additive0.11 upgrade retains account credentials, identity and user progress',async t=>{
  const old=await readFile(new URL('fixtures/schema-0.11.sql',import.meta.url),'utf8'),current=await readFile(new URL('../schema.sql',import.meta.url),'utf8');assert.ok(current.startsWith(old));
  const dir=await mkdtemp(join(tmpdir(),'tomi12-upgrade-'));t.after(()=>rm(dir,{recursive:true,force:true}));const path=join(dir,'old.sqlite'),raw=new DatabaseSync(path),uid=randomUUID(),stamp=new Date().toISOString();raw.exec(old);raw.prepare('INSERT INTO tomi_users(id,username,display_name,password_hash,recovery_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?)').run(uid,'upgrade12','Upgrade','hash-kept','recovery-kept',stamp,stamp);raw.prepare('INSERT INTO tomi_user_progress(user_id,spent) VALUES(?,200)').run(uid);raw.prepare("INSERT INTO tomi_user_identity(user_id,frame_id) VALUES(?,'rose')").run(uid);raw.close();
  const db=await openDatabase({sqliteFile:path});try{const user=(await db.query('SELECT password_hash FROM tomi_users WHERE id=?',[uid])).rows[0];assert.equal(user.password_hash,'hash-kept');assert.equal(Number((await db.query('SELECT spent FROM tomi_user_progress WHERE user_id=?',[uid])).rows[0].spent),200);assert.equal((await db.query('SELECT frame_id FROM tomi_user_identity WHERE user_id=?',[uid])).rows[0].frame_id,'rose');assert.equal(Number((await db.query('SELECT COUNT(*) n FROM tomi_platform_roles')).rows[0].n),0);}finally{await db.close();}
});
