import {policyVersion} from '../src/privacy.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {randomUUID} from 'node:crypto';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {request as httpRequest} from 'node:http';
import {Script} from 'node:vm';
import {openDatabase} from '../src/database.mjs';
import {createApp} from '../src/app.mjs';
import {newToken,digest} from '../src/security.mjs';
import {iceFromEnvironment} from '../src/ice.mjs';
import {privacyEnvironment,privacyDocuments} from '../src/privacy.mjs';
import {createPrivacy} from '../src/privacy.mjs';
import {DatabaseSync} from 'node:sqlite';

const password='test-only privacy beta1 passphrase',connectionString=process.env.TEST_DATABASE_URL;
if(connectionString){const u=new URL(connectionString);assert.ok(['localhost','127.0.0.1'].includes(u.hostname)&&u.pathname==='/tomi_test');}
async function fixture(t,{separate=false}={}){
  const dir=await mkdtemp(join(tmpdir(),'tomi-privacy10-'));let db,server,base,ownerUserId=null,tick=Date.now(),fails=false;
  const deleted=[],privateDeleted=[],objects=new Set();
  const store={prepare:u=>({uploadUrl:'https://files.test/'+u.id,headers:{},expiresIn:900}),readUrl:key=>'https://files.test/'+key,avatarUrl:key=>'https://files.test/'+key,privateReadUrl:key=>'https://private.test/'+key,
    async delete(key){if(fails)throw Error('offline');deleted.push(key);objects.delete(key);}};
  const privateStore={...store,async delete(key){if(fails)throw Error('offline');privateDeleted.push(key);objects.delete(key);}};
  const provider={ensure:async()=>{},grant:async(r,m)=>({url:'wss://test.livekit.cloud',identity:m.identity,token:'test-only'}),permissions:async()=>{},remove:async()=>{if(fails)throw Error('offline');},close:async()=>{if(fails)throw Error('offline');}};
  async function start(reset=false){
    db=await openDatabase({connectionString,sqliteFile:join(dir,'state.sqlite')});
    if(reset&&connectionString){await db.query('DELETE FROM tomi_users');await db.query('DELETE FROM tomi_rate_limits');await db.query('DELETE FROM tomi_admin_audit');await db.query('DELETE FROM tomi_privacy_retention');}
    server=await createApp({database:db,ownerUserId,storage:store,chatStorage:separate?privateStore:store,roomProvider:provider,iceProvider:iceFromEnvironment({CALL_TURN_URLS:'turn:relay.example.com:3478',CALL_TURN_SECRET:'test-only-'.repeat(5)}),pushAutoFlush:false,callAutoSweep:false,roomAutoSweep:false,deletionAutoSweep:false,deletionClock:()=>tick,rateLimitMultiplier:100});
    server.listen(0,'127.0.0.1');await once(server,'listening');base='http://127.0.0.1:'+server.address().port;
  }
  async function stop(){const done=once(server,'close');server.close();server.closeIdleConnections();await done;await db.close();}
  await start(true);t.after(async()=>{await stop();await rm(dir,{recursive:true,force:true});});
  return {get db(){return db;},get server(){return server;},get base(){return base;},store,objects,deleted,privateDeleted,set fails(x){fails=x;},advance(ms){tick+=ms;},async restart(owner=ownerUserId){await stop();ownerUserId=owner;await start();},
    async req(a,method,path,body,headers={}){const r=await fetch(base+path,{method,headers:{...(a?{authorization:'Bearer '+a.token}:{}),...(body===undefined?{}:{'content-type':'application/json'}),...headers},...(body===undefined?{}:{body:JSON.stringify(body)})});return {status:r.status,data:await r.json()};},
    async register(username){const r=await this.req(null,'POST','/v1/auth/register',{username,displayName:username,password});assert.equal(r.status,201);return r.data;},
    command(a,action,targetId,extra={}){return this.req(a,'POST','/v1/admin/actions',{requestId:randomUUID(),action,targetId,reason:'سبب اختبار الخصوصية',expectedRevision:0,...extra});},
    request(){return {requestId:randomUUID(),receiptToken:newToken(),password,confirmation:'حذف حسابي'};},
    status(d){return this.req(null,'POST','/v1/account/deletion/status',{requestId:d.requestId,receiptToken:d.receiptToken});},
    async image(a,prefix='tomi/posts/'){
      const id=randomUUID(),key=prefix+a.user.id+'/'+id+'.png',stamp=new Date().toISOString();objects.add(key);
      await db.query("INSERT INTO tomi_image_uploads(id,user_id,object_key,content_type,byte_length,content_md5,state,width,height,created_at,expires_at) VALUES(?,?,?,'image/png',100,'test-only','attached',10,10,?,?)",[id,a.user.id,key,stamp,stamp]);
      await db.query('INSERT INTO tomi_upload_digests(upload_id,sha256,created_at) VALUES(?,?,?)',[id,'a'.repeat(64),stamp]);return{id,key};
    },
  };
}

test('1.0 account erasure requires the current password, exact confirmation and a private receipt proof',async t=>{
  const f=await fixture(t),a=await f.register('privacy_one'),d=f.request();
  assert.equal((await f.req(a,'POST','/v1/account/deletion',{...d,password:'wrong'})).status,400);
  assert.equal((await f.req(a,'POST','/v1/account/deletion',{...d,confirmation:'yes'})).status,400);
  assert.equal((await f.req(a,'POST','/v1/account/deletion',{...d,userId:a.user.id})).status,400);
  assert.equal((await f.req(null,'POST','/v1/account/deletion',d)).status,401);
  const r=await f.req(a,'POST','/v1/account/deletion',d);assert.equal(r.status,202,JSON.stringify(r.data));assert.equal(r.data.personalDataErased,true);
  assert.equal((await f.req(a,'GET','/v1/me')).status,401);
  const replay=await f.req(a,'POST','/v1/account/deletion',d);assert.equal(replay.status,200);assert.equal(replay.data.requestId,d.requestId);
  assert.equal((await f.status({...d,receiptToken:newToken()})).status,404);
  const status=await f.status(d);assert.ok(!JSON.stringify(status.data).includes(a.user.id));assert.ok(!JSON.stringify(status.data).includes(a.user.username));
  assert.equal((await f.req(null,'POST','/v1/auth/login',{username:a.user.username,password})).status,401);
  assert.equal((await f.req(null,'POST','/v1/auth/recover',{username:a.user.username,password,recoveryCode:a.recoveryCode})).status,400);
  const reused=await f.register('privacy_one');assert.notEqual(reused.user.id,a.user.id);await f.req(reused,'POST','/v1/account/deletion',d);assert.equal((await f.req(reused,'GET','/v1/me')).status,200);
  assert.equal((await f.req(reused,'POST','/v1/reports',{requestId:randomUUID(),targetType:'account',targetId:a.user.id,reason:'harassment',description:'test-only'})).status,410);
});

test('1.0 erasure clears authored data and private links while preserving the peer and opaque shared gift ledger',async t=>{
  const f=await fixture(t),a=await f.register('privacy_author'),b=await f.register('privacy_peer'),stamp=new Date().toISOString();
  const post=(await f.req(a,'POST','/v1/posts',{text:'private authored post',requestId:randomUUID()})).data.post;
  await f.req(a,'PUT','/v1/users/'+b.user.id+'/follow',{follow:true});
  const thread=(await f.req(a,'POST','/v1/chats',{userId:b.user.id})).data.conversation;
  const m=(await f.req(a,'POST','/v1/chats/'+thread.id+'/messages',{text:'private authored message',requestId:randomUUID()})).data.message;
  const peer=(await f.req(b,'POST','/v1/chats/'+thread.id+'/messages',{text:'peer message stays',requestId:randomUUID()})).data.message;
  const image=await f.image(a,'tomi/avatars/');await f.db.query('INSERT INTO tomi_user_avatars(user_id,upload_id) VALUES(?,?)',[a.user.id,image.id]);
  const room=(await f.req(a,'POST','/v1/rooms',{title:'private room title',requestId:randomUUID(),capacity:10,seatCount:4})).data.room;
  await f.db.query('INSERT INTO tomi_room_gifts(id,room_id,sender_id,recipient_id,request_id,gift_id,quantity,unit_price,total,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)',[randomUUID(),room.id,a.user.id,b.user.id,randomUUID(),'diamond',1,100,100,stamp]);
  await f.db.query('INSERT INTO tomi_user_progress(user_id,spent) VALUES(?,100) ON CONFLICT(user_id) DO UPDATE SET spent=100',[a.user.id]);
  await f.db.query('INSERT INTO tomi_room_wallets(user_id,coins,next_claim) VALUES(?,500,?) ON CONFLICT(user_id) DO UPDATE SET coins=500',[a.user.id,stamp]);
  const d=f.request();assert.equal((await f.req(a,'POST','/v1/account/deletion',d)).status,202);
  assert.equal((await f.req(b,'GET','/v1/posts/'+post.id)).status,404);
  const messages=(await f.req(b,'GET','/v1/chats/'+thread.id+'/messages')).data.messages;
  assert.equal(messages.find(x=>x.id===m.id).deleted,true);assert.equal(messages.find(x=>x.id===m.id).text,'');assert.equal(messages.find(x=>x.id===peer.id).text,'peer message stays');
  assert.equal((await f.req(b,'POST','/v1/chats/'+thread.id+'/messages',{text:'late',requestId:randomUUID()})).status,403);
  assert.equal((await f.req(b,'PUT','/v1/users/'+a.user.id+'/follow',{follow:true})).status,410);
  const stub=(await f.db.query('SELECT * FROM tomi_users WHERE id=?',[a.user.id])).rows[0];assert.equal(stub.display_name,'حساب محذوف');assert.equal(stub.bio,'');assert.notEqual(stub.password_hash,undefined);assert.ok(stub.password_hash.startsWith('erased:'));
  for(const table of ['tomi_user_avatars','tomi_follows','tomi_user_progress','tomi_room_wallets','tomi_sessions'])assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM '+table)).rows[0].n),table==='tomi_sessions'?1:0);
  assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_room_gifts')).rows[0].n),1);assert.equal((await f.db.query('SELECT title,state FROM tomi_voice_rooms WHERE id=?',[room.id])).rows[0].state,'closed');
  await f.restart();assert.equal((await f.db.query('SELECT 1 FROM tomi_user_progress WHERE user_id=?',[a.user.id])).rows.length,0);
});

test('1.0 file cleanup survives provider failure and restart and deletes again after signed PUT expiry',async t=>{
  const f=await fixture(t),a=await f.register('privacy_media'),image=await f.image(a),d=f.request();f.fails=true;
  assert.equal((await f.req(a,'POST','/v1/account/deletion',d)).data.pendingMedia,1);await f.server.sweepDeletions();assert.equal(f.objects.has(image.key),true);
  await f.restart();f.fails=false;f.advance(60000);await f.server.sweepDeletions();assert.equal(f.objects.has(image.key),false);assert.equal((await f.status(d)).data.pendingMedia,1);
  f.objects.add(image.key);f.advance(16*60000);await f.server.sweepDeletions();assert.equal(f.objects.has(image.key),false);assert.equal(f.deleted.filter(k=>k===image.key).length,2);
  assert.equal((await f.status(d)).data.state,'completed');assert.equal((await f.db.query('SELECT 1 FROM tomi_upload_digests WHERE upload_id=?',[image.id])).rows.length,0);
});

test('1.0 protected owner must transfer ownership; suspended members can delete with browser credentials',async t=>{
  const f=await fixture(t),owner=await f.register('privacy_owner'),a=await f.register('privacy_banned');await f.restart(owner.user.id);
  assert.equal((await f.req(owner,'GET','/v1/account/deletion/preview')).data.ownerTransferRequired,true);
  assert.equal((await f.req(owner,'POST','/v1/account/deletion',f.request())).data.error.code,'OWNER_TRANSFER_REQUIRED');
  await f.command(owner,'suspend_user',a.user.id);const d=f.request();assert.equal((await f.req(null,'POST','/v1/account/deletion/web',{...d,username:a.user.username})).status,202);
  assert.equal((await f.command(owner,'restore_user',a.user.id,{expectedRevision:1})).status,410);assert.equal((await f.command(owner,'grant_moderator',a.user.id)).status,410);
  assert.equal((await f.req(owner,'GET','/v1/me')).status,200);
});

test('1.0 same accepted deletion receipt is safe under concurrent retry',async t=>{
  const f=await fixture(t),a=await f.register('privacy_retry'),d=f.request();
  const results=await Promise.all([f.req(a,'POST','/v1/account/deletion',d),f.req(a,'POST','/v1/account/deletion',d)]);
  assert.ok(results.every(r=>[200,202].includes(r.status)),JSON.stringify(results));assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_deleted_accounts')).rows[0].n),1);
});

test('1.0 authenticated delayed writes cannot recreate posts after account erasure commits',async t=>{
  const f=await fixture(t),a=await f.register('privacy_race'),body=JSON.stringify({requestId:randomUUID(),text:'late private body'}),target=new URL(f.base);
  let finish;const pending=new Promise((resolve,reject)=>{const req=httpRequest({hostname:target.hostname,port:target.port,path:'/v1/posts',method:'POST',headers:{authorization:'Bearer '+a.token,'content-type':'application/json','content-length':Buffer.byteLength(body)}},res=>{let text='';res.on('data',b=>text+=b);res.on('end',()=>resolve({status:res.statusCode,data:JSON.parse(text)}));});req.on('error',reject);req.write(body.slice(0,5));finish=()=>req.end(body.slice(5));});
  const deadline=Date.now()+3000;while(Date.now()<deadline){if((await f.db.query('SELECT 1 FROM tomi_rate_limits WHERE bucket_key=?',[digest('posts:'+a.user.id)])).rows.length)break;await new Promise(setImmediate);}
  assert.equal((await f.req(null,'POST','/v1/account/deletion/web',{...f.request(),username:a.user.username})).status,202);finish();
  assert.equal((await pending).status,401);assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_posts WHERE user_id=?',[a.user.id])).rows[0].n),0);
});

test('1.0 report and audit content is scrubbed and bounded security retention and receipt expiry are enforced',async t=>{
  const f=await fixture(t),owner=await f.register('privacy_audit'),a=await f.register('privacy_target');await f.restart(owner.user.id);
  const report=(await f.req(owner,'POST','/v1/reports',{requestId:randomUUID(),targetType:'account',targetId:a.user.id,reason:'other',description:'private user details'})).data.report;
  await f.command(owner,'review_report',report.id,{status:'resolved',note:'private details',publicMessage:'public details'});
  await f.command(owner,'suspend_user',a.user.id);
  const d=f.request();assert.equal((await f.req(null,'POST','/v1/account/deletion/web',{...d,username:a.user.username})).status,202);
  const r=(await f.db.query('SELECT * FROM tomi_reports WHERE id=?',[report.id])).rows[0];assert.equal(r.snapshot,'{}');assert.equal(r.description,'');assert.equal(r.review_note,'');
  const audit=(await f.db.query('SELECT * FROM tomi_admin_audit WHERE target_id=?',[a.user.id])).rows[0];assert.equal(audit.details,'{}');assert.equal(audit.reason,'حُذفت البيانات الشخصية');
  f.advance(91*86400000);await f.server.sweepDeletions();assert.equal((await f.db.query('SELECT 1 FROM tomi_reports WHERE id=?',[report.id])).rows.length,0);assert.equal((await f.status(d)).status,404);
});

test('1.0 public privacy/terms/deletion resources need no app and prevent cross-origin credential submission',async t=>{
  const f=await fixture(t);
  for(const path of ['/privacy','/terms','/community-guidelines','/account/delete']){const r=await fetch(f.base+path);assert.equal(r.status,200);assert.match(r.headers.get('content-security-policy'),/frame-ancestors 'none'/);const text=await r.text();assert.match(text,/TOMI/);assert.ok(!text.includes('test-only privacy beta1 passphrase'));if(path==='/account/delete'){assert.match(text,/<form method="post">/);const script=text.match(/<script nonce="[^"]+">([\s\S]*?)<\/script>/);assert.ok(script);assert.doesNotThrow(()=>new Script(script[1]));assert.match(text,/\/v1\/account\/deletion\/web/);assert.ok(!text.includes('localStorage.setItem(\'password'));}}
  const documents=await f.req(null,'GET','/v1/privacy/documents');assert.equal(documents.status,200);assert.equal(documents.data.publicationReady,false);assert.equal(documents.data.documents.length,4);
  const a=await f.register('privacy_origin'),d={...f.request(),username:a.user.username};
  assert.equal((await f.req(null,'POST','/v1/account/deletion/web',d,{origin:'https://evil.test'})).status,403);
  assert.equal((await f.req(null,'POST','/v1/account/deletion/web',d,{origin:f.base})).status,202);
});

test('1.0 public policy configuration validates contact and retention and escapes operator supplied markup',()=>{
  assert.equal(privacyEnvironment({}).publicationReady,false);
  assert.throws(()=>privacyEnvironment({TOMI_SUPPORT_EMAIL:'javascript:alert(1)'}));
  assert.throws(()=>privacyEnvironment({TOMI_PUBLIC_URL:'http://public.example'}));
  assert.throws(()=>privacyEnvironment({TOMI_BACKUP_RETENTION_DAYS:'0'}));
  const c=privacyEnvironment({TOMI_OPERATOR_NAME:'TOMI Test Operator',TOMI_SUPPORT_EMAIL:'support@example.test',TOMI_PUBLIC_URL:'https://api.example.test',TOMI_BACKUP_RETENTION_DAYS:'30'});assert.equal(c.publicationReady,true);assert.match(privacyDocuments(c).documents[0].sections.find(x=>x.title==='النسخ وروابط الملفات').text,/30/);
  let html='';createPrivacy({...c,operatorName:'<script>unsafe</script>'}).handle({method:'GET'},{writeHead(){},end(s){html=s;}},new URL('https://api.example.test/privacy'));assert.ok(html.includes('&lt;script&gt;unsafe&lt;/script&gt;'));assert.ok(!html.includes('<script>unsafe</script>'));
});

test('1.0 deletion routes image/audio/video cleanup to the correct private bucket and preserves other users files',async t=>{
  const f=await fixture(t,{separate:true}),a=await f.register('privacy_types'),b=await f.register('privacy_keep'),stamp=new Date().toISOString();
  const thread=(await f.req(a,'POST','/v1/chats',{userId:b.user.id})).data.conversation;
  const avatar=await f.image(a,'tomi/avatars/'),image=await f.image(a,'tomi/chat-images/'+thread.id+'/'),other=await f.image(b);
  await f.db.query('INSERT INTO tomi_user_avatars(user_id,upload_id) VALUES(?,?)',[a.user.id,avatar.id]);
  const im=(await f.req(a,'POST','/v1/chats/'+thread.id+'/messages',{text:'image',requestId:randomUUID()})).data.message;await f.db.query('UPDATE tomi_chat_messages SET image_upload_id=? WHERE id=?',[image.id,im.id]);
  const privateKeys=[image.key];
  for(const type of ['audio','video']){
    const id=randomUUID(),key=`tomi/chat-${type==='audio'?'audio':'videos'}/${thread.id}/${a.user.id}/${id}.${type==='audio'?'m4a':'mp4'}`;privateKeys.push(key);f.objects.add(key);
    await f.db.query(`INSERT INTO tomi_${type}_uploads(id,user_id,thread_id,object_key,content_type,byte_length,content_md5,duration_ms,state,created_at,expires_at) VALUES(?,?,?,?,?,100,'test-only',500,'attached',?,?)`,[id,a.user.id,thread.id,key,type==='audio'?'audio/mp4':'video/mp4',stamp,stamp]);
    const m=(await f.req(a,'POST','/v1/chats/'+thread.id+'/messages',{text:type,requestId:randomUUID()})).data.message;
    await f.db.query('INSERT INTO tomi_chat_'+type+'(message_id,upload_id) VALUES(?,?)',[m.id,id]);
  }
  const d=f.request();assert.equal((await f.req(a,'POST','/v1/account/deletion',d)).data.pendingMedia,4);await f.server.sweepDeletions();
  assert.deepEqual(f.deleted,[avatar.key]);assert.deepEqual(f.privateDeleted.sort(),privateKeys.sort());assert.equal(f.objects.has(other.key),true);
  f.advance(16*60000+1);await f.server.sweepDeletions();assert.equal((await f.status(d)).data.pendingMedia,0);assert.equal(f.objects.has(other.key),true);
  for(const type of ['image','audio','video'])assert.equal((await f.db.query('SELECT 1 FROM tomi_'+type+'_uploads WHERE user_id=?',[a.user.id])).rows.length,0);
});

test('1.0 delayed follow cannot recreate a relationship with an erased target',async t=>{
  const f=await fixture(t),a=await f.register('privacy_follow_a'),b=await f.register('privacy_follow_b'),body=JSON.stringify({follow:true}),u=new URL(f.base);let finish;
  const pending=new Promise((resolve,reject)=>{const request=httpRequest({hostname:u.hostname,port:u.port,path:'/v1/users/'+a.user.id+'/follow',method:'PUT',headers:{authorization:'Bearer '+b.token,'content-type':'application/json','content-length':Buffer.byteLength(body)}},response=>{response.resume();response.on('end',()=>resolve(response.statusCode));});request.on('error',reject);request.write(body.slice(0,4));finish=()=>request.end(body.slice(4));});
  const deadline=Date.now()+2000;while(Date.now()<deadline){if((await f.db.query('SELECT 1 FROM tomi_rate_limits WHERE bucket_key=?',[digest('requests:user:'+b.user.id)])).rows.length)break;await new Promise(setImmediate);}
  assert.equal((await f.req(a,'POST','/v1/account/deletion',f.request())).status,202);finish();assert.equal(await pending,410);assert.equal((await f.db.query('SELECT 1 FROM tomi_follows WHERE following_id=?',[a.user.id])).rows.length,0);
});

test('1.0 policy acceptance stores only the current version and erases its account-bound receipt',async t=>{
  const f=await fixture(t),base={username:'privacy_accept',displayName:'Accepted',password};
  assert.equal((await f.req(null,'POST','/v1/auth/register',{...base,policyVersion:'wrong-version'})).status,400);
  const a=(await f.req(null,'POST','/v1/auth/register',{...base,policyVersion})).data;
  assert.equal((await f.db.query('SELECT policy_version FROM tomi_policy_acceptances WHERE user_id=?',[a.user.id])).rows[0].policy_version,policyVersion);
  await f.req(a,'POST','/v1/account/deletion',f.request());assert.equal((await f.db.query('SELECT 1 FROM tomi_policy_acceptances WHERE user_id=?',[a.user.id])).rows.length,0);
});

test('1.0 upgrades the exact0.12 SQLite schema without changing live credentials, roles, reports or gift progress',async t=>{
  const old=await readFile(new URL('fixtures/schema-0.12.sql',import.meta.url),'utf8'),current=await readFile(new URL('../schema.sql',import.meta.url),'utf8');assert.ok(current.startsWith(old));
  const directory=await mkdtemp(join(tmpdir(),'tomi-upgrade-beta-'));t.after(()=>rm(directory,{recursive:true,force:true}));const file=join(directory,'state.sqlite'),raw=new DatabaseSync(file),id=randomUUID(),reporter=randomUUID(),stamp=new Date().toISOString();raw.exec(old);
  for(const uid of [id,reporter])raw.prepare('INSERT INTO tomi_users(id,username,display_name,password_hash,recovery_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?)').run(uid,'upgrade_'+uid.slice(0,8),'Retained','retained-hash','retained-recovery',stamp,stamp);
  raw.prepare('INSERT INTO tomi_platform_roles(user_id,role,revision,granted_by,updated_at) VALUES(?,?,2,?,?)').run(id,'moderator',reporter,stamp);
  raw.prepare('INSERT INTO tomi_user_progress(user_id,spent) VALUES(?,200)').run(id);
  raw.prepare('INSERT INTO tomi_reports(id,reporter_id,target_type,target_id,subject_user_id,reason,description,snapshot,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?)').run(randomUUID(),reporter,'account',id,id,'other','unchanged report','{}',stamp,stamp);raw.close();
  const db=await openDatabase({sqliteFile:file});try{assert.equal((await db.query('SELECT password_hash FROM tomi_users WHERE id=?',[id])).rows[0].password_hash,'retained-hash');assert.equal((await db.query('SELECT role FROM tomi_platform_roles WHERE user_id=?',[id])).rows[0].role,'moderator');assert.equal(Number((await db.query('SELECT spent FROM tomi_user_progress WHERE user_id=?',[id])).rows[0].spent),200);assert.equal((await db.query('SELECT description FROM tomi_reports')).rows[0].description,'unchanged report');assert.equal((await db.query('SELECT 1 FROM tomi_deleted_accounts')).rows.length,0);}finally{await db.close();}
});
