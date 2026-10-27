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
 const dir=await mkdtemp(join(tmpdir(),'tomi-home11-')),objects=new Map(),sent=[];
 const storage=images?new R2Images({endpoint:'https://'+'a'.repeat(32)+'.r2.cloudflarestorage.com',bucket:'tomi-test',accessKeyId:'test-access',secretAccessKey:'test-secret'},{fetcher:async(url,options)=>{const key=decodeURIComponent(new URL(url).pathname.slice('/tomi-test/'.length));if(options?.method==='DELETE'){objects.delete(key);return new Response(null,{status:204});}const value=objects.get(key);return value?new Response(value.bytes,{headers:{'content-type':value.type,'content-length':String(value.bytes.length)}}):new Response(null,{status:404});}}):null;
 let db,server,base;
 async function start(reset=false){db=await openDatabase({connectionString,sqliteFile:join(dir,'home.sqlite')});if(reset&&connectionString){await db.query('DELETE FROM tomi_users');await db.query('DELETE FROM tomi_rate_limits');}server=await createApp({database:db,storage,pushSender:push?async data=>{sent.push(data);return 'sent';}:null,pushAutoFlush:false});server.listen(0,'127.0.0.1');await once(server,'listening');base='http://127.0.0.1:'+server.address().port;}
 async function stop(){if(server){const done=new Promise((resolve,reject)=>server.close(e=>e?reject(e):resolve()));server.closeIdleConnections();await done;server=null;}if(db){await db.close();db=null;}}
 await start(true);t.after(async()=>{await stop();await rm(dir,{recursive:true,force:true});});
 return {get db(){return db;},get server(){return server;},objects,sent,async restart(){await stop();await start();},async request(method,path,body,token){const r=await fetch(base+path,{method,headers:{...(body!==undefined?{'content-type':'application/json'}:{}),...(token?{authorization:'Bearer '+token}:{})},...(body!==undefined?{body:JSON.stringify(body)}:{})});return {status:r.status,data:await r.json()};},async register(username){const r=await this.request('POST','/v1/auth/register',{username,displayName:username,password:'long TOMI passphrase for home test'});assert.equal(r.status,201);return r.data;},async story(user,extra={}){return this.request('POST','/v1/stories',{requestId:randomUUID(),text:'لحظة جديدة',...extra},user.token);},async upload(user){const r=await this.request('POST','/v1/media/images',{contentType:'image/png',byteLength:png.length,contentMd5:createHash('md5').update(png).digest('base64'),contentSha256:sha(png),requestId:randomUUID()},user.token);assert.equal(r.status,201);const row=(await db.query('SELECT * FROM tomi_image_uploads WHERE id=?',[r.data.uploadId])).rows[0];objects.set(row.object_key,{bytes:png,type:'image/png'});return r.data.uploadId;}};
}
test('stories persist, expire after24h, follow feed and author rings track real active stories',async t=>{
 const a=await fixture(t),u=await a.register('story_owner'),v=await a.register('story_viewer');
 assert.equal((await a.request('GET','/v1/stories')).status,401);
 assert.equal((await a.request('GET','/v1/users/'+u.user.id,undefined,v.token)).data.user.hasStory,false);
 const r=await a.story(u);assert.equal(r.status,201);const s=r.data.story;assert.equal(Date.parse(s.expiresAt)-Date.parse(s.createdAt),86400000);
 assert.equal((await a.request('GET','/v1/stories',undefined,v.token)).data.groups.length,0);
 await a.request('PUT','/v1/users/'+u.user.id+'/follow',{follow:true},v.token);
 assert.equal((await a.request('GET','/v1/stories',undefined,v.token)).data.groups.length,1);
 const post=await a.request('POST','/v1/posts',{text:'منشور',requestId:randomUUID()},u.token);assert.equal(post.data.post.author.hasStory,true);
 await a.restart();assert.equal((await a.request('GET','/v1/stories?userId='+u.user.id,undefined,v.token)).data.groups[0].stories[0].id,s.id);
 for(let i=0;i<2;i++)assert.equal((await a.request('PUT','/v1/stories/'+s.id+'/view',{},v.token)).status,200);
 assert.equal((await a.request('GET','/v1/stories/'+s.id,undefined,u.token)).data.story.viewsCount,1);
 assert.equal((await a.request('GET','/v1/stories/'+s.id+'/viewers',undefined,v.token)).status,403);
 assert.equal((await a.request('DELETE','/v1/stories/'+s.id,undefined,v.token)).status,403);
 await a.db.query('UPDATE tomi_stories SET expires_at=? WHERE id=?',['2000-01-01T00:00:00.000Z',s.id]);
 assert.equal((await a.request('GET','/v1/stories/'+s.id,undefined,v.token)).status,404);
 assert.equal((await a.request('GET','/v1/users/'+u.user.id,undefined,v.token)).data.user.hasStory,false);
 assert.equal((await a.request('GET','/v1/posts/'+post.data.post.id,undefined,v.token)).data.post.author.hasStory,false);
 await a.server.cleanupMedia();assert.equal((await a.db.query('SELECT id FROM tomi_stories')).rows.length,0);assert.equal((await a.db.query('SELECT * FROM tomi_story_views')).rows.length,0);
});
test('story retries cannot duplicate, revive deleted content, attach foreign or reused media',async t=>{
 const a=await fixture(t,{images:true}),u=await a.register('media_owner'),v=await a.register('media_other');
 const body={text:'محفوظ',requestId:randomUUID()},r=await Promise.all([a.request('POST','/v1/stories',body,u.token),a.request('POST','/v1/stories',body,u.token)]);assert.ok(r.every(x=>[200,201].includes(x.status)));assert.equal(r[0].data.story.id,r[1].data.story.id);
 assert.equal((await a.request('POST','/v1/stories',{...body,text:'changed'},u.token)).status,409);
 await a.request('DELETE','/v1/stories/'+r[0].data.story.id,undefined,u.token);assert.equal((await a.request('POST','/v1/stories',body,u.token)).status,404);
 for(const extra of [{text:''},{text:'x'.repeat(501)},{requestId:'bad'},{userId:v.user.id}])assert.equal((await a.story(u,extra)).status,400);
 const upload=await a.upload(u);assert.equal((await a.story(v,{imageUploadId:upload,attachmentSha256:sha(png)})).status,400);
 const s=await a.story(u,{imageUploadId:upload,attachmentSha256:sha(png)});assert.equal(s.status,201);assert.equal(s.data.story.image.width,1);
 assert.equal((await a.request('POST','/v1/posts',{text:'reuse',imageUploadId:upload,requestId:randomUUID()},u.token)).status,400);
 assert.equal((await a.request('GET','/v1/me',undefined,u.token)).data.user.postsCount,0);
 await a.request('DELETE','/v1/stories/'+s.data.story.id,undefined,u.token);assert.equal((await a.db.query('SELECT state FROM tomi_image_uploads WHERE id=?',[upload])).rows[0].state,'deleting');
 await a.db.query('UPDATE tomi_image_uploads SET expires_at=? WHERE id=?',['2000-01-01T00:00:00.000Z',upload]);await a.server.cleanupMedia();assert.equal(a.objects.size,0);
});
test('followers paginate, activity is idempotent and private, store availability is honest',async t=>{
 const a=await fixture(t,{push:true}),u=await a.register('home_owner'),v=await a.register('home_friend'),w=await a.register('home_second');
 await a.request('PUT','/v1/push/device',{token:'test-device-token-1234567890',platform:'android'},u.token);
 for(const person of [v,w])for(let i=0;i<2;i++)await a.request('PUT','/v1/users/'+u.user.id+'/follow',{follow:true},person.token);
 const first=(await a.request('GET','/v1/users/'+u.user.id+'/followers?limit=1',undefined,u.token)).data;assert.equal(first.users.length,1);assert.ok(first.nextCursor);
 const second=(await a.request('GET','/v1/users/'+u.user.id+'/followers?limit=1&cursor='+first.nextCursor,undefined,u.token)).data;assert.notEqual(first.users[0].id,second.users[0].id);assert.equal(second.nextCursor,null);
 const p=(await a.request('POST','/v1/posts',{text:'خبر',requestId:randomUUID()},u.token)).data.post;
 for(let i=0;i<2;i++)await a.request('PUT','/v1/posts/'+p.id+'/like',{liked:true},v.token);
 const comment={text:'هلا',requestId:randomUUID()};for(let i=0;i<2;i++)await a.request('POST','/v1/posts/'+p.id+'/comments',comment,v.token);
 const activity=(await a.request('GET','/v1/activity',undefined,u.token)).data;assert.equal(activity.items.length,4);assert.equal(activity.unreadCount,4);
 assert.equal((await a.request('GET','/v1/activity',undefined,v.token)).data.items.length,0);
 await a.request('PUT','/v1/activity/read',{ids:[activity.items[0].id]},v.token);assert.equal((await a.request('GET','/v1/activity',undefined,u.token)).data.unreadCount,4);
 await a.server.flushPush();assert.equal(a.sent.length,4);assert.ok(a.sent.every(x=>x.activityId&&x.recipientId===u.user.id));await a.server.flushPush();assert.equal(a.sent.length,4);
 await a.request('PUT','/v1/activity/read',{ids:activity.items.map(x=>x.id)},u.token);assert.equal((await a.request('GET','/v1/activity',undefined,u.token)).data.unreadCount,0);
 await a.restart();assert.equal((await a.request('GET','/v1/activity',undefined,u.token)).data.items.length,4);
 const catalog=(await a.request('GET','/v1/subscriptions/catalog',undefined,u.token)).data;assert.equal(catalog.services.length,4);assert.equal(catalog.purchasesEnabled,false);assert.ok(catalog.services.every(x=>x.price===null&&!x.available));
 assert.equal((await a.request('GET','/v1/subscriptions/usernames?username=home_owner',undefined,u.token)).data.available,false);
 assert.equal((await a.request('GET','/v1/subscriptions/usernames?username=unused_name',undefined,u.token)).data.purchasable,false);
});
test('blocked and suspended authors disappear from stories and activity; account erasure removes new data',async t=>{
 const a=await fixture(t),u=await a.register('erase_stories'),v=await a.register('erase_viewer');await a.request('PUT','/v1/users/'+u.user.id+'/follow',{follow:true},v.token);await a.story(u);
 await a.db.query('INSERT INTO tomi_user_blocks(blocker_id,blocked_id,created_at) VALUES(?,?,?)',[v.user.id,u.user.id,new Date().toISOString()]);
 assert.equal((await a.request('GET','/v1/stories?userId='+u.user.id,undefined,v.token)).data.groups.length,0);assert.equal((await a.request('GET','/v1/activity',undefined,u.token)).data.items.length,0);
 assert.equal((await a.request('GET','/v1/users/'+u.user.id+'/followers',undefined,v.token)).status,403);
 await a.db.query('DELETE FROM tomi_user_blocks');const deletion=await a.request('POST','/v1/account/deletion',{password:'long TOMI passphrase for home test',confirmation:'حذف حسابي',requestId:randomUUID(),receiptToken:Buffer.alloc(32,7).toString('base64url')},u.token);assert.equal(deletion.status,202,JSON.stringify(deletion.data));
 for(const table of ['tomi_stories','tomi_story_receipts','tomi_story_views','tomi_activity'])assert.equal((await a.db.query('SELECT * FROM '+table)).rows.length,0,table);
});
test('saved posts are private, paginated and removed with their source post',async t=>{
 const a=await fixture(t),u=await a.register('save_owner'),v=await a.register('save_viewer');const p=(await a.request('POST','/v1/posts',{text:'احفظني',requestId:randomUUID()},u.token)).data.post;
 for(let i=0;i<2;i++)assert.equal((await a.request('PUT','/v1/posts/'+p.id+'/save',{saved:true},v.token)).data.post.saved,true);
 assert.equal((await a.request('GET','/v1/posts?scope=saved',undefined,v.token)).data.posts.length,1);assert.equal((await a.request('GET','/v1/posts?scope=saved',undefined,u.token)).data.posts.length,0);
 await a.restart();assert.equal((await a.request('GET','/v1/posts/'+p.id,undefined,v.token)).data.post.saved,true);
 await a.request('PUT','/v1/posts/'+p.id+'/save',{saved:false},v.token);assert.equal((await a.request('GET','/v1/posts?scope=saved',undefined,v.token)).data.posts.length,0);
 await a.request('PUT','/v1/posts/'+p.id+'/save',{saved:true},v.token);await a.request('DELETE','/v1/posts/'+p.id,undefined,u.token);assert.equal((await a.db.query('SELECT * FROM tomi_post_saves')).rows.length,0);
});
test('real MP4 story publication bounds duration, survives lost acknowledgement and expires its media',async t=>{
 const {readFile}=await import('node:fs/promises'),{videoMetadata}=await import('../src/video.mjs');
 const a=await fixture(t,{images:true}),u=await a.register('video_story');
 async function prepare(bytes){const d=await a.request('POST','/v1/media/videos',{contentType:'video/mp4',byteLength:bytes.length,contentMd5:createHash('md5').update(bytes).digest('base64'),contentSha256:sha(bytes),requestId:randomUUID()},u.token);assert.equal(d.status,201);const row=(await a.db.query('SELECT * FROM tomi_video_uploads WHERE id=?',[d.data.uploadId])).rows[0];a.objects.set(row.object_key,{bytes,type:'video/mp4'});return d.data.uploadId;}
 const bytes=await readFile(new URL('fixtures/video10.mp4',import.meta.url)),id=await prepare(bytes),body={requestId:randomUUID(),videoUploadId:id,attachmentSha256:sha(bytes),text:''};
 // Pause a retry after its empty receipt read; let the other request attach
 // the media and commit its receipt before this retry reads the upload state.
 // This makes the previously intermittent PostgreSQL race deterministic.
 const originalQuery=a.db.query;let release,observed,paused=false;
 const resume=new Promise(r=>release=r),miss=new Promise(r=>observed=r);
 a.db.query=async(sql,values=[])=>{const result=await originalQuery(sql,values);if(!paused&&sql.startsWith('SELECT * FROM tomi_story_receipts')&&values[1]===body.requestId){paused=true;observed();await resume;}return result;};
 let results;const retry=a.request('POST','/v1/stories',body,u.token);
 try{await Promise.race([miss,retry.then(()=>{throw Error('Retry finished before its receipt checkpoint');})]);const first=await a.request('POST','/v1/stories',body,u.token);release();results=[first,await retry];}
 finally{release();a.db.query=originalQuery;await retry.catch(()=>{});}
 assert.ok(results.every(x=>[200,201].includes(x.status)),JSON.stringify(results));assert.equal(results[0].data.story.id,results[1].data.story.id);assert.equal(results[0].data.story.video.durationMs,1000);
 const long=Buffer.from(bytes);let at=0;while((at=long.indexOf('mdhd',at))>=0){const payload=at+4;assert.equal(long[payload],0);const scale=long.readUInt32BE(payload+12);long.writeUInt32BE(scale*61,payload+16);at+=4;}
 assert.equal(videoMetadata(long).durationMs,61000);const tooLong=await prepare(long);assert.equal((await a.story(u,{text:'',videoUploadId:tooLong,attachmentSha256:sha(long)})).data.error.code,'STORY_DURATION');
 await a.db.query('UPDATE tomi_stories SET expires_at=?',['2000-01-01T00:00:00.000Z']);await a.server.cleanupMedia();assert.equal((await a.db.query('SELECT state FROM tomi_video_uploads WHERE id=?',[id])).rows[0].state,'deleting');
});
test('social push payloads use a real channel, contain no content and route to the matching account',async()=>{
 const {generateKeyPairSync}=await import('node:crypto'),{fcmFromEnvironment}=await import('../src/push.mjs');const {privateKey}=generateKeyPairSync('rsa',{modulusLength:2048}),messages=[];
 const sender=fcmFromEnvironment({FCM_SERVICE_ACCOUNT_JSON:JSON.stringify({type:'service_account',project_id:'tomi-test-project',client_email:'service@tomi-test-project.iam.gserviceaccount.com',private_key:privateKey.export({type:'pkcs8',format:'pem'})})},{fetcher:async(url,opts)=>{if(url.includes('oauth2'))return Response.json({access_token:'test-oauth',expires_in:3600});messages.push(JSON.parse(opts.body).message);return Response.json({name:'sent'});}});
 const recipientId=randomUUID(),activityId=randomUUID();await sender({token:'test-token',recipientId,activityId,notificationKind:'like'});const m=messages[0];assert.deepEqual(m.data,{type:'activity',activityId,accountId:recipientId});assert.equal(m.android.notification.channel_id,'tomi_updates');assert.equal(m.notification.body,'إعجاب جديد بمنشورك في TOMI');assert.ok(Object.values(m.data).every(x=>typeof x==='string'));assert.equal(JSON.stringify(m).includes('password'),false);
});
