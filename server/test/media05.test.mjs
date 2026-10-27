import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHash,generateKeyPairSync,verify} from 'node:crypto';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {once} from 'node:events';
import {openDatabase} from '../src/database.mjs';
import {createApp} from '../src/app.mjs';
import {R2Images} from '../src/r2.mjs';
import {audioMetadata} from '../src/audio.mjs';
import {fcmFromEnvironment} from '../src/push.mjs';
const connectionString=process.env.TEST_DATABASE_URL;
if(connectionString){const u=new URL(connectionString);assert.ok(['localhost','127.0.0.1'].includes(u.hostname)&&u.pathname==='/tomi_test','Tests require a local tomi_test database');}
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jftkAAAAASUVORK5CYII=','base64');
const md5=b=>createHash('md5').update(b).digest('base64');
function box(type,...children){const data=Buffer.concat(children),head=Buffer.alloc(8);head.writeUInt32BE(data.length+8);head.write(type,4);return Buffer.concat([head,data]);}
function recording(ms=5000){
 const mdhd=Buffer.alloc(24);mdhd.writeUInt32BE(1000,12);mdhd.writeUInt32BE(ms,16);
 const hdlr=Buffer.alloc(24);hdlr.write('soun',8);
 const sample=Buffer.alloc(28);sample.writeUInt16BE(1,16);
 const stsd=Buffer.alloc(8);stsd.writeUInt32BE(1,4);
 const entry=box('mp4a',sample,box('esds',Buffer.from([0,0,0,0,3,0])));
 const stbl=box('stbl',box('stsd',stsd,entry));
 const mdia=box('mdia',box('mdhd',mdhd),box('hdlr',hdlr),box('minf',stbl));
 return Buffer.concat([box('ftyp',Buffer.from([77,52,65,32,0,0,0,0])),box('mdat',Buffer.from([0,1,2,3])),box('moov',box('trak',mdia))]);
}

async function fixture(t,{push=false,separate=false}={}){
 const directory=await mkdtemp(join(tmpdir(),'tomi05-')),objects=new Map(),privateObjects=new Map(),sent=[];
 const storageFor=(bucket,map)=>new R2Images({endpoint:'https://'+'a'.repeat(32)+'.r2.cloudflarestorage.com',bucket,accessKeyId:'test',secretAccessKey:'test'},{fetcher:async(url,opts)=>{const key=decodeURIComponent(new URL(url).pathname.slice(bucket.length+2));if(opts?.method==='DELETE'){map.delete(key);return new Response(null,{status:204});}const item=map.get(key);return item?new Response(item.bytes,{headers:{'content-type':item.type,'content-length':String(item.bytes.length)}}):new Response(null,{status:404});}});
 const storage=storageFor('feed-test',objects),chatStorage=separate?storageFor('chat-test',privateObjects):storage;let db,server,base,sender=push?async d=>{sent.push(d);return 'sent';}:null;
 async function start(){db=await openDatabase({connectionString:process.env.TEST_DATABASE_URL,sqliteFile:join(directory,'test.sqlite')});server=await createApp({database:db,storage,chatStorage,pushSender:sender,pushAutoFlush:false,rateLimitMultiplier:20});server.listen(0,'127.0.0.1');await once(server,'listening');base='http://127.0.0.1:'+server.address().port;}
 async function stop(){const done=new Promise((resolve,reject)=>server.close(e=>e?reject(e):resolve()));server.closeIdleConnections();await done;await db.close();}
 await start();if(process.env.TEST_DATABASE_URL){await db.query('DELETE FROM tomi_users');await db.query('DELETE FROM tomi_rate_limits');}t.after(async()=>{await stop();await rm(directory,{recursive:true,force:true});});
 return{objects,privateObjects,sent,get db(){return db;},get server(){return server;},async restart(){await stop();await start();},setSender(fn){sender=fn;},async request(method,path,body,token){const r=await fetch(base+path,{method,headers:{...(body!==undefined?{'content-type':'application/json'}:{}),...(token?{authorization:'Bearer '+token}:{})},...(body!==undefined?{body:JSON.stringify(body)}:{})});return{status:r.status,data:await r.json()};},async register(name){const r=await this.request('POST','/v1/auth/register',{username:name,displayName:name,password:'a long TOMI 05 testing passphrase'});assert.equal(r.status,201);return r.data;},async upload(a,path,bytes,type,table,extra={}){const r=await this.request('POST',path,{contentType:type,byteLength:bytes.length,contentMd5:md5(bytes),...extra},a.token);assert.equal(r.status,201,JSON.stringify(r.data));const row=(await db.query('SELECT * FROM '+table+' WHERE id=?',[r.data.uploadId])).rows[0];(separate&&table==='tomi_audio_uploads'?privateObjects:objects).set(row.object_key,{bytes,type});return r.data;}};
}
const open=async(api,a,b)=>(await api.request('POST','/v1/chats',{userId:b.user.id},a.token)).data.conversation;
const send=(api,a,c,extra={})=>api.request('POST',`/v1/chats/${c.id}/messages`,{text:'',requestId:randomUUID(),...extra},a.token);
const device=(api,a,token='tomi_device_token_123456789012345')=>api.request('PUT','/v1/push/device',{token,platform:'android'},a.token);
test('voice upload is private, persists, retries once and cleans after deletion',async t=>{
 const api=await fixture(t,{separate:true}),a=await api.register('voice05a'),b=await api.register('voice05b'),c=await open(api,a,b),upload=await api.upload(a,`/v1/chats/${c.id}/audio`,recording(),'audio/mp4','tomi_audio_uploads',{durationMs:5000}),requestId=randomUUID();
 // Hold the first empty receipt read until the twin has attached its audio.
 const originalQuery=api.db.query;let release,observed,paused=false;
 const resume=new Promise(r=>release=r),miss=new Promise(r=>observed=r);
 api.db.query=async(sql,values=[])=>{const rows=await originalQuery(sql,values);if(!paused&&sql.startsWith('SELECT id,payload_hash FROM tomi_chat_messages')&&values[1]===requestId){paused=true;observed();await resume;}return rows;};
 let result;const retry=send(api,a,c,{audioUploadId:upload.uploadId,requestId});
 try{await Promise.race([miss,retry.then(()=>{throw Error('Retry finished before its receipt checkpoint');})]);const first=await send(api,a,c,{audioUploadId:upload.uploadId,requestId});release();result=[first,await retry];}
 finally{release();api.db.query=originalQuery;await retry.catch(()=>{});}
 assert.ok(result.every(x=>[200,201].includes(x.status)),JSON.stringify(result));assert.equal(result[0].data.message.id,result[1].data.message.id);assert.equal(result[0].data.message.audio.durationMs,5000);assert.equal(new URL(result[0].data.message.audio.url).searchParams.get('X-Amz-Expires'),'300');
 await api.restart();const history=await api.request('GET',`/v1/chats/${c.id}/messages`,undefined,b.token);assert.equal(history.data.messages.length,1);assert.equal(history.data.conversation.lastMessage,'🎤 رسالة صوتية');const mid=result[0].data.message.id;await api.request('DELETE',`/v1/chats/${c.id}/messages/${mid}`,undefined,a.token);assert.equal((await send(api,a,c,{audioUploadId:upload.uploadId,requestId})).data.message.audio,null);await api.server.cleanupMedia();assert.equal(api.privateObjects.size,1);await api.db.query("UPDATE tomi_audio_uploads SET expires_at=? WHERE state='deleting'",['2000-01-01T00:00:00.000Z']);await api.server.cleanupMedia();assert.equal(api.privateObjects.size,0);
});
test('voice validates checksum, M4A metadata, duration, ownership, thread and blocking',async t=>{
 assert.deepEqual(audioMetadata(recording()),{durationMs:5000});assert.throws(()=>audioMetadata(png));assert.throws(()=>audioMetadata(recording(400000)));const corrupt=recording();corrupt.writeUInt32BE(0xffffffff,0);assert.throws(()=>audioMetadata(corrupt));
 const api=await fixture(t),a=await api.register('voiceperm_a'),b=await api.register('voiceperm_b'),z=await api.register('voiceperm_z'),c=await open(api,a,b),other=await open(api,a,z),u=await api.upload(a,`/v1/chats/${c.id}/audio`,recording(),'audio/mp4','tomi_audio_uploads',{durationMs:5000});
 assert.equal((await send(api,b,c,{audioUploadId:u.uploadId})).status,400);assert.equal((await send(api,a,other,{audioUploadId:u.uploadId})).status,400);assert.equal((await send(api,a,c,{audioUploadId:u.uploadId,imageUploadId:randomUUID()})).status,400);
 const row=(await api.db.query('SELECT * FROM tomi_audio_uploads WHERE id=?',[u.uploadId])).rows[0];api.objects.set(row.object_key,{bytes:recording(6000),type:'audio/mp4'});assert.equal((await send(api,a,c,{audioUploadId:u.uploadId})).data.error.code,'INVALID_AUDIO');api.objects.set(row.object_key,{bytes:recording(),type:'audio/mp4'});await api.request('PUT','/v1/chat/blocks/'+b.user.id,{blocked:true},a.token);assert.equal((await send(api,a,c,{audioUploadId:u.uploadId})).status,403);
});
test('avatars enforce ownership and feature scope, idempotency and safe replacement',async t=>{
 const api=await fixture(t,{separate:true}),a=await api.register('avatar_a'),b=await api.register('avatar_b'),first=await api.upload(a,'/v1/me/avatar/uploads',png,'image/png','tomi_image_uploads'),requestId=randomUUID(),body={imageUploadId:first.uploadId,requestId};
 assert.equal((await api.request('PUT','/v1/me/avatar',body,b.token)).status,400);const saved=await api.request('PUT','/v1/me/avatar',body,a.token);assert.equal(saved.data.user.avatarId,first.uploadId);const post=await api.request('POST','/v1/posts',{text:'avatar',requestId:randomUUID()},a.token);assert.equal(post.data.post.author.avatarId,first.uploadId);const c=await open(api,b,a);assert.equal(c.peer.avatarId,first.uploadId);
 const second=await api.upload(a,'/v1/me/avatar/uploads',png,'image/png','tomi_image_uploads');await api.request('PUT','/v1/me/avatar',{imageUploadId:second.uploadId,requestId:randomUUID()},a.token);assert.equal((await api.request('PUT','/v1/me/avatar',body,a.token)).data.user.avatarId,second.uploadId);assert.equal((await api.request('PUT','/v1/me/avatar',{...body,imageUploadId:second.uploadId},a.token)).status,409);
 assert.equal((await api.request('POST','/v1/posts',{text:'',imageUploadId:second.uploadId,requestId:randomUUID()},a.token)).status,400);await api.server.cleanupMedia();assert.equal(api.objects.size,2);await api.db.query("UPDATE tomi_image_uploads SET expires_at=? WHERE state='deleting'",['2000-01-01T00:00:00.000Z']);await api.server.cleanupMedia();assert.equal(api.objects.size,1);await api.request('PUT','/v1/me/avatar',{imageUploadId:null,requestId:randomUUID()},a.token);assert.equal((await api.request('GET','/v1/me',undefined,a.token)).data.user.avatarUrl,null);
});
test('0.11 uploading a photo clears the animated portrait once and replay does not erase a later choice',async t=>{
 const api=await fixture(t),a=await api.register('photo11'),first=await api.upload(a,'/v1/me/avatar/uploads',png,'image/png','tomi_image_uploads');
 await api.db.query('INSERT INTO tomi_user_progress(user_id,spent) VALUES(?,200)',[a.user.id]);
 await api.request('PUT','/v1/me/identity',{frameId:'rose',portraitId:'panda',entranceId:'glow'},a.token);
 const body={imageUploadId:first.uploadId,requestId:randomUUID()};let saved=await api.request('PUT','/v1/me/avatar',body,a.token);assert.equal(saved.status,200);assert.equal(saved.data.user.identity.portraitId,'none');assert.equal(saved.data.user.identity.frameId,'rose');assert.equal(saved.data.user.identity.entranceId,'glow');assert.equal(saved.data.user.identity.revision,2);
 await api.request('PUT','/v1/me/identity',{portraitId:'panda',expectedRevision:2},a.token);
 saved=await api.request('PUT','/v1/me/avatar',body,a.token);assert.equal(saved.data.user.identity.portraitId,'panda');assert.equal(saved.data.user.identity.revision,3);
 saved=await api.request('PUT','/v1/me/avatar',{imageUploadId:null,requestId:randomUUID()},a.token);assert.equal(saved.data.user.identity.portraitId,'none');assert.equal(saved.data.user.identity.revision,4);
});
test('push outbox persists and replays do not enqueue duplicates; logout detaches device',async t=>{
 const api=await fixture(t,{push:true}),a=await api.register('push_a'),b=await api.register('push_b'),c=await open(api,a,b);assert.equal((await device(api,b)).status,200);const requestId=randomUUID();await send(api,a,c,{text:'private text',requestId});await send(api,a,c,{text:'private text',requestId});await api.restart();await api.server.flushPush();assert.equal(api.sent.length,1);await api.server.flushPush();assert.equal(api.sent.length,1);await api.request('POST','/v1/auth/logout',{},b.token);await send(api,a,c,{text:'after logout'});await api.server.flushPush();assert.equal(api.sent.length,1);assert.equal(Number((await api.db.query('SELECT COUNT(*) AS n FROM tomi_push_devices')).rows[0].n),0);
});
test('push suppresses read, deleted, blocked and opted-out notifications',async t=>{
 const api=await fixture(t,{push:true}),a=await api.register('quiet_a'),b=await api.register('quiet_b'),c=await open(api,a,b);await device(api,b);const first=await send(api,a,c,{text:'read'});await api.request('PUT',`/v1/chats/${c.id}/read`,{sequence:first.data.message.sequence},b.token);await api.server.flushPush();assert.equal(api.sent.length,0);
 const second=await send(api,a,c,{text:'delete'});await api.request('DELETE',`/v1/chats/${c.id}/messages/${second.data.message.id}`,undefined,a.token);await api.server.flushPush();assert.equal(api.sent.length,0);
 await send(api,a,c,{text:'block'});await api.request('PUT','/v1/chat/blocks/'+a.user.id,{blocked:true},b.token);await api.server.flushPush();assert.equal(api.sent.length,0);await api.request('PUT','/v1/chat/blocks/'+a.user.id,{blocked:false},b.token);await api.request('PUT','/v1/push/settings',{enabled:false},b.token);await send(api,a,c,{text:'disabled'});await api.server.flushPush();assert.equal(api.sent.length,0);
});
test('FCM uses OAuth, generic notification content and unregistered-device handling',async()=>{
 const {privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:2048});let oauth=0,posts=[];
 const sender=fcmFromEnvironment({FCM_SERVICE_ACCOUNT_JSON:JSON.stringify({type:'service_account',project_id:'tomi-test-project',client_email:'service@tomi-test-project.iam.gserviceaccount.com',private_key:privateKey.export({type:'pkcs8',format:'pem'})})},{fetcher:async(url,opts)=>{if(url.includes('oauth2')){oauth++;const jwt=opts.body.get('assertion'),parts=jwt.split('.');assert.ok(verify('RSA-SHA256',Buffer.from(parts.slice(0,2).join('.')),publicKey,Buffer.from(parts[2],'base64url')));return Response.json({access_token:'fake-oauth',expires_in:3600});}posts.push(JSON.parse(opts.body));return posts.length===1?Response.json({name:'sent'}):Response.json({error:{details:[{errorCode:'UNREGISTERED'}]}},{status:404});}});
 assert.equal(await sender({token:'token',threadId:randomUUID(),recipientId:randomUUID()}),'sent');assert.equal(await sender({token:'token',threadId:randomUUID(),recipientId:randomUUID()}),'invalid');assert.equal(oauth,1);assert.equal(posts[0].message.notification.body,'وصلتك رسالة جديدة في TOMI');assert.equal(posts[0].message.data.type,'chat');assert.equal(fcmFromEnvironment({}),null);assert.throws(()=>fcmFromEnvironment({FCM_SERVICE_ACCOUNT_JSON:'bad'}));
});
test('push retries a transient failure without resending to an accepted device',async t=>{
 const api=await fixture(t,{push:true}),a=await api.register('retry05_a'),b=await api.register('retry05_b'),c=await open(api,a,b);
 const second=(await api.request('POST','/v1/auth/login',{username:'retry05_b',password:'a long TOMI 05 testing passphrase'})).data;
 const firstToken='first_device_token_123456789',secondToken='second_device_token_123456789';await device(api,b,firstToken);await device(api,second,secondToken);
 const attempts=new Map();let allow=false,acceptedToken;api.setSender(async d=>{attempts.set(d.token,(attempts.get(d.token)||0)+1);acceptedToken??=d.token;if(d.token!==acceptedToken&&!allow)throw Error('Transient');return 'sent';});await api.restart();await send(api,a,c,{text:'retry notification'});await api.server.flushPush();
 assert.equal((await api.db.query('SELECT state FROM tomi_push_outbox')).rows[0].state,'pending');allow=true;await api.db.query('UPDATE tomi_push_outbox SET next_at=?',['2000-01-01T00:00:00.000Z']);await api.server.flushPush();assert.equal(attempts.get(acceptedToken),1);assert.equal(attempts.get(acceptedToken===firstToken?secondToken:firstToken),2);assert.equal((await api.db.query('SELECT state FROM tomi_push_outbox')).rows[0].state,'sent');
});
test('token refresh replaces the session device and ownership transfer isolates accounts',async t=>{
 const api=await fixture(t,{push:true}),a=await api.register('device05_a'),b=await api.register('device05_b'),z=await api.register('device05_z'),c=await open(api,a,b),d=await open(api,a,z);
 await device(api,b,'older_device_token_123456789');const token='newer_device_token_123456789';await device(api,b,token);assert.equal(Number((await api.db.query('SELECT COUNT(*) AS n FROM tomi_push_devices')).rows[0].n),1);
 await device(api,z,token);await api.request('DELETE','/v1/push/device',{token},b.token);await send(api,a,c,{text:'old account'});await api.server.flushPush();assert.equal(api.sent.length,0);await send(api,a,d,{text:'new owner'});await api.server.flushPush();assert.equal(api.sent.length,1);assert.equal(api.sent[0].recipientId,z.user.id);
 await api.db.query('UPDATE tomi_sessions SET expires_at=? WHERE user_id=?',['2000-01-01T00:00:00.000Z',z.user.id]);await send(api,a,d,{text:'expired'});await api.server.flushPush();assert.equal(api.sent.length,1);
});

test('0.9 FCM call data carries a deadline and cancellation without duplicate system notifications',async()=>{
 const {privateKey}=generateKeyPairSync('rsa',{modulusLength:2048}),posts=[];
 const sender=fcmFromEnvironment({FCM_SERVICE_ACCOUNT_JSON:JSON.stringify({type:'service_account',project_id:'tomi-test-project',client_email:'service@tomi-test-project.iam.gserviceaccount.com',private_key:privateKey.export({type:'pkcs8',format:'pem'})})},{fetcher:async(url,opts)=>{
  if(url.includes('oauth2'))return Response.json({access_token:'fake-oauth',expires_in:3600});posts.push(JSON.parse(opts.body).message);return Response.json({name:'sent'});
 }});
 const data={token:'test',threadId:randomUUID(),recipientId:randomUUID(),callId:randomUUID(),callProtocol:2,kind:'video',bindingId:'test-session-binding',expiresAt:Date.now()+25000};
 await sender(data);await sender({...data,cancel:true});await sender({...data,callProtocol:1});
 assert.equal(posts[0].notification,undefined);assert.equal(posts[0].android.notification,undefined);assert.equal(posts[0].data.expiresAt,String(data.expiresAt));assert.equal(posts[0].data.bindingId,data.bindingId);assert.equal(posts[0].data.type,'call');assert.equal(posts[0].data.kind,'video');assert.equal(posts[0].android.priority,'HIGH');
 assert.equal(posts[1].data.type,'call_cancel');assert.equal(posts[1].notification,undefined);assert.equal(posts[2].notification.body,'مكالمة واردة في TOMI');
});
