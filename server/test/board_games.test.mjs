import test from 'node:test';
import assert from 'node:assert/strict';
import {newGame,performGameAction,automaticAction,publicGameState} from '../src/game_engine.mjs';
import {jackChoices,camelChoices,freeTile} from '../src/board_games.mjs';
const players=[0,1,2,3].map(seat=>({seat})),opts={now:1000,draw:n=>n-1};
const game=kind=>newGame(kind,kind==='camel'?players.slice(0,3):players,opts);
const choose=(s,seat,id)=>performGameAction(s,seat,{type:'choose',choice:id},{...opts,now:2000});
const card=(value,id='test-'+value)=>({id,value,suit:'clubs'});
function jack(rank,pawns=[1,-1,-1,-1]){const s=game('jackaroo');s.players[0].hand=[card(rank)];s.players[0].pawns=pawns;return s;}

test('board games keep four jackaroo seats, three co-op boards, unique cards and private hands',()=>{
 const s=newGame('jackaroo',players.slice(0,2),opts);assert.equal(s.players.length,4);assert.equal(s.players[2].bot,true);
 assert.equal(new Set([...s.deck,...s.players.flatMap(p=>p.hand)].map(c=>c.id)).size,52);
 const own=publicGameState(s,0);assert.equal(own.hand.length,4);assert.ok(own.players.every(p=>!('hand'in p)));assert.ok(!('deck'in own));
 const c=game('camel'),view=publicGameState(c,0);assert.equal(view.tiles.length,54);assert.ok(view.players.every(p=>!('tiles'in p)));assert.equal(c.players[1].tiles.length,54);
});
test('jackaroo entry uses A or K, cannot invent moves, and leaves input unchanged on rejection',()=>{
 const s=jack('A',[-1,-1,-1,-1]),c=jackChoices(s,0).find(c=>c.enter);assert.ok(c);
 const next=choose(s,0,c.id);assert.equal(next.players[0].pawns[0],0);assert.deepEqual(s.players[0].pawns,[-1,-1,-1,-1]);
 assert.throws(()=>choose(s,0,'invented'),e=>e.code==='GAME_CHOICE');assert.throws(()=>choose(s,1,c.id),e=>e.code==='GAME_TURN');
});
test('jackaroo protected starts block passing, capture sends opponents home, and own landing is forbidden',()=>{
 const s=jack('2',[14,-1,-1,-1]);s.players[1].pawns=[0,-1,-1,-1];assert.equal(jackChoices(s,0).every(c=>c.discard),true);
 s.players[1].pawns=[1,-1,-1,-1];s.players[0].pawns=[15,-1,-1,-1];const c=jackChoices(s,0).find(x=>!x.discard);assert.ok(c);assert.equal(choose(s,0,c.id).players[1].pawns[0],-1);
 s.players[0].pawns=[15,17,-1,-1];assert.ok(jackChoices(s,0).every(x=>x.discard||x.steps[0].pawn!==0));
});
test('jackaroo supports backwards four and split seven without overshooting home',()=>{
 const s=jack('4',[0,-1,-1,-1]),c=jackChoices(s,0).find(x=>!x.discard);assert.equal(choose(s,0,c.id).players[0].pawns[0],60);
 const split=jack('7',[5,20,-1,-1]),move=jackChoices(split,0).find(x=>x.steps?.length===2&&x.steps[0].steps===3);
 assert.ok(move);const next=choose(split,0,move.id);assert.deepEqual(next.players[0].pawns,[8,24,-1,-1]);
 const home=jack('2',[66,64,65,67]);assert.ok(jackChoices(home,0).every(x=>x.discard));
});
test('jackaroo jack swaps unprotected stones and a finished player controls partner',()=>{
 const s=jack('J',[3,-1,-1,-1]);s.players[1].pawns=[4,-1,-1,-1];const c=jackChoices(s,0).find(x=>x.swap?.seat===1&&x.swap.pawn===0);
 const next=choose(s,0,c.id);assert.equal(next.players[0].pawns[0],20);assert.equal(next.players[1].pawns[0],51);
 const partner=jack('A',[64,65,66,67]),v=publicGameState(partner,0);assert.equal(v.controlledSeat,2);const out=jackChoices(partner,0).find(x=>x.enter);assert.equal(choose(partner,0,out.id).players[2].pawns[0],0);
});
test('jackaroo team victory requires all eight stones and private state is not in history',()=>{
 const s=jack('A',[63,64,65,66]);s.players[2].pawns=[64,65,66,67];
 // Slot64 is occupied, so move the leading stone in the home stretch instead.
 s.players[0].pawns=[66,64,65,62];s.players[0].hand=[card('A')];const first=jackChoices(s,0).find(x=>x.steps?.[0].pawn===0&&x.steps[0].steps===1);assert.ok(first);
 const n=choose(s,0,first.id);assert.equal(n.status,'playing');assert.ok(n.history.every(e=>!('hand'in e)));
 s.players[0].pawns=[63,65,66,67];const win=jackChoices(s,0).find(x=>x.steps?.[0].pawn===0&&x.steps[0].steps===1);const done=choose(s,0,win.id);assert.equal(done.status,'finished');assert.deepEqual(done.result.winnerSeats,[0,2]);
});
test('camel blocks covered tiles and three equal tiles clear before the seven-slot loss check',()=>{
 const s=game('camel'),p=s.players[0],blocked=p.tiles.find(t=>!freeTile(p,t));assert.ok(blocked);assert.throws(()=>choose(s,0,blocked.id),e=>e.code==='GAME_CHOICE');
 p.tiles=[{id:'free',x:0,y:0,z:0,kind:2}];p.tray=[{id:'a',kind:2},{id:'b',kind:2},...Array.from({length:4},(_,i)=>({id:'x'+i,kind:i+3}))];
 const n=choose(s,0,'free');assert.equal(n.players[0].tray.length,4);assert.equal(n.players[0].cleared,3);assert.equal(n.status,'playing');
});
test('camel accepts cooperative out-of-turn picks but never another member tile or a full tray',()=>{
 const s=game('camel'),c=camelChoices(s,1).find(x=>x.type==='tile');const coop=choose(s,1,c.id);assert.equal(coop.players[1].tray.length,1);assert.equal(coop.turn,s.turn);assert.equal(coop.deadlineAt,s.deadlineAt);
 assert.throws(()=>choose(s,0,c.id),e=>e.code==='GAME_CHOICE');
 const p=s.players[0];p.tiles=[{id:'last',x:0,y:0,z:0,kind:8}];p.tray=Array.from({length:6},(_,i)=>({id:'t'+i,kind:i}));const n=choose(s,0,'last');assert.equal(n.status,'finished');assert.deepEqual(n.result.winnerSeats,[]);assert.equal(n.result.reason,'tray_full');
});
test('camel undo and side storage conserve tiles and consume server-owned tools once',()=>{
 const s=game('camel'),c=camelChoices(s,0).find(x=>x.type==='tile'),picked=choose(s,0,c.id),undone=choose(picked,0,'tool:undo');assert.equal(undone.players[0].tiles.length,54);assert.equal(undone.players[0].tools.undo,0);
 assert.throws(()=>choose(undone,0,'tool:undo'),e=>e.code==='GAME_CHOICE');
 const next=choose(picked,0,'tool:remove');assert.equal(next.players[0].side.length,1);assert.equal(next.players[0].tray.length,0);const side=choose(next,0,'side:'+c.id);assert.equal(side.players[0].tray.length,1);assert.equal(side.players[0].side.length,0);
});
test('camel orders award bounded team tools, shuffle conserves types, and automatic play cannot earn human moves',()=>{
 const s=game('camel'),p=s.players[0];p.tiles=[{id:'last',x:0,y:0,z:0,kind:0}];p.tray=[{id:'a',kind:0},{id:'b',kind:0}];s.orders.count=1;
 const n=choose(s,0,'last');assert.equal(n.orders.completed,1);assert.ok(n.players.every(p=>p.tools.shuffle===2));
 const full=game('camel'),before=full.players[0].tiles.map(t=>t.kind).sort();const shuffled=choose(full,0,'tool:shuffle');assert.deepEqual(shuffled.players[0].tiles.map(t=>t.kind).sort(),before);
 const auto=performGameAction(full,full.turn,automaticAction(full),{...opts,automatic:true});assert.equal(auto.players[0].humanMoves,0);
 let bots=newGame('camel',players.slice(0,3).map(p=>({...p,bot:true})),opts),moves=0;
 while(bots.status==='playing'&&moves<200)bots=performGameAction(bots,bots.turn,automaticAction(bots),{...opts,now:++moves*1000,automatic:true});
 assert.equal(bots.result.reason,'team_clear');assert.ok(bots.players.every(p=>p.humanMoves===0));assert.ok(publicGameState(bots,0).players.every(p=>!('solution'in p)));
});
