import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture,people,password} from './fixtures/platform-api.mjs';
async function ready(t){const f=await fixture(t),p=await people(f),post=await f.post(p.member);return {f,...p,post,share:(target=p.mod,pid=post.id,nonce=randomUUID(),actor=p.member)=>f.req(actor,'POST',`/v1/posts/${pid}/share`,{requestId:nonce,userId:target.user.id}),follow:(a,b)=>f.db.query('INSERT INTO tomi_follows(follower_id,following_id,created_at) VALUES(?,?,?) ON CONFLICT(follower_id,following_id) DO NOTHING',[a.user.id,b.user.id,new Date().toISOString()]),inbox:()=>f.req(p.mod,'GET','/v1/post-shares/requests'),act:(id,action='accept',nonce=randomUUID(),actor=p.mod)=>f.req(actor,'POST',`/v1/post-shares/requests/${id}`,{requestId:nonce,action})};}
test('1.6 followed accounts and followers receive shared posts in ordinary private messages',async t=>{
 const {f,member,mod,owner,post,share,follow}=await ready(t);await follow(member,mod);await follow(owner,member);
 for(const a of [mod,owner]){const r=await share(a);assert.equal(r.status,200,JSON.stringify(r));assert.equal(r.data.status,'delivered');const messages=(await f.req(a,'GET',`/v1/chats/${r.data.conversationId}/messages`)).data.messages;assert.equal(messages.length,1);assert.equal(messages[0].sharedPost.id,post.id);assert.equal(messages[0].sharedPost.available,true);assert.equal(messages[0].sharedPost.text,post.text);}
 assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_post_share_requests')).rows[0].n),0);
});
test('1.6 strangers enter requests without a conversation, unread count or notification until recipient accepts',async t=>{
 const {f,member,mod,post,share,inbox,act}=await ready(t),r=await share();assert.equal(r.status,200,JSON.stringify(r));assert.equal(r.data.status,'pending');const chats=(await f.req(mod,'GET','/v1/chats')).data;assert.deepEqual(chats.conversations,[]);assert.equal(chats.totalUnread,0);assert.equal(chats.shareRequestsCount,1);assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_push_outbox')).rows[0].n),0);
 const list=(await inbox()).data;assert.equal(list.items[0].sender.id,member.user.id);assert.equal(list.items[0].postId,post.id);const accepted=await act(r.data.requestId);assert.equal(accepted.status,200,JSON.stringify(accepted));assert.equal(accepted.data.status,'accepted');assert.equal((await inbox()).data.count,0);assert.equal((await f.req(mod,'GET','/v1/chats')).data.totalUnread,1);
 const next=await share(mod,(await f.post(member)).id);assert.equal(next.data.status,'delivered');
});
test('1.6 concurrent and restarted share retries preserve one pending request or one message and reject changed payloads',async t=>{
 const {f,member,mod,post,share,follow,inbox}=await ready(t),nonce=randomUUID();const rs=await Promise.all([share(mod,post.id,nonce),share(mod,post.id,nonce)]);assert.ok(rs.every(r=>r.status===200),JSON.stringify(rs));assert.equal((await inbox()).data.count,1);await f.restart();assert.equal((await share(mod,post.id,nonce)).data.replayed,true);assert.equal((await share(mod,(await f.post(member)).id,nonce)).status,409);
 await follow(member,mod);const direct=randomUUID(),ds=await Promise.all([share(mod,post.id,direct),share(mod,post.id,direct)]);assert.ok(ds.every(r=>r.status===200));assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_chat_messages WHERE sender_id=? AND request_id=?',[member.user.id,direct])).rows[0].n),1);
});
test('1.6 accepting concurrent requests from one sender delivers each available post exactly once',async t=>{
 const {f,member,mod,post,share,inbox,act}=await ready(t),nonce=randomUUID(),first=await share(mod,post.id,nonce),second=await share(mod,(await f.post(member)).id),actionNonce=randomUUID();const rs=await Promise.all([act(first.data.requestId,'accept',actionNonce),act(first.data.requestId,'accept',actionNonce)]);assert.ok(rs.every(r=>r.status===200),JSON.stringify(rs));assert.equal(rs[0].data.conversationId,rs[1].data.conversationId);const msgs=(await f.req(mod,'GET',`/v1/chats/${rs[0].data.conversationId}/messages`)).data.messages;assert.equal(msgs.length,2);assert.equal(new Set(msgs.map(m=>m.id)).size,2);assert.equal((await inbox()).data.count,0);assert.equal((await share(mod,post.id,nonce)).data.status,'delivered');assert.equal((await act(second.data.requestId)).status,200);assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_chat_messages')).rows[0].n),2);
});
test('1.6 request acceptance and blocking belong only to the recipient and request IDs cannot change action',async t=>{
 const {f,member,owner,share,act}=await ready(t),r=await share(),nonce=randomUUID();for(const actor of [member,owner])assert.equal((await act(r.data.requestId,'accept',randomUUID(),actor)).status,404);assert.equal((await act(r.data.requestId,'accept',nonce)).status,200);assert.equal((await act(r.data.requestId,'block',nonce)).status,409);assert.equal((await f.req(null,'POST',`/v1/post-shares/requests/${r.data.requestId}`,{requestId:randomUUID(),action:'accept'})).status,401);
});
test('1.6 blocking a stranger removes requests, revokes approval and prevents sharing in both directions',async t=>{
 const {f,member,mod,post,share,follow,inbox,act}=await ready(t),r=await share();assert.equal((await act(r.data.requestId,'block')).data.status,'blocked');assert.equal((await inbox()).data.count,0);await follow(member,mod);assert.equal((await share()).status,403);assert.equal((await share(member,post.id,randomUUID(),mod)).status,403);assert.equal((await act(r.data.requestId)).status,403);const contacts=(await f.req(member,'GET','/v1/post-shares/contacts')).data.users;assert.ok(contacts.every(u=>u.id!==mod.user.id));
});
test('1.6 deleted or moderated posts cannot be shared and private previews stop exposing their text after deletion',async t=>{
 const {f,member,mod,post,share,follow}=await ready(t);await follow(member,mod);const delivered=await share();assert.equal(delivered.status,200);assert.equal((await f.req(member,'DELETE',`/v1/posts/${post.id}`)).status,200);const m=(await f.req(mod,'GET',`/v1/chats/${delivered.data.conversationId}/messages`)).data.messages[0];assert.equal(m.sharedPost.available,false);assert.equal(m.sharedPost.text,'');assert.equal(m.sharedPost.id,null);assert.equal((await share()).status,404);
});
test('1.6 suspended senders cannot be accepted and invalid or self-directed shares never create requests',async t=>{
 const {f,owner,member,mod,post,share,act}=await ready(t),r=await share();await f.command(owner,'suspend_user',member.user.id);assert.equal((await act(r.data.requestId)).status,403);assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_chat_messages')).rows[0].n),0);
 assert.equal((await share(mod,post.id,randomUUID(),mod)).status,400);assert.equal((await f.req(mod,'POST',`/v1/posts/${post.id}/share`,{requestId:randomUUID(),userId:member.user.id,text:'forged'})).status,400);
});
test('1.6 request inbox pagination retains rows with the same timestamp and contacts include either follow direction',async t=>{
 const {f,member,mod,owner,post,follow}=await ready(t);await follow(member,mod);await follow(owner,member);const contacts=(await f.req(member,'GET','/v1/post-shares/contacts')).data.users;assert.deepEqual(new Set(contacts.map(u=>u.id)),new Set([mod.user.id,owner.user.id]));const stamp=new Date().toISOString();
 for(let i=0;i<35;i++)await f.db.query("INSERT INTO tomi_post_share_requests(id,sender_id,recipient_id,post_id,client_nonce,state,created_at,updated_at) VALUES(?,?,?,?,?,'pending',?,?)",[randomUUID(),member.user.id,mod.user.id,post.id,randomUUID(),stamp,stamp]);
 const a=(await f.req(mod,'GET','/v1/post-shares/requests')).data,b=(await f.req(mod,'GET','/v1/post-shares/requests?cursor='+a.nextCursor)).data;assert.equal(a.items.length,30);assert.equal(b.items.length,5);assert.equal(new Set([...a.items,...b.items].map(x=>x.id)).size,35);assert.equal((await f.req(mod,'GET','/v1/post-shares/requests?cursor=invalid')).status,400);
});
test('1.6 account erasure removes sent requests, receipts and shared-post links without reviving the sender',async t=>{
 const {f,member,mod,share}=await ready(t);await share();const r=await f.req(member,'POST','/v1/account/deletion',{password,confirmation:'حذف حسابي',requestId:randomUUID(),receiptToken:'w'.repeat(43)});assert.equal(r.status,202,JSON.stringify(r));assert.equal((await f.req(mod,'GET','/v1/post-shares/requests')).data.count,0);for(const table of ['tomi_post_share_requests','tomi_post_share_receipts','tomi_post_share_pairs'])assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM '+table+' WHERE sender_id=?',[member.user.id])).rows[0].n),0);
});

test('1.6 public charisma tiers follow owner grants and remain visible in profiles, posts and private peers',async t=>{
 const {f,owner,member,mod,post}=await ready(t);assert.equal((await f.command(owner,'add_charisma',member.user.id,{amount:12000})).status,200);
 const me=(await f.req(member,'GET','/v1/me')).data.user;assert.equal(me.identity.charisma,12000);assert.equal(me.identity.charismaTier.level,3);assert.equal(me.identity.charismaTier.icon,'⭐');
 const p=(await f.req(mod,'GET',`/v1/posts/${post.id}`)).data.post;assert.equal(p.author.identity.charismaTier.level,3);
 const c=(await f.req(mod,'POST','/v1/chats',{userId:member.user.id})).data.conversation;assert.equal(c.peer.identity.charismaTier.points,12000);
 await f.db.query('UPDATE tomi_user_progress SET received=3999 WHERE user_id=?',[member.user.id]);assert.equal((await f.req(member,'GET','/v1/me')).data.user.identity.charismaTier.level,1);
});
test('1.6 acceptance queued behind erasure never deadlocks or restores a deleted sender',async t=>{
 const {f,member,mod,share,act}=await ready(t),request=await share();
 if(f.db.dialect==='postgres'){
  let release,locked;const lockReady=new Promise(r=>locked=r),unlock=new Promise(r=>release=r);
  const hold=f.db.transaction(async db=>{await db.query('SELECT pg_advisory_xact_lock(172994,hashtext(?))',[member.user.id]);locked();await unlock;});await lockReady;
  let deleting,accepting;
  try{
   deleting=f.req(member,'POST','/v1/account/deletion',{password,confirmation:'حذف حسابي',requestId:randomUUID(),receiptToken:'z'.repeat(43)});
   let queued=false;const until=Date.now()+5000;
   while(Date.now()<until){const waits=(await f.db.query("SELECT COUNT(*) n FROM pg_locks WHERE locktype='advisory' AND NOT granted")).rows[0];if(Number(waits.n)>0){queued=true;break;}await new Promise(r=>setTimeout(r,10));}
   assert.ok(queued,'erasure must actually queue before acceptance starts');accepting=act(request.data.requestId);
  }finally{release();await hold;}
  const outcomes=await Promise.all([deleting,accepting]);assert.equal(outcomes[0].status,202);assert.ok([200,403,404,410].includes(outcomes[1].status),JSON.stringify(outcomes));
 }else{
  const outcomes=await Promise.all([f.req(member,'POST','/v1/account/deletion',{password,confirmation:'حذف حسابي',requestId:randomUUID(),receiptToken:'z'.repeat(43)}),act(request.data.requestId)]);assert.equal(outcomes[0].status,202);assert.ok([200,403,404,410].includes(outcomes[1].status));
 }
 assert.equal((await f.req(mod,'GET','/v1/post-shares/requests')).data.count,0);assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_post_share_receipts WHERE sender_id=?',[member.user.id])).rows[0].n),0);assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_chat_messages WHERE sender_id=? AND deleted_at IS NULL',[member.user.id])).rows[0].n),0);
});
