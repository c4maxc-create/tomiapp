import {hashPassword,digest,newToken} from '../src/security.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {once} from 'node:events';
import {openDatabase} from '../src/database.mjs';
import {createApp} from '../src/app.mjs';
import {WebSocket} from 'ws';
async function fixture(t){
 const dir=await mkdtemp(join(tmpdir(),'tomi32-')),db=await openDatabase({connectionString:process.env.TEST_DATABASE_URL,sqliteFile:join(dir,'test.sqlite')});
 if(process.env.TEST_DATABASE_URL){await db.query('DELETE FROM tomi_users');await db.query('DELETE FROM tomi_rate_limits');await db.query('DELETE FROM tomi_client_metrics');}
 const ownerId=randomUUID(),stamp=new Date().toISOString();await db.query('INSERT INTO tomi_users(id,username,display_name,password_hash,recovery_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',[ownerId,'owner34','owner',await hashPassword('test-only improvements32 passphrase'),digest(newToken()),stamp,stamp]);
 const sent=[];const server=await createApp({database:db,ownerUserId:ownerId,rateLimitMultiplier:30,callAutoSweep:false,roomAutoSweep:false,liveAutoTick:false,pushAutoFlush:false,pushSender:async value=>{sent.push(value);return 'sent';},iceProvider:async()=>({iceServers:[{urls:['turn:relay.example.com'],username:'test',credential:'test'}]})});
 server.listen(0,'127.0.0.1');await once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
 t.after(async()=>{const done=once(server,'close');server.close();server.closeIdleConnections();await done;await db.close();await rm(dir,{recursive:true,force:true});});
 const f={db,base,server,sent,async req(a,method,path,body){const r=await fetch(base+path,{method,headers:{...(a?{authorization:'Bearer '+a.token}:{}),...(body?{'content-type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,data:await r.json()};},async user(name){const r=await this.req(null,'POST','/v1/auth/register',{username:name,displayName:name,password:'test-only improvements32 passphrase'});assert.equal(r.status,201);return r.data;}};f.owner=(await f.req(null,'POST','/v1/auth/login',{username:'owner34',password:'test-only improvements32 passphrase'})).data;return f;
}
test('36 mentions are durable, deduplicated, private and respect blocks and recipient policies',async t=>{
 const f=await fixture(t),a=await f.user('notice36a'),b=await f.user('notice36b'),c=await f.user('notice36c');
 const body={text:'hello @notice36b',audience:'public',requestId:randomUUID()};
 const first=await f.req(a,'POST','/v1/posts',body);assert.equal(first.status,201);
 await f.req(a,'POST','/v1/posts',body);
 const notices=(await f.req(b,'GET','/v1/me/notices')).data.items;assert.equal(notices.length,1);assert.equal(notices[0].targetId,first.data.post.id);
 assert.equal((await f.req(c,'GET','/v1/me/notices/'+notices[0].id)).status,404);
 assert.equal((await f.req(b,'PUT','/v1/me/notices/'+notices[0].id,{})).data.notice.read,true);
 assert.equal((await f.req(b,'PUT','/v1/me/content-preferences',{comments:'everyone',mentions:'nobody',words:[]})).status,200);
 assert.equal((await f.req(a,'POST','/v1/posts',{...body,requestId:randomUUID()})).status,403);
 await f.db.query('INSERT INTO tomi_user_blocks(blocker_id,blocked_id,created_at) VALUES(?,?,?)',[b.user.id,a.user.id,new Date().toISOString()]);
 assert.equal((await f.req(b,'GET','/v1/me/notices')).data.items.length,0);
});
test('36 comments enforce recipient word filters and following policy atomically',async t=>{
 const f=await fixture(t),a=await f.user('filter36a'),b=await f.user('filter36b');
 const p=(await f.req(a,'POST','/v1/posts',{text:'test',audience:'public',requestId:randomUUID()})).data.post;
 const path='/v1/posts/'+p.id+'/comments';
 await f.req(a,'PUT','/v1/me/content-preferences',{comments:'everyone',mentions:'everyone',words:['STOP']});
 assert.equal((await f.req(b,'POST',path,{text:'please stop',requestId:randomUUID()})).status,403);
 assert.equal((await f.req(b,'POST',path,{text:'hello',requestId:randomUUID()})).status,201);
 await f.req(a,'PUT','/v1/me/content-preferences',{comments:'following',mentions:'everyone',words:[]});
 assert.equal((await f.req(b,'POST',path,{text:'hello again',requestId:randomUUID()})).status,403);
 await f.db.query('INSERT INTO tomi_follows(follower_id,following_id,created_at) VALUES(?,?,?)',[a.user.id,b.user.id,new Date().toISOString()]);
 assert.equal((await f.req(b,'POST',path,{text:'now allowed',requestId:randomUUID()})).status,201);
});
test('36 support reply creates one private notice per revision and exact ticket route',async t=>{
 const f=await fixture(t),a=await f.user('support36a'),b=await f.user('support36b');
 const ticket=(await f.req(a,'POST','/v1/me/support',{subject:'test',body:'help me',requestId:randomUUID()})).data.ticket;
 const path='/v1/admin/support/'+ticket.id,body={reply:'answered',status:'answered',revision:0};
 assert.equal((await f.req(f.owner,'PUT',path,body)).status,200);
 assert.equal((await f.req(f.owner,'PUT',path,body)).status,409);
 const notices=(await f.req(a,'GET','/v1/me/notices')).data.items;assert.equal(notices.length,1);assert.equal(notices[0].kind,'support');
 assert.equal((await f.req(b,'GET','/v1/me/support?targetId='+ticket.id)).data.items.length,0);
 assert.equal((await f.req(a,'GET','/v1/me/support?targetId='+ticket.id)).data.items[0].reply,'answered');
});
test('36 notice push is once per valid session device and never contains message text',async t=>{
 const f=await fixture(t),a=await f.user('push36a'),b=await f.user('push36b');
 assert.equal((await f.req(b,'PUT','/v1/push/device',{token:'notice36_device_123456789012345',platform:'android'})).status,200);
 await f.req(a,'POST','/v1/posts',{text:'private caption @push36b',audience:'public',requestId:randomUUID()});
 await f.server.flushPush();await f.server.flushPush();
 assert.equal(f.sent.length,1);assert.ok(f.sent[0].noticeId);assert.equal(f.sent[0].recipientId,b.user.id);assert.equal(f.sent[0].text,undefined);
 await f.req(b,'POST','/v1/auth/logout',{});
 await f.req(a,'POST','/v1/posts',{text:'another @push36b',audience:'public',requestId:randomUUID()});
 await f.server.flushPush();assert.equal(f.sent.length,1);
});
