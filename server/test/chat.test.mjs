import test from 'node:test';
import {WebSocket} from 'ws';
import {readFile} from 'node:fs/promises';
import {DatabaseSync} from 'node:sqlite';
import {hashPassword,digest,newToken} from '../src/security.mjs';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {once} from 'node:events';
import {openDatabase} from '../src/database.mjs';
import {createApp} from '../src/app.mjs';
import {R2Images,signS3Url,r2FromEnvironment,chatR2FromEnvironment} from '../src/r2.mjs';
import {imageDimensions} from '../src/images.mjs';
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jftkAAAAASUVORK5CYII=','base64');
const md5=b=>createHash('md5').update(b).digest('base64');
const connectionString=process.env.TEST_DATABASE_URL;
if(connectionString){const u=new URL(connectionString);assert.ok(['localhost','127.0.0.1'].includes(u.hostname)&&u.pathname==='/tomi_test');}
async function fixture(t,{images=false,separate=false}={}){
 const dir=await mkdtemp(join(tmpdir(),'tomi-social-')),objects=new Map(),privateObjects=new Map();
 const storage=images?new R2Images({endpoint:'https://'+'a'.repeat(32)+'.r2.cloudflarestorage.com',bucket:'tomi-test',accessKeyId:'test-access',secretAccessKey:'test-secret'},{fetcher:async(url,opts)=>{
  const key=decodeURIComponent(new URL(url).pathname.slice('/tomi-test/'.length));
  if(opts?.method==='DELETE'){objects.delete(key);return new Response(null,{status:204});}
  const o=objects.get(key);return o?new Response(o.bytes,{headers:{'content-type':o.type,'content-length':String(o.bytes.length)}}):new Response(null,{status:404});
 }}):null;
 const chatStorage=separate?new R2Images({endpoint:'https://'+'a'.repeat(32)+'.r2.cloudflarestorage.com',bucket:'private-chat',accessKeyId:'test',secretAccessKey:'test'},{fetcher:async(url,opts)=>{const key=decodeURIComponent(new URL(url).pathname.slice('/private-chat/'.length));if(opts?.method==='DELETE'){privateObjects.delete(key);return new Response(null,{status:204});}const o=privateObjects.get(key);return o?new Response(o.bytes,{headers:{'content-type':o.type,'content-length':String(o.bytes.length)}}):new Response(null,{status:404});}}):storage;
 let db,server,base;
 async function start(reset=false){db=await openDatabase({connectionString,sqliteFile:join(dir,'test.sqlite')});if(reset&&connectionString){await db.query('DELETE FROM tomi_users');await db.query('DELETE FROM tomi_rate_limits');}server=await createApp({database:db,storage,chatStorage,rateLimitMultiplier:10});server.listen(0,'127.0.0.1');await once(server,'listening');base='http://127.0.0.1:'+server.address().port;}
 async function stop(){if(server){const done=new Promise((res,rej)=>server.close(e=>e?rej(e):res()));server.closeIdleConnections();await done;server=null;}if(db){await db.close();db=null;}}
 await start(true);t.after(async()=>{await stop();await rm(dir,{recursive:true,force:true});});
 return {get base(){return base;},get db(){return db;},get server(){return server;},storage,objects,privateObjects,async restart(){await stop();await start();},async request(method,path,body,token){const r=await fetch(base+path,{method,headers:{...(body!==undefined?{'content-type':'application/json'}:{}),...(token?{authorization:'Bearer '+token}:{})},...(body!==undefined?{body:JSON.stringify(body)}:{})});return{status:r.status,data:await r.json()};},async register(name){const r=await this.request('POST','/v1/auth/register',{username:name,displayName:name,password:'long passphrase for TOMI testing'});assert.equal(r.status,201);return r.data;},async post(u,text,extra={}){return this.request('POST','/v1/posts',{text,requestId:randomUUID(),...extra},u.token);},async upload(u,bytes=png,type='image/png'){const r=await this.request('POST','/v1/media/images',{contentType:type,byteLength:bytes.length,contentMd5:md5(bytes)},u.token);assert.equal(r.status,201);const row=(await db.query('SELECT * FROM tomi_image_uploads WHERE id=?',[r.data.uploadId])).rows[0];objects.set(row.object_key,{bytes,type});return r.data;}};
}
const open=async(api,a,b)=>(await api.request('POST','/v1/chats',{userId:b.user.id},a.token)).data.conversation;
const send=async(api,a,c,text,extra={})=>api.request('POST',`/v1/chats/${c.id}/messages`,{text,requestId:randomUUID(),...extra},a.token);
const meta=async(api,a,c)=>(await api.request('GET',`/v1/chats/${c.id}`,undefined,a.token)).data.conversation;
const socket=async(api,a)=>{const ws=new WebSocket(api.base.replace('http:','ws:')+'/v1/chat/socket');await once(ws,'open');const ready=once(ws,'message');ws.send(JSON.stringify({type:'authenticate',token:a.token}));assert.equal(JSON.parse((await ready)[0]).type,'chat.ready');return ws;};

test('private history and unread markers persist across service restart',async t=>{
 const api=await fixture(t),a=await api.register('chat_writer'),b=await api.register('chat_reader'),c=await open(api,a,b);
 assert.equal((await api.request('GET','/v1/chats',undefined,b.token)).data.conversations.length,0);
 const sent=await send(api,a,c,'هلا');assert.equal(sent.status,201);await api.restart();
 const history=await api.request('GET',`/v1/chats/${c.id}/messages`,undefined,b.token);assert.equal(history.data.messages[0].text,'هلا');assert.equal(history.data.conversation.unreadCount,1);
 assert.equal((await api.request('GET','/v1/chats',undefined,b.token)).data.totalUnread,1);
 await api.request('PUT',`/v1/chats/${c.id}/read`,{sequence:1},b.token);assert.equal((await meta(api,a,c)).peerReadSequence,1);
});
test('concurrent pair creation and stable send retries do not duplicate messages',async t=>{
 const api=await fixture(t),a=await api.register('retry_a'),b=await api.register('retry_b');
 const pairs=await Promise.all([open(api,a,b),open(api,b,a)]);assert.equal(pairs[0].id,pairs[1].id);
 const c=pairs[0],requestId=randomUUID(),r=await Promise.all([send(api,a,c,'ثابت',{requestId}),send(api,a,c,'ثابت',{requestId})]);
 assert.equal(r[0].data.message.id,r[1].data.message.id);assert.equal((await meta(api,a,c)).sequence,1);
 assert.equal((await send(api,a,c,'تغيّر',{requestId})).status,409);
 const mid=r[0].data.message.id;await api.request('DELETE',`/v1/chats/${c.id}/messages/${mid}`,undefined,a.token);
 const replay=await send(api,a,c,'ثابت',{requestId});assert.equal(replay.data.message.deleted,true);assert.equal(replay.data.message.text,'');
});
test('sequence pagination has no gaps at equal timestamps',async t=>{
 const api=await fixture(t),a=await api.register('pages_a'),b=await api.register('pages_b'),c=await open(api,a,b);
 for(let i=1;i<=11;i++)assert.equal((await send(api,a,c,String(i))).status,201);
 await api.db.query('UPDATE tomi_chat_messages SET created_at=?',['2026-01-01T00:00:00.000Z']);
 let before,seen=[];do{const p=(await api.request('GET',`/v1/chats/${c.id}/messages?limit=3${before?'&before='+before:''}`,undefined,b.token)).data;seen.unshift(...p.messages.map(m=>m.sequence));before=p.nextBefore;}while(before);
 assert.deepEqual(seen,Array.from({length:11},(_,i)=>i+1));
});
test('participant permissions, validation and monotonic reads are enforced',async t=>{
 const api=await fixture(t),a=await api.register('perm_a'),b=await api.register('perm_b'),z=await api.register('perm_z'),c=await open(api,a,b),m=(await send(api,a,c,'private')).data.message;
 assert.equal((await api.request('GET',`/v1/chats/${c.id}/messages`,undefined,z.token)).status,404);
 assert.equal((await api.request('DELETE',`/v1/chats/${c.id}/messages/${m.id}`,undefined,b.token)).status,403);
 assert.equal((await api.request('POST','/v1/chats',{userId:a.user.id},a.token)).status,400);
 assert.equal((await send(api,a,c,'')).status,400);assert.equal((await send(api,a,c,'x'.repeat(2001))).status,400);
 assert.equal((await api.request('PUT',`/v1/chats/${c.id}/read`,{sequence:2},b.token)).status,400);
 await api.request('PUT',`/v1/chats/${c.id}/read`,{sequence:1},b.token);await api.request('PUT',`/v1/chats/${c.id}/read`,{sequence:0},b.token);assert.equal((await meta(api,b,c)).myReadSequence,1);
});
test('blocking prevents both directions while preserving authorized history',async t=>{
 const api=await fixture(t),a=await api.register('block_a'),b=await api.register('block_b'),c=await open(api,a,b);await send(api,a,c,'محفوظ');
 await api.request('PUT','/v1/chat/blocks/'+b.user.id,{blocked:true},a.token);
 assert.equal((await send(api,a,c,'ممنوع')).status,403);assert.equal((await send(api,b,c,'ممنوع')).status,403);
 assert.equal((await api.request('GET',`/v1/chats/${c.id}/messages`,undefined,b.token)).data.messages.length,1);
 assert.equal((await api.request('GET','/v1/chat/blocks',undefined,a.token)).data.users[0].id,b.user.id);
 await api.request('PUT','/v1/chat/blocks/'+b.user.id,{blocked:false},a.token);assert.equal((await send(api,b,c,'رجع')).status,201);
});
test('authenticated websocket updates and typing reach only participants; logout closes the socket',async t=>{
 const api=await fixture(t),a=await api.register('socket_a'),b=await api.register('socket_b'),z=await api.register('socket_z'),c=await open(api,a,b),wa=await socket(api,a),wb=await socket(api,b),wz=await socket(api,z);
 t.after(()=>[wa,wb,wz].forEach(w=>w.terminate()));const stranger=[];wz.on('message',v=>stranger.push(JSON.parse(v)));
 const got=once(wb,'message');await send(api,a,c,'event');assert.equal(JSON.parse((await got)[0]).type,'chat.message');
 const typed=once(wb,'message');wa.send(JSON.stringify({type:'typing',conversationId:c.id,active:true}));assert.equal(JSON.parse((await typed)[0]).type,'chat.typing');
 const recording=once(wb,'message');wa.send(JSON.stringify({type:'typing',conversationId:c.id,active:true,activity:'recording'}));const recordingEvent=JSON.parse((await recording)[0]);assert.equal(recordingEvent.activity,'recording');assert.equal(recordingEvent.userId,a.user.id);
 const uploading=once(wb,'message');wa.send(JSON.stringify({type:'typing',conversationId:c.id,active:true,activity:'video'}));assert.equal(JSON.parse((await uploading)[0]).activity,'video');
 await api.request('PUT','/v1/chat/blocks/'+b.user.id,{blocked:true},a.token);
 // Use one predicate listener because a block invalidation may already be queued.
 const rejected=new Promise(resolve=>wa.on('message',v=>{const e=JSON.parse(v);if(e.type==='chat.error')resolve(e);}));
 wa.send(JSON.stringify({type:'typing',conversationId:c.id,active:true}));assert.equal((await rejected).code,'CHAT_BLOCKED');assert.deepEqual(stranger,[]);
 const closed=once(wb,'close');await api.request('POST','/v1/auth/logout',{},b.token);assert.equal((await closed)[0],4401);
});
test('chat image uploads are scoped to sender, conversation and feature; deletion cleans safely',async t=>{
 const api=await fixture(t,{images:true}),a=await api.register('photo_a'),b=await api.register('photo_b'),z=await api.register('photo_z'),c=await open(api,a,b),other=await open(api,a,z);
 const prepared=await api.request('POST',`/v1/chats/${c.id}/images`,{contentType:'image/png',byteLength:png.length,contentMd5:md5(png)},a.token);assert.equal(prepared.status,201);
 const uid=prepared.data.uploadId,u=(await api.db.query('SELECT * FROM tomi_image_uploads WHERE id=?',[uid])).rows[0];api.objects.set(u.object_key,{bytes:png,type:'image/png'});
 assert.equal((await send(api,b,c,'',{imageUploadId:uid})).status,400);assert.equal((await send(api,a,other,'',{imageUploadId:uid})).status,400);
 assert.equal((await api.post(a,'',{imageUploadId:uid})).status,400);
 const requestId=randomUUID(),sent=await send(api,a,c,'',{imageUploadId:uid,requestId});assert.equal(sent.status,201);
 assert.equal(new URL(sent.data.message.image.url).searchParams.get('X-Amz-Expires'),'300');assert.equal((await send(api,a,c,'',{imageUploadId:uid,requestId})).data.message.id,sent.data.message.id);
 await api.request('DELETE',`/v1/chats/${c.id}/messages/${sent.data.message.id}`,undefined,a.token);await api.server.cleanupMedia();assert.equal(api.objects.size,1);
 await api.db.query("UPDATE tomi_image_uploads SET expires_at=? WHERE state='deleting'",['2000-01-01T00:00:00.000Z']);await api.server.cleanupMedia();assert.equal(api.objects.size,0);
});
test('one nonce used concurrently across different recipients has one winner',async t=>{
 const api=await fixture(t),a=await api.register('nonce_a'),b=await api.register('nonce_b'),z=await api.register('nonce_z'),c=await open(api,a,b),d=await open(api,a,z),requestId=randomUUID();
 const r=await Promise.all([send(api,a,c,'same',{requestId}),send(api,a,d,'same',{requestId})]);assert.deepEqual(r.map(x=>x.status).sort(),[201,409]);
 assert.equal(Number((await api.db.query('SELECT COUNT(*) AS n FROM tomi_chat_messages')).rows[0].n),1);
});
test('private image environment rejects partial or known public bucket reuse',()=>{
 const cfg={R2_ACCOUNT_ID:'a'.repeat(32),R2_BUCKET_NAME:'public-feed',R2_ACCESS_KEY_ID:'test',R2_SECRET_ACCESS_KEY:'test',R2_PUBLIC_BASE_URL:'https://images.example.com'},storage=r2FromEnvironment(cfg);
 assert.equal(chatR2FromEnvironment({},storage),null);assert.throws(()=>chatR2FromEnvironment({R2_CHAT_BUCKET_NAME:'partial'},storage));
 const chat=Object.fromEntries(Object.entries(cfg).filter(([k])=>k!=='R2_PUBLIC_BASE_URL').map(([k,v])=>[k.replace('R2_','R2_CHAT_'),v]));assert.throws(()=>chatR2FromEnvironment(chat,storage));chat.R2_CHAT_BUCKET_NAME='private-chat';assert.equal(chatR2FromEnvironment(chat,storage).config.bucket,'private-chat');
});
test('additive migration retains a 0.3 account session and post',async t=>{
 const dir=await mkdtemp(join(tmpdir(),'tomi-migration-')),file=join(dir,'old.sqlite'),old=new DatabaseSync(file),uid=randomUUID(),token=newToken(),stamp='2026-01-01T00:00:00.000Z';
 old.exec(await readFile(new URL('fixtures/schema-0.3.sql',import.meta.url),'utf8'));
 old.prepare('INSERT INTO tomi_users(id,username,display_name,password_hash,recovery_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?)').run(uid,'legacy_chat','Old',await hashPassword('long legacy password'),digest('recovery'),stamp,stamp);
 old.prepare('INSERT INTO tomi_sessions(token_hash,user_id,auth_version,created_at,expires_at) VALUES(?,?,?,?,?)').run(digest(token),uid,1,stamp,'2099-01-01T00:00:00.000Z');
 old.prepare('INSERT INTO tomi_posts(id,user_id,request_id,body,created_at) VALUES(?,?,?,?,?)').run(randomUUID(),uid,randomUUID(),'old saved post',stamp);old.close();
 const db=await openDatabase({sqliteFile:file}),server=await createApp({database:db});server.listen(0,'127.0.0.1');await once(server,'listening');
 t.after(async()=>{await new Promise(resolve=>server.close(resolve));await db.close();await rm(dir,{recursive:true,force:true});});
 const r=await fetch('http://127.0.0.1:'+server.address().port+'/v1/me',{headers:{authorization:'Bearer '+token}}),d=await r.json();assert.equal(d.user.username,'legacy_chat');assert.equal(d.user.postsCount,1);
 assert.equal(Number((await db.query('SELECT COUNT(*) AS n FROM tomi_chat_threads')).rows[0].n),0);
});

test('separate chat and feed buckets clean only their own uploads',async t=>{
 const api=await fixture(t,{images:true,separate:true}),a=await api.register('private_bkt_a'),b=await api.register('private_bkt_b'),c=await open(api,a,b);
 const u=await api.request('POST',`/v1/chats/${c.id}/images`,{contentType:'image/png',byteLength:png.length,contentMd5:md5(png)},a.token);
 const row=(await api.db.query('SELECT object_key FROM tomi_image_uploads WHERE id=?',[u.data.uploadId])).rows[0];api.privateObjects.set(row.object_key,{bytes:png,type:'image/png'});
 const m=await send(api,a,c,'',{imageUploadId:u.data.uploadId});assert.equal(m.status,201);assert.match(new URL(m.data.message.image.url).pathname,/^\/private-chat\//);
 const feed=await api.upload(a);assert.equal(api.objects.size,1);await api.request('DELETE',`/v1/chats/${c.id}/messages/${m.data.message.id}`,null,a.token);
 await api.db.query("UPDATE tomi_image_uploads SET expires_at=? WHERE state<>'attached'",['2000-01-01T00:00:00.000Z']);await api.server.cleanupMedia();assert.equal(api.privateObjects.size,0);assert.equal(api.objects.size,0);assert.equal((await api.db.query('SELECT id FROM tomi_image_uploads')).rows.length,0);
});
