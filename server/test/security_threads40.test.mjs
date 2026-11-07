import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {once} from 'node:events';
import {WebSocket} from 'ws';
import {fixture} from './fixtures/platform-api.mjs';
const comment=async(f,a,p,text,parentId)=>{const r=await f.req(a,'POST',`/v1/posts/${p.id}/comments`,{text,requestId:randomUUID(),...(parentId?{parentId}:{})});assert.equal(r.status,201,JSON.stringify(r));return r;};
test('40 comment threads page roots and nested replies without accepting a different post or unauthorized deletion',async t=>{
 const f=await fixture(t),a=await f.register('thread40a'),b=await f.register('thread40b'),c=await f.register('thread40c'),p=await f.post(a),other=await f.post(b);
 const root=(await comment(f,b,p,'root')).data.comment;
 const first=(await comment(f,c,p,'first',root.id)).data.comment;
 const second=(await comment(f,b,p,'reply to first',first.id)).data.comment;
 const path=`/v1/posts/${p.id}/comments`;
 const page=(await f.req(a,'GET',path+'?threaded=true')).data;assert.equal(page.comments.length,1);assert.equal(page.comments[0].replyCount,2);
 const r1=(await f.req(a,'GET',path+'?parentId='+root.id+'&limit=1')).data;
 assert.equal(r1.comments.length,1);assert.ok(r1.nextCursor);assert.equal(r1.root.id,root.id);
 const r2=(await f.req(a,'GET',path+'?parentId='+root.id+'&limit=1&cursor='+r1.nextCursor)).data;
 assert.equal(r2.comments[0].id,second.id);assert.equal(r2.comments[0].replyToUsername,c.user.username);assert.equal(r2.comments[0].rootId,root.id);
 assert.equal((await f.req(a,'GET',`/v1/posts/${other.id}/comments?parentId=${root.id}`)).status,404);
 assert.equal((await f.req(c,'DELETE','/v1/comments/'+root.id)).status,403);
 assert.equal((await f.req(b,'DELETE','/v1/comments/'+root.id)).status,200);
 assert.equal((await f.req(a,'GET',path+'?threaded=true')).data.comments.length,0);
 assert.equal((await f.req(a,'GET',path)).data.comments.length,0);
});
test('40 follower-only story access is enforced for direct IDs, author pages and view receipts',async t=>{
 const f=await fixture(t),a=await f.register('story40a'),b=await f.register('story40b');
 const s=(await f.req(a,'POST','/v1/stories',{text:'private story',audience:'followers',requestId:randomUUID()})).data.story;assert.ok(s);
 assert.equal((await f.req(b,'GET','/v1/stories/'+s.id)).status,404);
 assert.equal((await f.req(b,'PUT','/v1/stories/'+s.id+'/view',{})).status,404);
 assert.equal((await f.req(b,'GET','/v1/stories?userId='+a.user.id)).data.groups.length,0);
 await f.req(b,'PUT','/v1/users/'+a.user.id+'/follow',{follow:true});assert.equal((await f.req(b,'GET','/v1/stories/'+s.id)).status,200);
 await f.req(b,'PUT','/v1/users/'+a.user.id+'/follow',{follow:false});assert.equal((await f.req(b,'GET','/v1/stories/'+s.id)).status,404);
 const pub=(await f.req(a,'POST','/v1/stories',{text:'public',audience:'public',requestId:randomUUID()})).data.story;
 assert.equal((await f.req(b,'GET','/v1/stories/'+pub.id)).status,200);
});
test('40 JSON pollution gadgets, excessive nesting, malformed UTF8 and false JSON MIME types are rejected',async t=>{
 const f=await fixture(t),path=f.base+'/v1/auth/login';
 for(const payload of ['{"__proto__":{"admin":true}}','{"context":{"constructor":{"prototype":{"admin":true}}}}','{"context":'+ '['.repeat(40)+'0'+']'.repeat(40)+'}',Buffer.from([0xff])]){
  const r=await fetch(path,{method:'POST',headers:{'content-type':'application/json'},body:payload});assert.equal(r.status,400);
 }
 assert.equal({}.admin,undefined);
 assert.equal((await fetch(path,{method:'POST',headers:{'content-type':'application/json-invalid'},body:'{}'})).status,415);
 assert.equal((await fetch(path,{method:'POST',headers:{'content-type':'application/json','content-encoding':'gzip'},body:'{}'})).status,415);
 const health=await fetch(f.base+'/health');assert.equal(health.headers.get('x-frame-options'),'DENY');assert.match(health.headers.get('strict-transport-security'),/max-age=/);
 assert.equal(f.server.maxHeadersCount,64);
});
test('40 unauthenticated websocket slots are bounded per IP before database work and XFF cannot bypass the default',async t=>{
 const f=await fixture(t),sockets=[],url=f.base.replace('http:','ws:')+'/v1/chat/socket';
 t.after(()=>sockets.forEach(w=>w.terminate()));
 for(let i=0;i<8;i++){const w=new WebSocket(url,{headers:{'x-forwarded-for':'198.51.100.'+i}});w.on('error',()=>{});sockets.push(w);await once(w,'open');}
 const denied=new WebSocket(url,{headers:{'x-forwarded-for':'203.0.113.99'}});denied.on('error',()=>{});sockets.push(denied);
 const status=await new Promise(resolve=>denied.on('unexpected-response',(_,response)=>{response.resume();resolve(response.statusCode);}));assert.equal(status,429);
 const closed=once(sockets[0],'close');sockets[0].terminate();await closed;
 const allowed=new WebSocket(url);allowed.on('error',()=>{});sockets.push(allowed);await once(allowed,'open');
 allowed.send('null');const [code]=await once(allowed,'close');assert.equal(code,4401);
});
