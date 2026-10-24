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
 return {get db(){return db;},get server(){return server;},objects,sent,async restart(){await stop();await start();},async request(method,path,body,token){const r=await fetch(base+path,{method,headers:{...(body!==undefined?{'content-type':'application/json'}:{}),...(token?{authorization:'Bearer '+token}:{})},...(body!==undefined?{body:JSON.stringify(body)}:{})});return {status:r.status,data:await r.json()};},async register(username){const r=await this.request('POST','/v1/auth/register',{username,displayName:username,password:'long TOMI passphrase for home test'});assert.equal(r.status,201);return r.data;},async story(user,extra={}){return this.request('POST','/v1/stories',{requestId:randomUUID(),text:'لحظة جديدة',...extra},user.token);},async upload(user){const r=await this.request('POST','/v1/media/images',{contentType:'image/png',byteLength:png.length,contentMd5:createHash('md5').update(png).digest('base64'),contentSha256:sha(png),requestId:randomUUID()},user.token);assert.equal(r.status,201);const row=(await db.query('SELECT * FROM tomi_image_uploads WHERE id=?',[r.data.uploadId])).rows[0];objects.set(row.object_key,{bytes:png,type:'image/png'});return r.data.uploadId;}};
}
async function people(a,n=4){const p=[];for(let i=0;i<n;i++)p.push(await a.register('chat12_'+randomUUID().slice(0,8)));return p;}
async function group(a,users){const body={title:'مجموعة الأصدقاء',memberIds:users.slice(1,3).map(u=>u.user.id),requestId:randomUUID()},r=await a.request('POST','/v1/groups',body,users[0].token);assert.equal(r.status,201,JSON.stringify(r.data));return{gid:r.data.conversation.id,body,conversation:r.data.conversation};}
async function send(a,user,gid,text,extra={}){const r=await a.request('POST','/v1/groups/'+gid+'/messages',{text,requestId:randomUUID(),...extra},user.token);assert.ok([200,201].includes(r.status),JSON.stringify(r.data));return r.data;}
async function direct(a,u,v){const r=await a.request('POST','/v1/chats',{userId:v.user.id},u.token);assert.equal(r.status,200,JSON.stringify(r.data));return r.data.conversation.id;}
async function file(a,u,tid,{group=false,bytes=Buffer.from('%PDF-1.4\nprivate document'),name='تجربة.pdf'}={}){const d=await a.request('POST',`/v1/${group?'groups':'chats'}/${tid}/files`,{requestId:randomUUID(),fileName:name,byteLength:bytes.length,contentType:'application/octet-stream',contentMd5:createHash('md5').update(bytes).digest('base64'),contentSha256:sha(bytes)},u.token);assert.equal(d.status,201,JSON.stringify(d.data));const row=(await a.db.query('SELECT * FROM tomi_private_uploads WHERE id=?',[d.data.uploadId])).rows[0];a.objects.set(row.object_key,{bytes,type:'application/octet-stream'});return{uploadId:row.id,row,bytes,sha:sha(bytes)};}

test('1.2 group creation, private membership, merged inbox, read state and idempotency survive restart',async t=>{
 const a=await fixture(t),p=await people(a),g=await group(a,p);
 assert.equal(g.conversation.memberCount,3);assert.equal(g.conversation.type,'group');
 assert.equal((await a.request('POST','/v1/groups',g.body,p[0].token)).data.conversation.id,g.gid);
 assert.equal((await a.request('POST','/v1/groups',{...g.body,title:'تغيّر'},p[0].token)).status,409);
 assert.equal((await a.request('GET','/v1/groups/'+g.gid,undefined,p[3].token)).status,404);
 const nonce=randomUUID(),first=await send(a,p[0],g.gid,'أهلًا',{requestId:nonce});await send(a,p[0],g.gid,'أهلًا',{requestId:nonce});
 assert.equal((await a.db.query('SELECT * FROM tomi_group_messages')).rows.length,1);
 const list=(await a.request('GET','/v1/chats',undefined,p[1].token)).data;assert.equal(list.totalUnread,1);assert.equal(list.conversations[0].id,g.gid);assert.equal(list.conversations[0].lastMessage,'أهلًا');
 assert.equal((await a.request('GET','/v1/chats/'+g.gid,undefined,p[1].token)).data.conversation.type,'group');
 assert.equal((await a.request('PUT','/v1/groups/'+g.gid+'/read',{sequence:1},p[1].token)).status,200);
 await a.restart();assert.equal((await a.request('GET','/v1/chats',undefined,p[1].token)).data.totalUnread,0);
 assert.equal((await a.request('GET','/v1/groups/'+g.gid+'/requests/'+nonce,undefined,p[0].token)).data.message.id,first.message.id);
});
test('1.2 direct stickers and private documents are real messages with checksummed uploads and retries',async t=>{
 const a=await fixture(t,{images:true}),p=await people(a,3),tid=await direct(a,p[0],p[1]);
 const body={text:'',stickerId:'hello',requestId:randomUUID()},first=await a.request('POST','/v1/chats/'+tid+'/messages',body,p[0].token);assert.equal(first.status,201,JSON.stringify(first.data));assert.equal(first.data.message.stickerId,'hello');
 assert.equal((await a.request('POST','/v1/chats/'+tid+'/messages',body,p[0].token)).data.message.id,first.data.message.id);
 assert.equal((await a.request('POST','/v1/chats/'+tid+'/messages',{...body,stickerId:'cool'},p[0].token)).status,409);
 const f=await file(a,p[0],tid),payload={text:'المستند',fileUploadId:f.uploadId,attachmentSha256:f.sha,requestId:randomUUID()};
 a.objects.get(f.row.object_key).bytes=Buffer.from('wrong');assert.equal((await a.request('POST','/v1/chats/'+tid+'/messages',payload,p[0].token)).status,400);
 a.objects.get(f.row.object_key).bytes=f.bytes;const saved=await a.request('POST','/v1/chats/'+tid+'/messages',payload,p[0].token);assert.equal(saved.status,201,JSON.stringify(saved.data));assert.equal(saved.data.message.file.name,'تجربة.pdf');assert.match(saved.data.message.file.url,/X-Amz-Expires=300/);
 assert.equal((await a.request('GET','/v1/chats/'+tid+'/messages/'+saved.data.message.id,undefined,p[2].token)).status,404);
 assert.equal((await a.request('POST','/v1/chats/'+tid+'/messages',payload,p[0].token)).data.message.id,saved.data.message.id);
 await a.request('DELETE','/v1/chats/'+tid+'/messages/'+saved.data.message.id,undefined,p[0].token);
 assert.equal((await a.db.query('SELECT state FROM tomi_private_uploads WHERE id=?',[f.uploadId])).rows[0].state,'deleting');
});
test('1.2 group reply, reactions, pin and owner deletion enforce scope and update tombstones',async t=>{
 const a=await fixture(t),p=await people(a),{gid}=await group(a,p),m=await send(a,p[1],gid,'رسالة أصلية'),reply=await send(a,p[2],gid,'رد',{replyToId:m.message.id});
 assert.equal(reply.message.reply.text,'رسالة أصلية');
 assert.equal((await a.request('PUT',`/v1/groups/${gid}/messages/${m.message.id}/reaction`,{emoji:'❤️'},p[2].token)).data.message.reactions[0].count,1);
 assert.equal((await a.request('PUT',`/v1/groups/${gid}/messages/${m.message.id}/pin`,{pinned:true},p[0].token)).data.conversation.pinnedMessageId,m.message.id);
 assert.equal((await a.request('DELETE',`/v1/groups/${gid}/messages/${m.message.id}`,undefined,p[2].token)).status,403);
 assert.equal((await a.request('DELETE',`/v1/groups/${gid}/messages/${m.message.id}`,undefined,p[0].token)).status,200);
 assert.equal((await a.request('GET',`/v1/groups/${gid}/messages/${reply.message.id}`,undefined,p[2].token)).data.message.reply.deleted,true);
 assert.equal((await a.request('GET',`/v1/groups/${gid}/search?q=أصلية`,undefined,p[0].token)).data.messages.length,0);
});
test('1.2 new group members cannot read earlier history; removal revokes access; ownership transfers on leave',async t=>{
 const a=await fixture(t),p=await people(a),{gid,body}=await group(a,p),m=await send(a,p[0],gid,'قبل الانضمام');
 assert.equal((await a.request('PUT',`/v1/groups/${gid}/members`,{memberIds:[p[3].user.id]},p[1].token)).status,403);
 assert.equal((await a.request('PUT',`/v1/groups/${gid}/members`,{memberIds:[p[3].user.id]},p[0].token)).status,200);
 assert.equal((await a.request('GET',`/v1/groups/${gid}/messages`,undefined,p[3].token)).data.messages.length,0);assert.equal((await a.request('GET',`/v1/groups/${gid}`,undefined,p[3].token)).data.conversation.lastMessage,'');
 assert.equal((await a.request('GET',`/v1/groups/${gid}/messages/${m.message.id}`,undefined,p[3].token)).status,404);
 await send(a,p[1],gid,'بعد الانضمام');assert.equal((await a.request('GET',`/v1/groups/${gid}/messages`,undefined,p[3].token)).data.messages.length,1);
 await a.request('DELETE',`/v1/groups/${gid}/members/${p[3].user.id}`,undefined,p[0].token);assert.equal((await a.request('GET',`/v1/groups/${gid}/messages`,undefined,p[3].token)).status,404);assert.ok((await a.request('GET','/v1/chats',undefined,p[3].token)).data.removedConversationIds.includes(gid));
 await a.request('DELETE',`/v1/groups/${gid}/members/${p[0].user.id}`,undefined,p[0].token);assert.notEqual((await a.request('GET',`/v1/groups/${gid}`,undefined,p[1].token)).data.conversation.ownerId,p[0].user.id);assert.equal((await a.request('POST','/v1/groups',body,p[0].token)).status,404);assert.equal(Number((await a.db.query('SELECT COUNT(*) total FROM tomi_groups')).rows[0].total),1);
});
test('1.2 group attachments cannot cross conversations and private files expire without public URLs',async t=>{
 const a=await fixture(t,{images:true}),p=await people(a),g=await group(a,p),f=await file(a,p[1],g.gid,{group:true});
 const g2=(await a.request('POST','/v1/groups',{...g.body,requestId:randomUUID()},p[0].token)).data.conversation;
 assert.equal((await a.request('POST',`/v1/groups/${g2.id}/messages`,{text:'',fileUploadId:f.uploadId,attachmentSha256:f.sha,requestId:randomUUID()},p[1].token)).status,409);
 const m=await send(a,p[1],g.gid,'',{fileUploadId:f.uploadId,attachmentSha256:f.sha});assert.equal(m.message.file.byteLength,f.bytes.length);assert.equal(new URL(m.message.file.url).searchParams.get('X-Amz-Expires'),'300');
 const unused=await file(a,p[0],g.gid,{group:true});await a.db.query("UPDATE tomi_private_uploads SET expires_at='2000-01-01T00:00:00.000Z' WHERE id=?",[unused.uploadId]);await a.server.cleanupMedia();assert.equal(a.objects.has(unused.row.object_key),false);
});
test('1.2 group notifications are per recipient, deduplicated and stop after read, block or leave',async t=>{
 const a=await fixture(t,{push:true}),p=await people(a),{gid}=await group(a,p);
 for(let i=1;i<3;i++)assert.equal((await a.request('PUT','/v1/push/device',{token:'group-device-token-abcdefghijklmnopqrstuvwxyz-'+i,platform:'android'},p[i].token)).status,200);
 await send(a,p[0],gid,'سر خاص');await a.server.flushPush();assert.equal(a.sent.length,2);assert.ok(a.sent.every(s=>s.threadId===gid&&!JSON.stringify(s).includes('سر خاص')));await a.server.flushPush();assert.equal(a.sent.length,2);
 await send(a,p[0],gid,'ثانية');await a.request('PUT',`/v1/groups/${gid}/read`,{sequence:2},p[1].token);await a.request('DELETE',`/v1/groups/${gid}/members/${p[2].user.id}`,undefined,p[0].token);await a.server.flushPush();assert.equal(a.sent.length,2);
});
test('1.2 deleting an account erases group authored content, stickers and document names and transfers ownership',async t=>{
 const a=await fixture(t,{images:true}),p=await people(a),{gid}=await group(a,p),f=await file(a,p[0],gid,{group:true});await send(a,p[0],gid,'نص خاص',{fileUploadId:f.uploadId,attachmentSha256:f.sha});
 const tid=await direct(a,p[0],p[1]);await a.request('POST','/v1/chats/'+tid+'/messages',{requestId:randomUUID(),text:'',stickerId:'love'},p[0].token);
 const d=await a.request('POST','/v1/account/deletion',{password:'long TOMI passphrase for home test',confirmation:'حذف حسابي',requestId:randomUUID(),receiptToken:Buffer.alloc(32,9).toString('base64url')},p[0].token);assert.equal(d.status,202,JSON.stringify(d.data));
 assert.equal((await a.db.query('SELECT * FROM tomi_chat_stickers')).rows.length,0);assert.equal((await a.db.query('SELECT * FROM tomi_private_uploads WHERE user_id=?',[p[0].user.id])).rows.length,0);
 const live=(await a.request('GET',`/v1/groups/${gid}`,undefined,p[1].token)).data.conversation;assert.notEqual(live.ownerId,p[0].user.id);assert.equal(live.groupTitle,'مجموعة');assert.equal((await a.request('GET',`/v1/groups/${gid}/messages`,undefined,p[1].token)).data.messages[0].deleted,true);
});
