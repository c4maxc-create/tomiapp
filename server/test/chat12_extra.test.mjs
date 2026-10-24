import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {once} from 'node:events';
import {openDatabase} from '../src/database.mjs';
import {createApp} from '../src/app.mjs';
import {R2Images} from '../src/r2.mjs';
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jftkAAAAASUVORK5CYII=','base64');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const connectionString=process.env.TEST_DATABASE_URL;
if(connectionString){const u=new URL(connectionString);assert.ok(['localhost','127.0.0.1'].includes(u.hostname)&&u.pathname==='/tomi_test');}
async function fixture(t,{images=false,push=false}={}){
 const dir=await mkdtemp(join(tmpdir(),'tomi-chat12-')),objects=new Map(),sent=[];
 const storage=images?new R2Images({endpoint:'https://'+'a'.repeat(32)+'.r2.cloudflarestorage.com',bucket:'tomi-test',accessKeyId:'test-access',secretAccessKey:'test-secret'},{fetcher:async(url,options)=>{const key=decodeURIComponent(new URL(url).pathname.slice('/tomi-test/'.length));if(options?.method==='DELETE'){objects.delete(key);return new Response(null,{status:204});}const value=objects.get(key);return value?new Response(value.bytes,{headers:{'content-type':value.type,'content-length':String(value.bytes.length)}}):new Response(null,{status:404});}}):null;
 let db,server,base;
 async function start(reset=false){db=await openDatabase({connectionString,sqliteFile:join(dir,'home.sqlite')});if(reset&&connectionString){await db.query('DELETE FROM tomi_users');await db.query('DELETE FROM tomi_rate_limits');}server=await createApp({database:db,storage,pushSender:push?async data=>{sent.push(data);return 'sent';}:null,pushAutoFlush:false});server.listen(0,'127.0.0.1');await once(server,'listening');base='http://127.0.0.1:'+server.address().port;}
 async function stop(){if(server){const done=new Promise((resolve,reject)=>server.close(e=>e?reject(e):resolve()));server.closeIdleConnections();await done;server=null;}if(db){await db.close();db=null;}}
 await start(true);t.after(async()=>{await stop();await rm(dir,{recursive:true,force:true});});
 return {get base(){return base;},get db(){return db;},get server(){return server;},objects,sent,async restart(){await stop();await start();},async request(method,path,body,token){const r=await fetch(base+path,{method,headers:{...(body!==undefined?{'content-type':'application/json'}:{}),...(token?{authorization:'Bearer '+token}:{})},...(body!==undefined?{body:JSON.stringify(body)}:{})});return {status:r.status,data:await r.json()};},async register(username){const r=await this.request('POST','/v1/auth/register',{username,displayName:username,password:'long TOMI passphrase for home test'});assert.equal(r.status,201);return r.data;},async story(user,extra={}){return this.request('POST','/v1/stories',{requestId:randomUUID(),text:'لحظة جديدة',...extra},user.token);},async upload(user){const r=await this.request('POST','/v1/media/images',{contentType:'image/png',byteLength:png.length,contentMd5:createHash('md5').update(png).digest('base64'),contentSha256:sha(png),requestId:randomUUID()},user.token);assert.equal(r.status,201);const row=(await db.query('SELECT * FROM tomi_image_uploads WHERE id=?',[r.data.uploadId])).rows[0];objects.set(row.object_key,{bytes:png,type:'image/png'});return r.data.uploadId;}};
}
async function people(a,n=4){const p=[];for(let i=0;i<n;i++)p.push(await a.register('chat12_'+randomUUID().slice(0,8)));return p;}
async function group(a,users){const body={title:'مجموعة الأصدقاء',memberIds:users.slice(1,3).map(u=>u.user.id),requestId:randomUUID()},r=await a.request('POST','/v1/groups',body,users[0].token);assert.equal(r.status,201,JSON.stringify(r.data));return{gid:r.data.conversation.id,body,conversation:r.data.conversation};}
async function send(a,user,gid,text,extra={}){const r=await a.request('POST','/v1/groups/'+gid+'/messages',{text,requestId:randomUUID(),...extra},user.token);assert.ok([200,201].includes(r.status),JSON.stringify(r.data));return r.data;}
async function direct(a,u,v){const r=await a.request('POST','/v1/chats',{userId:v.user.id},u.token);assert.equal(r.status,200,JSON.stringify(r.data));return r.data.conversation.id;}
async function file(a,u,tid,{group=false,bytes=Buffer.from('%PDF-1.4\nprivate document'),name='تجربة.pdf'}={}){const d=await a.request('POST',`/v1/${group?'groups':'chats'}/${tid}/files`,{requestId:randomUUID(),fileName:name,byteLength:bytes.length,contentType:'application/octet-stream',contentMd5:createHash('md5').update(bytes).digest('base64'),contentSha256:sha(bytes)},u.token);assert.equal(d.status,201,JSON.stringify(d.data));const row=(await a.db.query('SELECT * FROM tomi_private_uploads WHERE id=?',[d.data.uploadId])).rows[0];a.objects.set(row.object_key,{bytes,type:'application/octet-stream'});return{uploadId:row.id,row,bytes,sha:sha(bytes)};}

test('1.2 group image, voice and video use verified private media and deletion releases their objects',async t=>{
 const {readFile}=await import('node:fs/promises'),a=await fixture(t,{images:true}),p=await people(a,3),{gid}=await group(a,p);
 for(const kind of ['image','audio','video']){
  const bytes=kind==='image'?png:await readFile(new URL(kind==='audio'?'fixtures/voice12.m4a':'fixtures/video10.mp4',import.meta.url)),type=kind==='image'?'image/png':kind==='audio'?'audio/mp4':'video/mp4',suffix=kind==='image'?'images':kind==='video'?'videos':'audio';
  const upload=await a.request('POST',`/v1/groups/${gid}/${suffix}`,{requestId:randomUUID(),contentType:type,byteLength:bytes.length,contentMd5:createHash('md5').update(bytes).digest('base64'),contentSha256:sha(bytes),...kind==='audio'?{durationMs:1000}:{}},p[0].token);assert.equal(upload.status,201,JSON.stringify(upload.data));
  const u=(await a.db.query('SELECT * FROM tomi_private_uploads WHERE id=?',[upload.data.uploadId])).rows[0];a.objects.set(u.object_key,{bytes,type});
  const saved=await send(a,p[0],gid,'',{[kind+'UploadId']:u.id,attachmentSha256:sha(bytes)});assert.ok(saved.message[kind]);assert.equal(new URL(saved.message[kind].url).searchParams.get('X-Amz-Expires'),'300');
  await a.request('DELETE',`/v1/groups/${gid}/messages/${saved.message.id}`,undefined,p[0].token);await a.db.query("UPDATE tomi_private_uploads SET expires_at='2000-01-01T00:00:00.000Z' WHERE id=?",[u.id]);await a.server.cleanupMedia();assert.equal(a.objects.has(u.object_key),false);
 }
});
test('1.2 group typing is instant for members and revoked immediately after removal',async t=>{
 const {default:WebSocket}=await import('ws'),a=await fixture(t),p=await people(a),{gid}=await group(a,p),sockets=[];
 function wait(ws,type){return new Promise((resolve,reject)=>{const timeout=setTimeout(()=>{ws.off('message',listen);reject(Error('No '+type));},3000);function listen(raw){const e=JSON.parse(raw);if(e.type===type){clearTimeout(timeout);ws.off('message',listen);resolve(e);}}ws.on('message',listen);});}
 for(const u of [p[1],p[2],p[3]]){const ws=new WebSocket(a.base.replace('http:','ws:')+'/v1/chat/socket');await once(ws,'open');const ready=wait(ws,'chat.ready');ws.send(JSON.stringify({type:'authenticate',token:u.token}));await ready;sockets.push(ws);}t.after(()=>sockets.forEach(ws=>ws.terminate()));
 const expected=wait(sockets[1],'chat.typing');let outsiderMessages=0;sockets[2].on('message',()=>outsiderMessages++);sockets[0].send(JSON.stringify({type:'typing',conversationId:gid,active:true}));const event=await expected;assert.equal(event.conversationId,gid);assert.equal(event.group,true);
 await a.request('DELETE',`/v1/groups/${gid}/members/${p[1].user.id}`,undefined,p[0].token);const rejected=wait(sockets[0],'chat.error');sockets[0].send(JSON.stringify({type:'typing',conversationId:gid,active:true}));assert.equal((await rejected).code,'CHAT_NOT_FOUND');assert.equal(outsiderMessages,0);
});
