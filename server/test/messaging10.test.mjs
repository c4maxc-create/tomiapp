import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {once} from 'node:events';
import {DatabaseSync} from 'node:sqlite';
import {openDatabase} from '../src/database.mjs';
import {createApp} from '../src/app.mjs';
import {R2Images} from '../src/r2.mjs';
import {VideoInspector,videoMetadata,maxVideoBytes} from '../src/video.mjs';
const connectionString=process.env.TEST_DATABASE_URL;
if(connectionString){const u=new URL(connectionString);assert.ok(['localhost','127.0.0.1'].includes(u.hostname)&&u.pathname==='/tomi_test','Tests require local tomi_test');}
const video=await readFile(new URL('fixtures/video10.mp4',import.meta.url));
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jftkAAAAASUVORK5CYII=','base64');
const sha=b=>createHash('sha256').update(b).digest('hex'),md5=b=>createHash('md5').update(b).digest('base64');
async function fixture(t){
 const dir=await mkdtemp(join(tmpdir(),'tomi10-')),objects=new Map(),privateObjects=new Map();let db,server,base;
 const storage=(bucket,map)=>new R2Images({endpoint:'https://'+'a'.repeat(32)+'.r2.cloudflarestorage.com',bucket,accessKeyId:'test',secretAccessKey:'test'},{fetcher:async(url,options)=>{
  const key=decodeURIComponent(new URL(url).pathname.slice(bucket.length+2));if(options?.method==='DELETE'){map.delete(key);return new Response(null,{status:204});}
  const item=map.get(key);return item?new Response(item.bytes,{headers:{'content-type':item.type,'content-length':String(item.bytes.length)}}):new Response(null,{status:404});
 }});
 const main=storage('feed-test',objects),chat=storage('private-test',privateObjects);
 const provider={ensure:async()=>{},grant:async(r,m)=>({identity:m.identity,url:'wss://test.livekit.cloud',token:'test-only'}),permissions:async()=>{},remove:async()=>{},close:async()=>{}};
 async function start(reset=false){db=await openDatabase({connectionString,sqliteFile:join(dir,'test.sqlite')});if(reset&&connectionString){await db.query('DELETE FROM tomi_users');await db.query('DELETE FROM tomi_rate_limits');}server=await createApp({database:db,storage:main,chatStorage:chat,roomProvider:provider,roomAutoSweep:false,callAutoSweep:false,pushAutoFlush:false,rateLimitMultiplier:100});server.listen(0,'127.0.0.1');await once(server,'listening');base='http://127.0.0.1:'+server.address().port;}
 async function stop(){const closed=once(server,'close');server.close();server.closeIdleConnections();await closed;await db.close();}
 await start(true);t.after(async()=>{await stop();await rm(dir,{recursive:true,force:true});});
 return {objects,privateObjects,get db(){return db;},get server(){return server;},async restart(){await stop();await start();},
  async request(a,method,path,body){const r=await fetch(base+path,{method,headers:{...(a?{authorization:'Bearer '+a.token}:{}),...(body?{'content-type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,data:await r.json()};},
  async register(name){const r=await this.request(null,'POST','/v1/auth/register',{username:name,displayName:name,password:'test-only 0.10 passphrase'});assert.equal(r.status,201);return r.data;},
  async open(a,b){return (await this.request(a,'POST','/v1/chats',{userId:b.user.id})).data.conversation;},
  async prepare(a,path,bytes=png,type='image/png',requestId=randomUUID(),extra={}){return this.request(a,'POST',path,{requestId,contentSha256:sha(bytes),contentType:type,byteLength:bytes.length,contentMd5:md5(bytes),...extra});},
  async put(upload,bytes,type='image/png'){const id=upload.data.uploadId;let u=(await db.query('SELECT * FROM tomi_image_uploads WHERE id=?',[id])).rows[0];if(!u)u=(await db.query('SELECT * FROM tomi_video_uploads WHERE id=?',[id])).rows[0];(u.object_key.startsWith('tomi/chat-')?privateObjects:objects).set(u.object_key,{bytes,type});return u;},
 };
}
const send=(f,a,c,extra)=>f.request(a,'POST',`/v1/chats/${c.id}/messages`,{text:'',requestId:randomUUID(),...extra});
test('0.10 replies reactions pins and their deletion persist and enforce participant/block boundaries',async t=>{
 const f=await fixture(t),a=await f.register('tools10a'),b=await f.register('tools10b'),z=await f.register('tools10z'),c=await f.open(a,b),other=await f.open(a,z);
 const first=(await send(f,a,c,{text:'النص الأصلي'})).data.message;
 assert.equal((await send(f,a,other,{text:'رد مزور',replyToId:first.id})).data.error.code,'REPLY_INVALID');
 const reply=(await send(f,b,c,{text:'جواب',replyToId:first.id})).data.message;assert.equal(reply.reply.text,'النص الأصلي');
 const tool=(as,mid,action,body)=>f.request(as,'PUT',`/v1/chats/${c.id}/messages/${mid}/${action}`,body);
 assert.equal((await tool(z,first.id,'reaction',{emoji:'❤️'})).status,404);
 await Promise.all([tool(a,first.id,'reaction',{emoji:'❤️'}),tool(b,first.id,'reaction',{emoji:'❤️'})]);
 let r=await tool(a,first.id,'reaction',{emoji:'❤️'});assert.deepEqual(r.data.message.reactions,[{emoji:'❤️',count:2,mine:true}]);
 r=await tool(a,first.id,'reaction',{emoji:'🔥'});assert.equal(r.data.message.reactions.length,2);
 assert.equal((await tool(a,first.id,'reaction',{emoji:'unsupported'})).status,400);
 await tool(a,first.id,'pin',{pinned:true});await tool(b,reply.id,'pin',{pinned:true});r=await tool(a,first.id,'pin',{pinned:false});assert.equal(r.data.conversation.pinnedMessageId,reply.id);
 await f.restart();r=await f.request(b,'GET',`/v1/chats/${c.id}/messages/${first.id}`);assert.equal(r.data.message.reactions.length,2);assert.equal(r.data.conversation.pinnedMessageId,reply.id);
 await f.request(a,'DELETE',`/v1/chats/${c.id}/messages/${first.id}`);r=await f.request(b,'GET',`/v1/chats/${c.id}/messages/${reply.id}`);assert.equal(r.data.message.reply.deleted,true);assert.equal(r.data.message.reply.text,'تم حذف الرسالة');
 assert.equal((await send(f,b,c,{text:'رد',replyToId:first.id})).status,400);
 await f.request(a,'PUT','/v1/chat/blocks/'+b.user.id,{blocked:true});assert.equal((await tool(b,reply.id,'pin',{pinned:true})).status,403);
});
test('0.10 search uses literal matching, stable sequence pages and private own request receipts',{timeout:180000},async t=>{
 const f=await fixture(t),a=await f.register('search10a'),b=await f.register('search10b'),z=await f.register('search10z'),c=await f.open(a,b);let first;
 for(let i=0;i<65;i++){const r=await send(f,a,c,{text:i===0?'100%_literal':'سؤال '+i});assert.equal(r.status,201);first??=r.data.message;if((i+1)%16===0||i===64)t.diagnostic('Search fixture messages prepared: '+(i+1)+'/65');}
 const found=[];let before,pages=0;do{assert.ok(++pages<=3,'Search pagination exceeded the expected three pages');const r=await f.request(a,'GET',`/v1/chats/${c.id}/search?q=${encodeURIComponent('سؤال')}`+(before?'&before='+before:''));assert.equal(r.status,200);found.push(...r.data.messages.map(m=>m.sequence));const next=r.data.nextBefore;if(before!=null&&next!=null)assert.ok(next<before,'Search cursor did not move backwards');before=next;t.diagnostic('Search page completed: '+pages);}while(before);assert.equal(pages,3);
 assert.equal(found.length,64);assert.equal(new Set(found).size,64);
 assert.equal((await f.request(a,'GET',`/v1/chats/${c.id}/search?q=%25_`)).data.messages.length,1);
 assert.equal((await f.request(z,'GET',`/v1/chats/${c.id}/search?q=سؤال`)).status,404);
 assert.equal((await f.request(a,'GET',`/v1/chats/${c.id}/search?q=ok&before=9999999999999999`)).status,400);
 assert.equal((await f.request(a,'GET',`/v1/chats/${c.id}/requests/${first.requestId}`)).data.message.id,first.id);
 assert.equal((await f.request(b,'GET',`/v1/chats/${c.id}/requests/${first.requestId}`)).status,404);
 await f.request(a,'DELETE',`/v1/chats/${c.id}/messages/${first.id}`);assert.equal((await f.request(a,'GET',`/v1/chats/${c.id}/search?q=%25_`)).data.messages.length,0);
});
test('0.10 upload init and physical-upload renewal preserve a single logical image request',async t=>{
 const f=await fixture(t),a=await f.register('media10a'),b=await f.register('media10b'),c=await f.open(a,b),nonce=randomUUID(),path=`/v1/chats/${c.id}/images`;
 const [one,two]=await Promise.all([f.prepare(a,path,png,'image/png',nonce),f.prepare(a,path,png,'image/png',nonce)]);assert.equal(one.data.uploadId,two.data.uploadId);
 assert.equal((await f.prepare(a,'/v1/media/images',png,'image/png',nonce)).status,409);
 await f.db.query('UPDATE tomi_image_uploads SET expires_at=? WHERE id=?',['2000-01-01T00:00:00.000Z',one.data.uploadId]);
 const newer=await f.prepare(a,path,png,'image/png',nonce);assert.notEqual(newer.data.uploadId,one.data.uploadId);await f.put(newer,png);
 const body={text:'صورة',requestId:nonce,imageUploadId:newer.data.uploadId,attachmentSha256:sha(png)},saved=await send(f,a,c,body);assert.equal(saved.status,201);
 await f.restart();const replay=await send(f,a,c,{...body,imageUploadId:one.data.uploadId});assert.equal(replay.status,200);assert.equal(replay.data.message.id,saved.data.message.id);
 assert.equal((await f.prepare(a,path,png,'image/png',nonce)).data.error.code,'UPLOAD_ATTACHED');
 assert.equal(Number((await f.db.query('SELECT COUNT(*) AS n FROM tomi_chat_messages')).rows[0].n),1);
 const bad=await f.prepare(a,path,png,'image/png',randomUUID(),{contentSha256:'0'.repeat(64)});await f.put(bad,png);assert.equal((await send(f,a,c,{imageUploadId:bad.data.uploadId,attachmentSha256:'0'.repeat(64)})).data.error.code,'INVALID_IMAGE');
});
test('0.10 real H264 AAC MP4 inspection streams across every header and bounds malformed metadata',()=>{
 assert.deepEqual(videoMetadata(video),{width:320,height:180,durationMs:1000});
 const surround=Buffer.from(video),audio=surround.indexOf('mp4a');assert.ok(audio>0);surround.writeUInt16BE(6,audio+20);assert.equal(videoMetadata(surround).durationMs,1000);surround.writeUInt16BE(9,audio+20);assert.throws(()=>videoMetadata(surround));
 for(const size of [1,7,13,1024]){const x=new VideoInspector(video.length);for(let i=0;i<video.length;i+=size)x.push(video.subarray(i,i+size));assert.equal(x.finish().durationMs,1000);}
 assert.throws(()=>new VideoInspector(maxVideoBytes+1));assert.throws(()=>videoMetadata(png));assert.throws(()=>videoMetadata(video.subarray(0,video.length-1)));
 const unsupported=Buffer.from(video);let i=unsupported.indexOf('avc1');while(i>=0){unsupported.write('hvc1',i);i=unsupported.indexOf('avc1',i+4);}assert.throws(()=>videoMetadata(unsupported));
 const huge=Buffer.from(video),codec=huge.indexOf('avc1',40);huge.writeUInt16BE(4096,codec+4+24);assert.throws(()=>videoMetadata(huge));
});
test('0.10 videos use separate private/public buckets, actual metadata and cleanup after deletion',async t=>{
 const f=await fixture(t),a=await f.register('video10a'),b=await f.register('video10b'),z=await f.register('video10z'),c=await f.open(a,b),nonce=randomUUID();
 const u=await f.prepare(a,`/v1/chats/${c.id}/videos`,video,'video/mp4',nonce);assert.equal(u.status,201);await f.put(u,video,'video/mp4');
 assert.equal((await send(f,b,c,{videoUploadId:u.data.uploadId,attachmentSha256:sha(video)})).status,400);
 const message=(await send(f,a,c,{requestId:nonce,videoUploadId:u.data.uploadId,attachmentSha256:sha(video)})).data.message;assert.equal(message.video.width,320);assert.equal(new URL(message.video.url).searchParams.get('X-Amz-Expires'),'300');assert.match(message.video.url,/private-test/);
 assert.equal((await f.request(z,'GET',`/v1/chats/${c.id}/messages/${message.id}`)).status,404);
 const pu=await f.prepare(a,'/v1/media/videos',video,'video/mp4');await f.put(pu,video,'video/mp4');
 const post=await f.request(a,'POST','/v1/posts',{requestId:randomUUID(),text:'فيديو',videoUploadId:pu.data.uploadId,attachmentSha256:sha(video)});assert.equal(post.status,201);assert.match(post.data.post.video.url,/feed-test/);assert.equal(post.data.post.video.durationMs,1000);
 await f.request(a,'DELETE',`/v1/chats/${c.id}/messages/${message.id}`);await f.request(a,'DELETE','/v1/posts/'+post.data.post.id);await f.db.query("UPDATE tomi_video_uploads SET expires_at=? WHERE state='deleting'",['2000-01-01T00:00:00.000Z']);await f.server.cleanupMedia();assert.equal(f.privateObjects.size,0);assert.equal(f.objects.size,0);
});
test('0.10 a post receipt survives deleted posts and cannot republish an uncertain old nonce',async t=>{
 const f=await fixture(t),a=await f.register('posts10a'),b=await f.register('posts10b'),nonce=randomUUID(),body={text:'منشور',requestId:nonce};
 const p=await f.request(a,'POST','/v1/posts',body);assert.equal(p.status,201);await f.restart();assert.equal((await f.request(a,'GET','/v1/posts/requests/'+nonce)).data.post.id,p.data.post.id);assert.equal((await f.request(b,'GET','/v1/posts/requests/'+nonce)).status,404);
 await f.request(a,'DELETE','/v1/posts/'+p.data.post.id);await f.restart();assert.equal((await f.request(a,'POST','/v1/posts',body)).data.error.code,'REQUEST_REMOVED');assert.equal((await f.request(a,'GET','/v1/posts/requests/'+nonce)).status,410);assert.equal(Number((await f.db.query('SELECT COUNT(*) AS n FROM tomi_posts')).rows[0].n),0);
});
test('0.10 room history is keyset paginated and session bound; own gift receipt remains readable after close',{timeout:180000},async t=>{
 const f=await fixture(t),a=await f.register('history10a'),b=await f.register('history10b'),z=await f.register('history10z'),rid=randomUUID(),path='/v1/rooms/'+rid;
 await f.request(a,'POST','/v1/rooms',{requestId:rid,title:'غرفة السجل',capacity:10,seatCount:4});await f.request(a,'POST',path+'/join',{});await f.request(b,'POST',path+'/join',{});
 for(let i=0;i<95;i++){assert.equal((await f.request(a,'POST',path+'/message',{requestId:randomUUID(),text:'رسالة '+i})).status,200);if((i+1)%32===0||i===94)t.diagnostic('Room-history fixture messages prepared: '+(i+1)+'/95');}
 const seen=[];let before,pages=0;do{assert.ok(++pages<=10,'Room history pagination did not terminate');const r=await f.request(b,'GET',path+'/events'+(before?'?before='+before:''));assert.equal(r.status,200);seen.push(...r.data.events.filter(e=>e.kind==='message').map(e=>e.sequence));const next=r.data.nextBefore;if(before!=null&&next!=null)assert.ok(next<before,'Room-history cursor did not move backwards');before=next;}while(before);assert.equal(new Set(seen).size,95);assert.equal(seen.length,95);
 assert.equal((await f.request(z,'GET',path+'/events')).status,403);
 const other=(await f.request(null,'POST','/v1/auth/login',{username:'history10b',password:'test-only 0.10 passphrase'})).data;assert.equal((await f.request(other,'GET',path+'/events')).status,409);
 const nonce=randomUUID(),gift={requestId:nonce,recipientId:b.user.id,giftId:'rose',quantity:2},sent=await f.request(a,'POST',path+'/gift',gift);assert.equal(sent.status,200);const coins=sent.data.wallet.coins;
 await f.request(a,'POST',path+'/close',{});await f.restart();assert.equal((await f.request(a,'GET',path+'/requests/'+nonce)).data.wallet.coins,coins);assert.equal((await f.request(b,'GET',path+'/requests/'+nonce)).status,404);assert.ok((await f.request(b,'GET',path+'/events')).status>=400);assert.equal(Number((await f.db.query('SELECT COUNT(*) AS n FROM tomi_room_all_gifts')).rows[0].n),1);
});
test('0.10 additive migration opens the exact 0.9 schema and retains existing session and text post receipt',async t=>{
 const old=await readFile(new URL('fixtures/schema-0.9.sql',import.meta.url),'utf8'),next=await readFile(new URL('../schema.sql',import.meta.url),'utf8');assert.ok(next.startsWith(old));
 const dir=await mkdtemp(join(tmpdir(),'tomi-upgrade10-'));t.after(()=>rm(dir,{recursive:true,force:true}));const file=join(dir,'old.sqlite'),raw=new DatabaseSync(file);raw.exec(old);
 const uid=randomUUID(),post=randomUUID(),nonce=randomUUID(),stamp=new Date().toISOString();
 raw.prepare('INSERT INTO tomi_users(id,username,display_name,password_hash,recovery_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?)').run(uid,'upgrade10','Upgrade','test-only','test-only',stamp,stamp);
 raw.prepare('INSERT INTO tomi_posts(id,user_id,request_id,body,created_at) VALUES(?,?,?,?,?)').run(post,uid,nonce,'old post',stamp);raw.close();
 const db=await openDatabase({sqliteFile:file});try{assert.equal((await db.query('SELECT body FROM tomi_posts WHERE id=?',[post])).rows[0].body,'old post');assert.equal((await db.query('SELECT post_id FROM tomi_post_receipts WHERE user_id=? AND request_id=?',[uid,nonce])).rows[0].post_id,post);assert.equal(Number((await db.query('SELECT COUNT(*) AS n FROM tomi_chat_reactions')).rows[0].n),0);}finally{await db.close();}
});
