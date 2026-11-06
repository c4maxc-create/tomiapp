import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {once} from 'node:events';
import {openDatabase} from '../src/database.mjs';
import {createApp} from '../src/app.mjs';
import {requireContact} from '../src/contact_preferences.mjs';
async function fixture(t){
 const dir=await mkdtemp(join(tmpdir(),'tomi32-')),db=await openDatabase({connectionString:process.env.TEST_DATABASE_URL,sqliteFile:join(dir,'test.sqlite')});
 if(process.env.TEST_DATABASE_URL){await db.query('DELETE FROM tomi_users');await db.query('DELETE FROM tomi_rate_limits');}
 const server=await createApp({database:db,rateLimitMultiplier:30,callAutoSweep:false,roomAutoSweep:false,liveAutoTick:false,pushAutoFlush:false,pushSender:async()=> 'sent',iceProvider:async()=>({iceServers:[{urls:['turn:relay.example.com'],username:'test',credential:'test'}]})});
 server.listen(0,'127.0.0.1');await once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
 t.after(async()=>{const done=once(server,'close');server.close();server.closeIdleConnections();await done;await db.close();await rm(dir,{recursive:true,force:true});});
 const f={db,async req(a,method,path,body){const r=await fetch(base+path,{method,headers:{...(a?{authorization:'Bearer '+a.token}:{}),...(body?{'content-type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,data:await r.json()};},async user(name){const r=await this.req(null,'POST','/v1/auth/register',{username:name,displayName:name,password:'test-only improvements32 passphrase'});assert.equal(r.status,201);return r.data;}};return f;
}
const prefs=(messages='everyone',calls='everyone',roomInvites='everyone')=>({messages,calls,roomInvites});
test('32 contact preferences persist per account, validate all fields and require authentication',async t=>{
 const f=await fixture(t),a=await f.user('pref32a'),b=await f.user('pref32b');
 assert.equal((await f.req(null,'GET','/v1/me/contact-preferences')).status,401);
 assert.deepEqual((await f.req(a,'GET','/v1/me/contact-preferences')).data.preferences,prefs());
 assert.equal((await f.req(a,'PUT','/v1/me/contact-preferences',{...prefs(),calls:'invalid'})).status,400);
 assert.equal((await f.req(a,'PUT','/v1/me/contact-preferences',{toString:'everyone',calls:'everyone',roomInvites:'everyone'})).status,400);
 assert.equal((await f.req(a,'PUT','/v1/me/contact-preferences',prefs('following','nobody','nobody'))).status,200);
 assert.deepEqual((await f.req(a,'GET','/v1/me/contact-preferences')).data.preferences,prefs('following','nobody','nobody'));
 assert.deepEqual((await f.req(b,'GET','/v1/me/contact-preferences')).data.preferences,prefs());
});
test('32 existing direct threads cannot bypass contact policy and accepted messages keep their receipt',async t=>{
 const f=await fixture(t),a=await f.user('send32a'),b=await f.user('send32b'),c=(await f.req(a,'POST','/v1/chats',{userId:b.user.id})).data.conversation;
 const body={text:'مرحبا',requestId:randomUUID()},path=`/v1/chats/${c.id}/messages`;
 const first=await f.req(a,'POST',path,body);assert.equal(first.status,201);
 await f.req(b,'PUT','/v1/me/contact-preferences',prefs('nobody'));
 assert.equal((await f.req(a,'POST',path,{text:'مرفوض',requestId:randomUUID()})).data.error.code,'CONTACT_RESTRICTED');
 assert.equal((await f.req(a,'POST',path,body)).data.message.id,first.data.message.id);
 await f.req(b,'PUT','/v1/me/contact-preferences',prefs('following'));
 assert.equal((await f.req(a,'POST','/v1/chats',{userId:b.user.id})).status,403);
 await f.db.query('INSERT INTO tomi_follows(follower_id,following_id,created_at) VALUES(?,?,?)',[b.user.id,a.user.id,new Date().toISOString()]);
 assert.equal((await f.req(a,'POST',path,{text:'مسموح',requestId:randomUUID()})).status,201);
});
test('32 call and room microphone invitations respect recipient choices',async t=>{
 const f=await fixture(t),a=await f.user('call32a'),b=await f.user('call32b'),c=(await f.req(a,'POST','/v1/chats',{userId:b.user.id})).data.conversation;
 await f.req(b,'PUT','/v1/me/contact-preferences',prefs('everyone','nobody','nobody'));
 assert.equal((await f.req(a,'POST','/v1/calls',{requestId:randomUUID(),conversationId:c.id,kind:'audio'})).data.error.code,'CONTACT_RESTRICTED');
 await assert.rejects(()=>requireContact(f.db,b.user.id,a.user.id,'roomInvites'),e=>e.code==='CONTACT_RESTRICTED');
 await f.req(b,'PUT','/v1/me/contact-preferences',prefs());
 assert.equal((await f.req(a,'POST','/v1/calls',{requestId:randomUUID(),conversationId:c.id,kind:'audio'})).status,201);
});
test('32 muted chats still deliver messages, suppress new push jobs and cannot be changed by outsiders',async t=>{
 const f=await fixture(t),a=await f.user('mute32a'),b=await f.user('mute32b'),z=await f.user('mute32z'),c=(await f.req(a,'POST','/v1/chats',{userId:b.user.id})).data.conversation,path=`/v1/chats/${c.id}/mute`;
 assert.equal((await f.req(z,'PUT',path,{muted:true})).status,404);
 assert.equal((await f.req(b,'PUT',path,{muted:true})).data.muted,true);
 const message=await f.req(a,'POST',`/v1/chats/${c.id}/messages`,{text:'بدون تنبيه',requestId:randomUUID()});assert.equal(message.status,201);
 assert.equal((await f.db.query('SELECT * FROM tomi_push_outbox WHERE message_id=?',[message.data.message.id])).rows.length,0);
 assert.equal((await f.req(b,'GET',path)).data.muted,true);
 assert.equal((await f.req(b,'PUT',path,{muted:false})).data.muted,false);
});
test('32 real video preview is account-owned, immutable and returned with public video metadata',async t=>{
 const f=await fixture(t),a=await f.user('poster32a'),b=await f.user('poster32b'),id=randomUUID(),stamp=new Date().toISOString();
 await f.db.query("INSERT INTO tomi_video_uploads(id,user_id,object_key,content_type,byte_length,content_md5,state,created_at,expires_at,width,height,duration_ms) VALUES(?,?,?,?,?,?,'pending',?,?,?,?,?)",[id,a.user.id,'tomi/posts/'+a.user.id+'/'+id+'.mp4','video/mp4',100,'test',stamp,new Date(Date.now()+60000).toISOString(),320,180,1000]);
 const poster='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jftkAAAAASUVORK5CYII=',path=`/v1/media/videos/${id}/poster`;
 assert.equal((await f.req(b,'PUT',path,{poster})).status,404);
 assert.equal((await f.req(a,'PUT',path,{poster})).status,200);
 assert.equal((await f.req(a,'PUT',path,{poster})).status,200);
 assert.equal((await f.req(a,'PUT',path,{poster:'data:text/html;base64,abcd'})).status,400);
 const post=randomUUID();await f.db.query('INSERT INTO tomi_posts(id,user_id,request_id,body,created_at) VALUES(?,?,?,?,?)',[post,a.user.id,randomUUID(),'فيديو',stamp]);await f.db.query('INSERT INTO tomi_post_video(post_id,upload_id) VALUES(?,?)',[post,id]);
 assert.equal((await f.req(b,'GET','/v1/posts?scope=explore')).data.posts.find(p=>p.id===post).video.poster,poster);
});
