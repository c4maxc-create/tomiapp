import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {once} from 'node:events';
import {WebSocket} from 'ws';
import {fixture} from './fixtures/platform-api.mjs';
import {newGame,performGameAction} from '../src/game_engine.mjs';
const kinds=['uno','snakes','jackaroo','camel','wheel'];
const start=(f,u,kind)=>f.req(u,'POST','/v1/games/search',{kind});
async function leave(f,u,id){const m=(await f.req(u,'GET','/v1/games/matches/'+id)).data.match;return f.req(u,'POST',`/v1/games/matches/${id}/action`,{requestId:randomUUID(),type:'leave',expectedRevision:m.revision});}
async function socket(f,u,t){const ws=new WebSocket(f.base.replace('http','ws')+'/v1/chat/socket'),events=[];ws.on('message',b=>events.push(JSON.parse(b)));t.after(()=>ws.terminate());await once(ws,'open');ws.send(JSON.stringify({type:'authenticate',token:u.token}));await until(()=>events.some(e=>e.type==='chat.ready'));return events;}
async function until(fn){for(let n=0;n<300;n++){if(fn())return;await new Promise(r=>setTimeout(r,10));}assert.fail('Expected realtime event not received');}

test('public search pairs same-game humans for all five games and keeps hands private',async t=>{
 const f=await fixture(t,{gamesAutoTick:false});const a=await f.register('smooth_a'),b=await f.register('smooth_b'),outside=await f.register('smooth_outside');
 for(const kind of kinds){
  const queued=await start(f,a,kind);assert.equal(queued.status,200,JSON.stringify(queued));assert.equal(queued.data.search.status,'searching');
  const matched=await start(f,b,kind);assert.equal(matched.status,200,JSON.stringify(matched));assert.equal(matched.data.search.status,'matched');assert.equal(matched.data.match.status,'playing');assert.equal(matched.data.match.lobbyType,'public');
  const id=matched.data.match.id;const summary=(await f.req(a,'GET','/v1/games')).data;assert.equal(summary.search.matchId,id);
  const own=(await f.req(a,'GET','/v1/games/matches/'+id)).data.match;assert.equal(own.players.filter(p=>!p.bot).length,2);assert.ok(own.players.every(p=>!('hand'in p)&&!('tiles'in p)));
  assert.equal((await f.req(outside,'GET','/v1/games/matches/'+id)).status,403);
  assert.equal((await start(f,a,kind)).data.search.matchId,id);
  await leave(f,a,id);await leave(f,b,id);
 }
});

test('concurrent public searches assign each account to one pair and survive restart',async t=>{
 const f=await fixture(t,{gamesAutoTick:false}),users=[];for(let i=0;i<4;i++)users.push(await f.register('smooth_concurrent_'+i));
 const results=await Promise.all(users.flatMap(u=>[start(f,u,'uno'),start(f,u,'uno')]));assert.ok(results.every(r=>r.status===200),JSON.stringify(results));
 const rows=(await f.db.query('SELECT user_id,match_id FROM tomi_game_players')).rows;assert.equal(rows.length,4);assert.equal(new Set(rows.map(r=>r.user_id)).size,4);assert.equal(new Set(rows.map(r=>r.match_id)).size,2);
 await f.restart();for(const u of users)assert.equal((await f.req(u,'GET','/v1/games')).data.search.status,'matched');
});

test('search excludes blocks/private matches and cancellation does not silently leave a matched table',async t=>{
 const f=await fixture(t,{gamesAutoTick:false}),a=await f.register('smooth_block_a'),b=await f.register('smooth_block_b');
 await f.db.query('INSERT INTO tomi_user_blocks(blocker_id,blocked_id,created_at) VALUES(?,?,?)',[a.user.id,b.user.id,new Date().toISOString()]);
 await start(f,a,'snakes');assert.equal((await start(f,b,'snakes')).data.search.status,'searching');
 assert.equal((await f.req(a,'POST','/v1/games/search/cancel',{kind:'snakes'})).data.search,null);
 await f.db.query('DELETE FROM tomi_user_blocks');const match=await start(f,a,'snakes');assert.equal(match.data.search.status,'matched');
 assert.equal((await f.req(a,'POST','/v1/games/search/cancel',{kind:'snakes'})).data.search.matchId,match.data.match.id);
 assert.equal((await f.req(a,'POST','/v1/games/matches',{requestId:randomUUID(),kind:'snakes',mode:'friends'})).data.error.code,'GAME_ACTIVE');
 await leave(f,a,match.data.match.id);await leave(f,b,match.data.match.id);
 const privateTable=await f.req(a,'POST','/v1/games/matches',{requestId:randomUUID(),kind:'snakes',mode:'friends'});assert.equal(privateTable.status,200);
 assert.equal((await start(f,a,'uno')).data.error.code,'GAME_ACTIVE');
 assert.equal((await start(f,b,'snakes')).data.search.status,'searching');assert.equal((await f.req(a,'GET','/v1/games/matches/'+privateTable.data.match.id)).data.match.players.length,1);
});

test('expired searches are not paired and changing games requires cancelling the old queue',async t=>{
 let now=1000000;const f=await fixture(t,{gamesAutoTick:false,gamesClock:()=>now}),a=await f.register('smooth_expire_a'),b=await f.register('smooth_expire_b');
 await start(f,a,'camel');assert.equal((await start(f,a,'uno')).data.error.code,'GAME_SEARCH_ACTIVE');
 now+=46000;assert.equal((await start(f,b,'camel')).data.search.status,'searching');assert.equal((await f.req(a,'GET','/v1/games')).data.search,null);
 assert.equal((await start(f,a,'camel')).data.search.status,'matched');
});

test('new GIF chat messages arrive as scoped realtime payloads without exposing sender nonces to peers',async t=>{
 const f=await fixture(t),a=await f.register('smooth_chat_a'),b=await f.register('smooth_chat_b'),c=await f.register('smooth_chat_c');
 const ae=await socket(f,a,t),be=await socket(f,b,t),ce=await socket(f,c,t);
 const tid=(await f.req(a,'POST','/v1/chats',{userId:b.user.id})).data.conversation.id;
 const payload={text:'',stickerId:'gif_heart',requestId:randomUUID()},posted=await f.req(a,'POST',`/v1/chats/${tid}/messages`,payload);assert.equal(posted.status,201,JSON.stringify(posted));
 await until(()=>be.some(e=>e.type==='chat.message'&&e.message?.id===posted.data.message.id));
 const peer=be.find(e=>e.message?.id===posted.data.message.id),self=ae.find(e=>e.message?.id===posted.data.message.id);
 assert.equal(peer.message.stickerId,'gif_heart');assert.equal(peer.message.requestId,null);assert.equal(peer.message.isMine,false);assert.equal(self.message.requestId,payload.requestId);assert.equal(self.message.isMine,true);assert.equal(ce.some(e=>e.conversationId===tid),false);
 assert.equal((await f.req(a,'POST',`/v1/chats/${tid}/messages`,payload)).data.message.id,posted.data.message.id);
 assert.equal((await f.req(c,'GET',`/v1/chats/${tid}/messages`)).status,404);
 // A member joining during delivery must not receive a message from before joined_seq.
 const later=await f.register('smooth_chat_late'),late=await socket(f,later,t);
 const created=await f.req(a,'POST','/v1/groups',{title:'GIF privacy',memberIds:[b.user.id,c.user.id],requestId:randomUUID()});assert.equal(created.status,201,JSON.stringify(created));const group=created.data.conversation;
 const query=f.db.query;let entered,release;
 const blocked=new Promise(resolve=>entered=resolve),resume=new Promise(resolve=>release=resolve);
 f.db.query=async(sql,args)=>{if(sql.startsWith('SELECT user_id FROM tomi_group_members WHERE group_id=? AND left_at IS NULL AND joined_seq<?')){entered();await resume;}return query(sql,args);};
 try{
  const sending=f.req(a,'POST',`/v1/groups/${group.id}/messages`,{text:'',stickerId:'gif_wave',requestId:randomUUID()});
  await blocked;assert.equal((await f.req(a,'PUT',`/v1/groups/${group.id}/members`,{memberIds:[later.user.id]})).status,200);release();
  const sent=await sending;assert.equal(sent.status,201);await until(()=>be.some(e=>e.message?.id===sent.data.message.id));
  assert.equal(late.some(e=>e.message?.id===sent.data.message.id),false);
 }finally{release();f.db.query=query;}

});

test('motion events are sequenced and expose the complete authoritative dice path',()=>{
 let s=newGame('snakes',[{seat:0},{seat:1,bot:true}],{draw:()=>0,now:1000});
 s=performGameAction(s,0,{type:'roll'},{draw:()=>1,now:2000});const e=s.history[0];assert.equal(e.sequence,1);assert.deepEqual(e.steps,[1,2]);assert.equal(e.landing,2);assert.equal(e.to,38);assert.equal(e.transport,'ladder');assert.equal(s.deadlineAt,3800);
});

test('free wheel private play is authoritative and cannot debit or credit account coins',async t=>{
 const f=await fixture(t,{gamesAutoTick:false}),a=await f.register('smooth_wheel_a'),b=await f.register('smooth_wheel_b');
 let match=(await f.req(a,'POST','/v1/games/matches',{requestId:randomUUID(),kind:'wheel',mode:'friends'})).data.match;
 await f.req(b,'POST','/v1/games/join',{requestId:randomUUID(),code:match.code});match=(await f.req(a,'GET','/v1/games/matches/'+match.id)).data.match;
 match=(await f.req(a,'POST',`/v1/games/matches/${match.id}/action`,{requestId:randomUUID(),expectedRevision:match.revision,type:'start'})).data.match;
 for(let n=0;n<6;n++){const actor=match.turn===0?a:b,r=await f.req(actor,'POST',`/v1/games/matches/${match.id}/action`,{requestId:randomUUID(),expectedRevision:match.revision,type:'spin'});assert.equal(r.status,200,JSON.stringify(r));match=r.data.match;}
 assert.equal(match.status,'finished');assert.ok(match.result.winnerSeats.length>0);assert.ok(match.players.every(p=>p.spins===3));
 for(const u of [a,b])assert.equal((await f.req(u,'GET','/v1/games')).data.coins,1000);
});
