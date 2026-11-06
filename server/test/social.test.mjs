import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {once} from 'node:events';
import {openDatabase} from '../src/database.mjs';
import {createApp} from '../src/app.mjs';
import {R2Images,signS3Url,r2FromEnvironment} from '../src/r2.mjs';
import {imageDimensions} from '../src/images.mjs';
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jftkAAAAASUVORK5CYII=','base64');
const md5=b=>createHash('md5').update(b).digest('base64');
const connectionString=process.env.TEST_DATABASE_URL;
if(connectionString){const u=new URL(connectionString);assert.ok(['localhost','127.0.0.1'].includes(u.hostname)&&u.pathname==='/tomi_test');}
async function fixture(t,{images=false}={}){
 const dir=await mkdtemp(join(tmpdir(),'tomi-social-')),objects=new Map();
 const storage=images?new R2Images({endpoint:'https://'+'a'.repeat(32)+'.r2.cloudflarestorage.com',bucket:'tomi-test',accessKeyId:'test-access',secretAccessKey:'test-secret'},{fetcher:async(url,opts)=>{
  const key=decodeURIComponent(new URL(url).pathname.slice('/tomi-test/'.length));
  if(opts?.method==='DELETE'){objects.delete(key);return new Response(null,{status:204});}
  const o=objects.get(key);return o?new Response(o.bytes,{headers:{'content-type':o.type,'content-length':String(o.bytes.length)}}):new Response(null,{status:404});
 }}):null;
 let db,server,base;
 async function start(reset=false){db=await openDatabase({connectionString,sqliteFile:join(dir,'test.sqlite')});if(reset&&connectionString){await db.query('DELETE FROM tomi_users');await db.query('DELETE FROM tomi_rate_limits');}server=await createApp({database:db,storage,rateLimitMultiplier:10});server.listen(0,'127.0.0.1');await once(server,'listening');base='http://127.0.0.1:'+server.address().port;}
 async function stop(){if(server){const done=new Promise((res,rej)=>server.close(e=>e?rej(e):res()));server.closeIdleConnections();await done;server=null;}if(db){await db.close();db=null;}}
 await start(true);t.after(async()=>{await stop();await rm(dir,{recursive:true,force:true});});
 return {get db(){return db;},get server(){return server;},storage,objects,async restart(){await stop();await start();},async request(method,path,body,token){const r=await fetch(base+path,{method,headers:{...(body!==undefined?{'content-type':'application/json'}:{}),...(token?{authorization:'Bearer '+token}:{})},...(body!==undefined?{body:JSON.stringify(body)}:{})});return{status:r.status,data:await r.json()};},async register(name){const r=await this.request('POST','/v1/auth/register',{username:name,displayName:name,password:'long passphrase for TOMI testing'});assert.equal(r.status,201);return r.data;},async post(u,text,extra={}){return this.request('POST','/v1/posts',{text,requestId:randomUUID(),...extra},u.token);},async upload(u,bytes=png,type='image/png'){const r=await this.request('POST','/v1/media/images',{contentType:type,byteLength:bytes.length,contentMd5:md5(bytes)},u.token);assert.equal(r.status,201);const row=(await db.query('SELECT * FROM tomi_image_uploads WHERE id=?',[r.data.uploadId])).rows[0];objects.set(row.object_key,{bytes,type});return r.data;}};
}
test('text posts and profile counts survive restart; text works without R2',async t=>{
 const a=await fixture(t),u=await a.register('writer'),v=await a.register('reader');const p=await a.post(u,'أول منشور 💜');assert.equal(p.status,201);assert.equal(p.data.user.postsCount,1);await a.restart();const f=await a.request('GET','/v1/posts',undefined,v.token);assert.equal(f.data.posts[0].text,'أول منشور 💜');assert.equal(f.data.posts[0].isMine,false);assert.equal((await a.request('GET','/v1/me',undefined,u.token)).data.user.postsCount,1);assert.equal(f.data.imageUploadEnabled,false);assert.equal((await a.request('POST','/v1/media/images',{},u.token)).data.error.code,'IMAGES_DISABLED');
});
test('simultaneous and repeated requests cannot duplicate posts or comments',async t=>{
 const a=await fixture(t),u=await a.register('retry_user'),b={text:'retry safely',requestId:randomUUID()};const r=await Promise.all([a.request('POST','/v1/posts',b,u.token),a.request('POST','/v1/posts',b,u.token)]);assert.ok(r.every(v=>[200,201].includes(v.status)));assert.equal(r[0].data.post.id,r[1].data.post.id);assert.equal((await a.request('POST','/v1/posts',{...b,text:'changed'},u.token)).status,409);const path='/v1/posts/'+r[0].data.post.id+'/comments',c={text:'تعليق',requestId:randomUUID()};for(let i=0;i<2;i++)assert.equal((await a.request('POST',path,c,u.token)).status,201);assert.equal((await a.request('GET',path,undefined,u.token)).data.comments.length,1);
});
test('likes are idempotent; author and comment ownership are enforced',async t=>{
 const a=await fixture(t),u=await a.register('author'),v=await a.register('friend'),w=await a.register('stranger');const p=(await a.post(u,'like and comment')).data.post,path='/v1/posts/'+p.id;for(let i=0;i<2;i++)assert.equal((await a.request('PUT',path+'/like',{liked:true},v.token)).data.post.likesCount,1);assert.equal((await a.request('PUT',path+'/like',{liked:false},v.token)).data.post.likesCount,0);const c=(await a.request('POST',path+'/comments',{text:'هلا',requestId:randomUUID()},v.token)).data.comment;assert.equal((await a.request('DELETE','/v1/comments/'+c.id,undefined,w.token)).status,403);assert.equal((await a.request('DELETE','/v1/comments/'+c.id,undefined,u.token)).data.post.commentsCount,0);assert.equal((await a.request('DELETE',path,undefined,v.token)).status,403);await a.request('POST',path+'/comments',{text:'another',requestId:randomUUID()},v.token);assert.equal((await a.request('DELETE',path,undefined,u.token)).data.user.postsCount,0);assert.equal(Number((await a.db.query('SELECT COUNT(*) AS n FROM tomi_comments')).rows[0].n),0);
});
test('following and own feeds paginate without duplicates at equal timestamps',async t=>{
 const a=await fixture(t),u=await a.register('viewer'),v=await a.register('followed'),w=await a.register('unfollowed');await a.request('PUT','/v1/users/'+v.user.id+'/follow',{follow:true},u.token);for(const person of [u,v,w,v,v])await a.post(person,'post from '+person.user.username);await a.db.query('UPDATE tomi_posts SET created_at=?',['2026-10-13T00:00:00.000Z']);const f=await a.request('GET','/v1/posts?scope=following',undefined,u.token);assert.equal(f.data.posts.length,4);assert.ok(f.data.posts.every(p=>p.author.id!==w.user.id));assert.equal((await a.request('GET','/v1/posts?scope=mine',undefined,u.token)).data.posts.length,1);let cursor=null,ids=[];do{const r=await a.request('GET','/v1/posts?limit=2'+(cursor?'&cursor='+encodeURIComponent(cursor):''),undefined,u.token);ids.push(...r.data.posts.map(p=>p.id));cursor=r.data.nextCursor;}while(cursor);assert.equal(ids.length,5);assert.equal(new Set(ids).size,5);assert.equal((await a.request('GET','/v1/posts?cursor=bad',undefined,u.token)).status,400);
});
test('unauthenticated, empty, oversized and forged content is refused',async t=>{
 const a=await fixture(t),u=await a.register('validation');assert.equal((await a.request('GET','/v1/posts')).status,401);for(const b of [{text:'',requestId:randomUUID()},{text:'x'.repeat(2001),requestId:randomUUID()},{text:'good',requestId:'bad'},{text:'good',requestId:randomUUID(),userId:randomUUID()}])assert.equal((await a.request('POST','/v1/posts',b,u.token)).status,400);assert.equal((await a.request('GET','/v1/posts?limit=99',undefined,u.token)).status,400);
});
test('image publication checks bytes and ownership; deleting queues safe cleanup',async t=>{
 const a=await fixture(t,{images:true}),u=await a.register('image_author'),v=await a.register('image_other'),up=await a.upload(u);assert.equal(up.headers['if-none-match'],'*');assert.equal(new URL(up.uploadUrl).searchParams.get('X-Amz-Expires'),'900');assert.ok(new URL(up.uploadUrl).searchParams.get('X-Amz-SignedHeaders').includes('content-md5'));assert.equal((await a.post(v,'foreign',{imageUploadId:up.uploadId})).status,400);const p=await a.post(u,'',{imageUploadId:up.uploadId});assert.equal(p.status,201);assert.equal(p.data.post.image.width,1);assert.match(p.data.post.image.url,/r2.cloudflarestorage.com/);assert.equal((await a.post(u,'reused',{imageUploadId:up.uploadId})).status,400);await a.restart();assert.equal((await a.request('GET','/v1/posts',undefined,v.token)).data.posts[0].image.height,1);await a.request('DELETE','/v1/posts/'+p.data.post.id,undefined,u.token);await a.db.query('UPDATE tomi_image_uploads SET expires_at=? WHERE id=?',['2000-01-01T00:00:00.000Z',up.uploadId]);await a.server.cleanupMedia();assert.equal(a.objects.size,0);assert.equal((await a.db.query('SELECT id FROM tomi_image_uploads')).rows.length,0);
});
test('missing, checksum-mismatched and fake image files are never published',async t=>{
 const a=await fixture(t,{images:true}),u=await a.register('bad_images'),up=await a.upload(u),row=(await a.db.query('SELECT * FROM tomi_image_uploads WHERE id=?',[up.uploadId])).rows[0];a.objects.delete(row.object_key);assert.equal((await a.post(u,'missing',{imageUploadId:up.uploadId})).status,409);a.objects.set(row.object_key,{bytes:Buffer.alloc(png.length),type:'image/png'});assert.equal((await a.post(u,'checksum',{imageUploadId:up.uploadId})).status,400);const fake=Buffer.from('this is definitely not a real image file'),second=await a.upload(u,fake);assert.equal((await a.post(u,'fake',{imageUploadId:second.uploadId})).status,400);assert.equal((await a.request('GET','/v1/me',undefined,u.token)).data.user.postsCount,0);
});
test('R2 signing matches the published AWS Signature V4 test vector',()=>{
 const url=signS3Url({endpoint:'https://examplebucket.s3.amazonaws.com',bucket:'',key:'test.txt',region:'us-east-1',accessKeyId:'AKIAIOSFODNN7EXAMPLE',secretAccessKey:'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',expires:86400,now:new Date('2013-05-24T00:00:00Z')});assert.equal(new URL(url).searchParams.get('X-Amz-Signature'),'aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404');assert.equal(r2FromEnvironment({}),null);assert.throws(()=>r2FromEnvironment({R2_ACCOUNT_ID:'partial'}));assert.deepEqual(imageDimensions(png,'image/png'),{width:1,height:1});
});

test('explore includes every public post including own and followed accounts but excludes follower-only distribution',async t=>{
 const a=await fixture(t),u=await a.register('explore_viewer'),v=await a.register('explore_followed'),w=await a.register('explore_other');
 await a.request('PUT','/v1/users/'+v.user.id+'/follow',{follow:true},u.token);
 for(const person of [u,v,w])await a.post(person,'ordinary public content');
 const found=await a.request('GET','/v1/posts?scope=explore',undefined,u.token);
 assert.equal(found.status,200);assert.equal(found.data.posts.length,3);assert.deepEqual(new Set(found.data.posts.map(p=>p.author.id)),new Set([u.user.id,v.user.id,w.user.id]));
 await a.request('PUT','/v1/users/'+w.user.id+'/follow',{follow:true},u.token);
 await a.request('POST','/v1/posts',{requestId:randomUUID(),text:'followers only',audience:'followers'},v.token);
 assert.equal((await a.request('GET','/v1/posts?scope=explore',undefined,u.token)).data.posts.length,3);
});
