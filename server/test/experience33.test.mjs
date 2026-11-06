import {newToken} from '../src/security.mjs';
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
 const server=await createApp({database:db,rateLimitMultiplier:30,callAutoSweep:false,roomAutoSweep:false,liveAutoTick:false,pushAutoFlush:false,pushSender:async()=> 'sent',iceProvider:async()=>({iceServers:[{urls:['turn:relay.example.com'],username:'test',credential:'test'}]})});
 server.listen(0,'127.0.0.1');await once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
 t.after(async()=>{const done=once(server,'close');server.close();server.closeIdleConnections();await done;await db.close();await rm(dir,{recursive:true,force:true});});
 const f={db,base,async req(a,method,path,body){const r=await fetch(base+path,{method,headers:{...(a?{authorization:'Bearer '+a.token}:{}),...(body?{'content-type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,data:await r.json()};},async user(name){const r=await this.req(null,'POST','/v1/auth/register',{username:name,displayName:name,password:'test-only improvements32 passphrase'});assert.equal(r.status,201);return r.data;}};return f;
}
const login=(f,a)=>f.req(null,'POST','/v1/auth/login',{username:a.user.username,password:'test-only improvements32 passphrase'});
const post=(f,a,text,audience='public')=>f.req(a,'POST','/v1/posts',{text,audience,requestId:randomUUID()});
test('33 session devices use opaque IDs, enforce ownership and revoke one other login immediately',async t=>{
 const f=await fixture(t),a=await f.user('session33a'),b=await f.user('session33b'),second=(await login(f,a)).data;
 const d=await f.req(a,'GET','/v1/me/sessions');assert.equal(d.status,200);assert.equal(d.data.sessions.length,2);assert.equal(d.data.sessions.filter(s=>s.current).length,1);assert.ok(!JSON.stringify(d.data).includes(a.token));assert.ok(!JSON.stringify(d.data).includes('token_hash'));
 const other=d.data.sessions.find(s=>!s.current),own=d.data.sessions.find(s=>s.current);assert.equal((await f.req(b,'DELETE','/v1/me/sessions/'+other.id)).status,404);assert.equal((await f.req(a,'DELETE','/v1/me/sessions/'+own.id)).status,400);
 assert.equal((await f.req(a,'DELETE','/v1/me/sessions/'+other.id)).status,200);assert.equal((await f.req(second,'GET','/v1/me')).status,401);assert.equal((await f.req(a,'GET','/v1/me')).status,200);
});
test('33 revoking all other devices leaves the current device and labels are validated',async t=>{
 const f=await fixture(t),a=await f.user('label33a');await login(f,a);await login(f,a);
 assert.equal((await f.req(a,'PUT','/v1/me/sessions/current',{label:'جهازي',platform:'android'})).data.sessions.find(s=>s.current).label,'جهازي');
 assert.equal((await f.req(a,'PUT','/v1/me/sessions/current',{label:'bad',platform:'token'})).status,400);
 const r=await f.req(a,'POST','/v1/me/sessions/revoke-others',{});assert.equal(r.data.removed,2);assert.equal(r.data.sessions.length,1);
});
test('33 unified search finds public content and rooms but excludes follower-only, hidden and blocked content with literal wildcard escaping',async t=>{
 const f=await fixture(t),a=await f.user('needle33a'),b=await f.user('needle33b');const p=(await post(f,a,'needle public 100%_')).data.post,q=(await post(f,a,'needle followers','followers')).data.post;
 const room=randomUUID();await f.db.query("INSERT INTO tomi_voice_rooms(id,owner_id,title,capacity,seat_count,created_at) VALUES(?,?,?,?,?,?)",[room,a.user.id,'needle room',8,4,new Date().toISOString()]);await f.db.query("INSERT INTO tomi_room_policy(room_id,tier,creator_id,price,last_owner_visit) VALUES(?,'free',?,0,?)",[room,a.user.id,new Date().toISOString()]);
 let r=await f.req(b,'GET','/v1/search?q=needle');assert.equal(r.status,200);assert.ok(r.data.users.some(u=>u.id===a.user.id));assert.ok(r.data.rooms.some(x=>x.id===room));assert.ok(r.data.posts.some(x=>x.id===p.id));assert.ok(!r.data.posts.some(x=>x.id===q.id));
 r=await f.req(b,'GET','/v1/search?q='+encodeURIComponent('%_'));assert.equal(r.data.posts.length,1);
 await f.req(b,'PUT','/v1/chat/blocks/'+a.user.id,{blocked:true});r=await f.req(b,'GET','/v1/search?q=needle');assert.ok(!r.data.users.some(u=>u.id===a.user.id));assert.equal(r.data.posts.length,0);assert.equal(r.data.rooms.length,0);
});
test('33 saved collections are private, idempotent and unsaving removes membership without deleting the post',async t=>{
 const f=await fixture(t),a=await f.user('collect33a'),b=await f.user('collect33b'),p=(await post(f,b,'save this')).data.post,id=randomUUID();
 assert.equal((await f.req(a,'POST','/v1/me/collections',{id,name:'مفضلة'})).status,201);assert.equal((await f.req(a,'POST','/v1/me/collections',{id,name:'مفضلة'})).status,201);
 const path=`/v1/me/collections/${id}/posts/${p.id}`;assert.equal((await f.req(a,'PUT',path)).data.error.code,'NOT_SAVED');await f.req(a,'PUT',`/v1/posts/${p.id}/save`,{saved:true});assert.equal((await f.req(a,'PUT',path)).status,200);assert.equal((await f.req(b,'GET','/v1/me/collections/'+id)).status,404);assert.equal((await f.req(a,'GET','/v1/me/collections/'+id)).data.posts.length,1);
 await f.req(a,'PUT',`/v1/posts/${p.id}/save`,{saved:false});assert.equal((await f.req(a,'GET','/v1/me/collections/'+id)).data.posts.length,0);assert.equal((await f.req(b,'GET','/v1/posts/'+p.id)).status,200);
 const erased=await f.req(a,'POST','/v1/account/deletion',{requestId:randomUUID(),receiptToken:newToken(),password:'test-only improvements32 passphrase',confirmation:'حذف حسابي'});assert.equal(erased.status,202);assert.equal((await f.db.query('SELECT * FROM tomi_saved_collections WHERE user_id=?',[a.user.id])).rows.length,0);assert.equal((await f.db.query('SELECT * FROM tomi_session_devices WHERE user_id=?',[a.user.id])).rows.length,0);assert.equal((await f.req(b,'GET','/v1/posts/'+p.id)).status,200);
});
test('33 diagnostics accept only bounded aggregate counters and never store message or account content',async t=>{
 const f=await fixture(t),a=await f.user('metric33a'),m={kind:'api_latency',area:'chat',bucket:2,count:3,build:33};assert.equal((await f.req(null,'POST','/v1/diagnostics/metrics',{metrics:[m]})).status,401);
 assert.equal((await f.req(a,'POST','/v1/diagnostics/metrics',{metrics:[{...m,message:'private'}]})).status,400);assert.equal((await f.req(a,'POST','/v1/diagnostics/metrics',{metrics:[m]})).status,202);await f.req(a,'POST','/v1/diagnostics/metrics',{metrics:[m]});
 const row=(await f.db.query('SELECT * FROM tomi_client_metrics')).rows[0];assert.equal(Number(row.total),6);assert.deepEqual(Object.keys(row).sort(),['day','kind','area','bucket','build','total'].sort());
});
test('33 TypeScript admin dashboard is CSP protected and ordinary accounts cannot read administration metrics',async t=>{
 const f=await fixture(t),a=await f.user('web33a'),r=await fetch(f.base+'/admin');assert.equal(r.status,200);assert.match(r.headers.get('content-security-policy'),/frame-ancestors 'none'/);assert.match(await r.text(),/مركز الإدارة/);const js=await fetch(f.base+'/admin/assets/dashboard.js');assert.equal(js.status,200);assert.match(js.headers.get('content-type'),/javascript/);const body=await js.text();assert.ok(!body.includes('localStorage'));assert.ok(!body.includes('innerHTML'));assert.equal((await f.req(a,'GET','/v1/admin/metrics')).status,403);
});
test('33 new login alerts target existing account sockets and revocation closes the revoked session',async t=>{
 const f=await fixture(t),a=await f.user('alert33a'),b=await f.user('alert33b');
 async function socket(u){const w=new WebSocket(f.base.replace('http:','ws:')+'/v1/chat/socket');await once(w,'open');const ready=once(w,'message');w.send(JSON.stringify({type:'authenticate',token:u.token}));assert.equal(JSON.parse((await ready)[0]).type,'chat.ready');return w;}
 const wa=await socket(a),wb=await socket(b);t.after(()=>{wa.terminate();wb.terminate();});const stranger=[];wb.on('message',v=>stranger.push(JSON.parse(v)));
 const got=once(wa,'message'),second=(await login(f,a)).data;assert.equal(JSON.parse((await got)[0]).type,'security.new-login');assert.equal(stranger.length,0);
 const rows=(await f.req(second,'GET','/v1/me/sessions')).data.sessions,old=rows.find(s=>!s.current),closed=once(wa,'close');await f.req(second,'DELETE','/v1/me/sessions/'+old.id);await closed;assert.equal((await f.req(a,'GET','/v1/me')).status,401);
});
