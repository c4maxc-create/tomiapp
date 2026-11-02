import test from 'node:test';
import assert from 'node:assert/strict';
import {makeDeck,newGame,performGameAction,automaticAction,publicGameState,canPlayCard} from '../src/game_engine.mjs';
import {gameProgress,gameThresholds} from '../src/game_progress.mjs';
const players=[{seat:0},{seat:1},{seat:2},{seat:3}];
function uno(two=false){return newGame('uno',players.slice(0,two?2:4),{now:1000});}
function setup(card,hand=[card],two=false){const s=uno(two);s.players[0].hand=hand;s.discard=[{id:'top',color:'red',value:'5'}];s.activeColor='red';return s;}
const card=(color,value,id=color+'-'+value)=>({id,color,value});

test('1.7 deck has 108 unique cards with the playable colour and action distribution',()=>{
 const deck=makeDeck();assert.equal(deck.length,108);assert.equal(new Set(deck.map(c=>c.id)).size,108);
 for(const color of ['red','yellow','green','blue']){assert.equal(deck.filter(c=>c.color===color).length,25);assert.equal(deck.filter(c=>c.color===color&&c.value==='0').length,1);}
 assert.equal(deck.filter(c=>c.value==='wild4').length,4);
});
test('1.7 dealing conserves all cards and begins on a number',()=>{
 const s=uno();assert.deepEqual(s.players.map(p=>p.hand.length),[7,7,7,7]);assert.equal(s.deck.length,79);assert.match(s.discard[0].value,/^\d$/);assert.equal(s.discard.length,1);
});
test('1.7 out-of-turn and invented card actions leave the authoritative input untouched',()=>{
 const s=uno(),before=structuredClone(s);assert.throws(()=>performGameAction(s,1,{type:'draw'}),e=>e.code==='GAME_TURN');assert.throws(()=>performGameAction(s,0,{type:'play',cardId:'invented'}),e=>e.code==='GAME_CARD');assert.deepEqual(s,before);
});
test('1.7 a draw-four cannot bypass a matching colour in the player hand',()=>{
 const wild=card(null,'wild4','w4'),s=setup(wild,[wild,card('red','7')]);assert.equal(canPlayCard(s,s.players[0],wild),false);assert.throws(()=>performGameAction(s,0,{type:'play',cardId:'w4',color:'blue'}),e=>e.code==='GAME_CARD');
});
test('1.7 wilds require a valid colour and coloured cards reject a forced colour',()=>{
 const wild=card(null,'wild','w'),s=setup(wild,[wild,card('blue','1')]);assert.throws(()=>performGameAction(s,0,{type:'play',cardId:'w'}),e=>e.code==='GAME_COLOR');const next=performGameAction(s,0,{type:'play',cardId:'w',color:'green',uno:true});assert.equal(next.activeColor,'green');
 const red=card('red','2'),r=setup(red);assert.throws(()=>performGameAction(r,0,{type:'play',cardId:red.id,color:'blue'}),e=>e.code==='GAME_COLOR');
});
test('1.7 reverse skips the opponent in a two-player match',()=>{
 const reverse=card('red','reverse'),s=setup(reverse,[reverse,card('blue','3')],true);const next=performGameAction(s,0,{type:'play',cardId:reverse.id,uno:true});assert.equal(next.turn,0);assert.equal(next.direction,-1);
});
test('1.7 draw-two charges the next hand and skips that player without stacking',()=>{
 const draw2=card('red','draw2'),s=setup(draw2,[draw2,card('green','2')]);const before=s.players[1].hand.length;const next=performGameAction(s,0,{type:'play',cardId:draw2.id,uno:true});assert.equal(next.players[1].hand.length,before+2);assert.equal(next.turn,2);
});
test('1.7 drawing permits only the newly drawn playable card or passing',()=>{
 const red=card('red','3'),s=setup(red,[red,card('blue','7')]);s.deck=[card('red','9','drawn')];const drawn=performGameAction(s,0,{type:'draw'});assert.equal(drawn.turn,0);assert.equal(drawn.drawnId,'drawn');assert.throws(()=>performGameAction(drawn,0,{type:'play',cardId:red.id}),e=>e.code==='GAME_CARD');assert.throws(()=>performGameAction(drawn,0,{type:'draw'}),e=>e.code==='GAME_DRAW');assert.equal(performGameAction(drawn,0,{type:'pass'}).turn,1);
});
test('1.7 forgetting UNO applies the displayed two-card rule and prevents a false one-card state',()=>{
 const red=card('red','2'),s=setup(red,[red,card('blue','7')]);const next=performGameAction(s,0,{type:'play',cardId:red.id});assert.equal(next.players[0].hand.length,3);assert.equal(next.history[0].unoPenalty,2);
});
test('1.7 recycling keeps the top discard and never copies another player cards',()=>{
 const s=uno();s.deck=[];const top=s.discard[0];s.discard=[card('blue','1','recycle'),top];const next=performGameAction(s,0,{type:'draw'});assert.equal(next.discard.at(-1).id,top.id);assert.ok(next.players[0].hand.some(c=>c.id==='recycle'));assert.deepEqual(next.players[1].hand,s.players[1].hand);
});
test('1.7 the public table never exposes the draw pile or another private hand',()=>{
 const s=uno(),view=publicGameState(s,0),privateId=s.players[1].hand[0].id;assert.equal(view.hand.length,7);assert.ok(!('deck' in view));assert.ok(!('discard' in view));assert.ok(view.players.every(p=>!('hand' in p)));assert.ok(!JSON.stringify(view).includes('"'+privateId+'"'));
});
test('1.7 a ladder and snake move from their board square to the configured endpoint',()=>{
 const s=newGame('snakes',players.slice(0,2),{now:0});const ladder=performGameAction(s,0,{type:'roll'},{draw:()=>1});assert.equal(ladder.players[0].position,38);assert.deepEqual(ladder.lastMove.steps,[1,2]);assert.equal(ladder.lastMove.transport,'ladder');s.players[0].position=15;const snake=performGameAction(s,0,{type:'roll'},{draw:()=>0});assert.equal(snake.players[0].position,6);assert.equal(snake.lastMove.transport,'snake');
});
test('1.7 exact finish, overshoot and the extra six turn are enforced on the server',()=>{
 const s=newGame('snakes',players.slice(0,2),{now:0});s.players[0].position=99;const over=performGameAction(s,0,{type:'roll'},{draw:()=>1});assert.equal(over.players[0].position,99);assert.equal(over.turn,1);s.players[0].position=0;assert.equal(performGameAction(s,0,{type:'roll'},{draw:()=>5}).turn,0);s.players[0].position=94;const win=performGameAction(s,0,{type:'roll'},{draw:()=>5,now:5000});assert.equal(win.status,'finished');assert.equal(win.result.winnerSeat,0);
});
test('1.7 full legal card matches finish while conserving every card across reshuffles',()=>{
 for(let round=0;round<4;round++){
  let s=uno(),n=0;
  while(s.status==='playing'&&n++<2500){s=performGameAction(s,s.turn,automaticAction(s),{now:n*1000,automatic:true});const all=[...s.deck,...s.discard,...s.players.flatMap(p=>p.hand)];assert.equal(all.length,108);assert.equal(new Set(all.map(c=>c.id)).size,108);}
  assert.equal(s.status,'finished');assert.equal(s.players.find(p=>p.seat===s.result.winnerSeat).hand.length,0);assert.ok(s.players.every(p=>p.humanMoves===0));
 }
});
test('1.7 full snakes matches reach square 100 without leaving the board',()=>{
 let s=newGame('snakes',players,{now:0}),n=0;
 while(s.status==='playing'&&n++<5000){s=performGameAction(s,s.turn,{type:'roll'},{now:n*1000,automatic:true});assert.ok(s.players.every(p=>p.position>=0&&p.position<=100));}
 assert.equal(s.status,'finished');assert.equal(s.players.find(p=>p.seat===s.result.winnerSeat).position,100);
});
test('1.7 game-level boundaries are separate and capped at level fifty',()=>{
 assert.equal(gameProgress(-10).level,1);assert.equal(gameProgress(99).level,1);assert.equal(gameProgress(100).level,2);assert.equal(gameProgress(100).remaining,300);assert.equal(gameProgress(240100).level,50);assert.equal(gameProgress(240100).next,null);assert.equal(gameThresholds.length,50);
});
