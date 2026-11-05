import {newFreeWheel,spinFreeWheel,publicFreeWheel} from './free_wheel.mjs';
import {newBoardGame,performBoardAction,automaticBoardAction,publicBoardState} from './board_games.mjs';
import {randomInt} from 'node:crypto';
import {ApiError} from './security.mjs';

export const cardColors = Object.freeze(['red', 'yellow', 'green', 'blue']);
export const ladders = Object.freeze({2:38,7:14,8:31,15:26,21:42,28:84,36:44,51:67,71:91,78:98,87:94});
export const snakes = Object.freeze({16:6,46:25,49:11,62:19,64:60,74:53,89:68,92:88,95:75,99:80});
const fail = (code, message) => { throw new ApiError(409, code, message); };
const copy = value => structuredClone(value);
const number = card => /^\d$/.test(card.value);

export function makeDeck() {
  const cards = [];
  for (const color of cardColors) {
    cards.push({id:`${color}-0`, color, value:'0'});
    for (const value of ['1','2','3','4','5','6','7','8','9','skip','reverse','draw2']) {
      for (let n=0;n<2;n++) cards.push({id:`${color}-${value}-${n}`,color,value});
    }
  }
  for (const value of ['wild','wild4']) for (let n=0;n<4;n++) cards.push({id:`${value}-${n}`,color:null,value});
  return cards;
}

function shuffle(cards, draw) {
  for (let n=cards.length-1;n>0;n--) {
    const index=draw(n+1);
    [cards[n],cards[index]]=[cards[index],cards[n]];
  }
  return cards;
}

function next(s, count=1) {
  const at=s.players.findIndex(p=>p.seat===s.turn);
  s.turn=s.players[(at+count*s.direction+s.players.length*8)%s.players.length].seat;
  s.drawnId=null;
}

function take(s, player, count, draw) {
  let total=0;
  for (let i=0;i<count;i++) {
    if (!s.deck.length && s.discard.length>1) {
      const top=s.discard.pop();
      s.deck=shuffle(s.discard,draw);s.discard=[top];
    }
    if (!s.deck.length) break;
    player.hand.push(s.deck.pop());total++;
  }
  return total;
}

export function canPlayCard(s, player, card) {
  if (s.drawnId && s.drawnId!==card.id) return false;
  if (card.value==='wild4') return !player.hand.some(c=>c.color===s.activeColor);
  return card.color===null || card.color===s.activeColor || card.value===s.discard.at(-1).value;
}

export function newGame(kind, players, {draw=randomInt, now=Date.now()}={}) {
  if(kind==='wheel'){if(players.length<2||players.length>4||new Set(players.map(p=>p.seat)).size!==players.length)throw Error('Invalid wheel setup');return newFreeWheel(players,now);}
  if (['jackaroo','camel'].includes(kind)) return newBoardGame(kind,players,{draw,now});
  if (!['uno','snakes'].includes(kind) || players.length<2 || players.length>4 || new Set(players.map(p=>p.seat)).size!==players.length) throw Error('Invalid game setup');
  const s={kind,status:'playing',players:players.map(p=>({seat:p.seat,bot:!!p.bot,hand:[],position:0,moves:0,humanMoves:0})),turn:players[0].seat,direction:1,sequence:0,startedAt:now,updatedAt:now,deadlineAt:now+30000,drawnId:null,history:[],result:null};
  if (kind==='uno') {
    s.deck=shuffle(makeDeck(),draw);s.discard=[];
    for (let i=0;i<7;i++) for (const p of s.players) p.hand.push(s.deck.pop());
    let card=s.deck.pop();
    while (!number(card)) {s.deck.unshift(card);card=s.deck.pop();}
    s.discard.push(card);s.activeColor=card.color;
  }
  return s;
}

function finish(s, player, now) {
  s.status='finished';
  s.result={winnerSeat:player.seat,finishedAt:now,turns:s.sequence+1};
}

export function automaticAction(s) {
  if (['jackaroo','camel'].includes(s.kind)) return automaticBoardAction(s);
  if(s.kind==='wheel')return {type:'spin'};
  if (s.kind==='snakes') return {type:'roll'};
  const player=s.players.find(p=>p.seat===s.turn);
  const card=player.hand.find(c=>canPlayCard(s,player,c));
  if (!card) return {type:s.drawnId?'pass':'draw'};
  const color=cardColors.map(color=>({color,n:player.hand.filter(c=>c.color===color).length})).sort((a,b)=>b.n-a.n)[0].color;
  return {type:'play',cardId:card.id,...(card.color===null?{color}:{}),uno:true};
}

export function performGameAction(original, seat, action, {draw=randomInt,now=Date.now(),automatic=false}={}) {
  if(original.kind==='wheel')return spinFreeWheel(original,seat,action,{draw,now,automatic});
  if (['jackaroo','camel'].includes(original.kind)) return performBoardAction(original,seat,action,{draw,now,automatic});
  const s=copy(original),player=s.players.find(p=>p.seat===seat);
  if (s.status!=='playing') fail('GAME_ENDED','انتهت هذه الجولة.');
  if (!player || s.turn!==seat) fail('GAME_TURN','انتظر دورك.');
  const event={seat,type:action.type,automatic,at:now};
  if (s.kind==='snakes') {
    if (action.type!=='roll') fail('GAME_ACTION','اضغط رمي النرد في دورك.');
    const dice=draw(6)+1,from=player.position,landing=from+dice;
    const steps=landing<=100?Array.from({length:dice},(_,i)=>from+i+1):[];
    const to=landing>100?from:(ladders[landing]??snakes[landing]??landing);
    player.position=to;
    Object.assign(event,{dice,from,landing:landing>100?from:landing,to,steps,transport:ladders[landing]?'ladder':snakes[landing]?'snake':null,overshoot:landing>100});
    s.lastMove=event;
    if (to===100) finish(s,player,now);
    else if (dice!==6) next(s);
  } else if (action.type==='draw') {
    if (s.drawnId) fail('GAME_DRAW','سحبت ورقة بالفعل؛ العبها أو مرّر الدور.');
    const count=take(s,player,1,draw);
    event.count=count;
    const card=count?player.hand.at(-1):null;
    if (card && canPlayCard(s,player,card)) s.drawnId=card.id;
    else next(s);
  } else if (action.type==='pass') {
    if (!s.drawnId) fail('GAME_ACTION','اسحب ورقة أولًا أو العب ورقة صالحة.');
    next(s);
  } else if (action.type==='play') {
    const card=player.hand.find(c=>c.id===action.cardId);
    if (!card || !canPlayCard(s,player,card)) fail('GAME_CARD','هذه الورقة غير صالحة الآن.');
    if (card.color===null && !cardColors.includes(action.color)) fail('GAME_COLOR','اختَر اللون التالي.');
    if (card.color!==null && action.color!==undefined) fail('GAME_COLOR','الورقة الملونة لا تحتاج اختيار لون.');
    player.hand=player.hand.filter(c=>c.id!==card.id);
    s.discard.push(card);s.activeColor=card.color??action.color;
    event.card=card;event.color=s.activeColor;
    if (player.hand.length===1) {
      event.uno=action.uno===true;
      if (!event.uno) event.unoPenalty=take(s,player,2,draw);
    }
    if (card.value==='reverse') {
      s.direction*=-1;
      next(s,s.players.length===2?2:1);
    } else if (card.value==='skip') next(s,2);
    else if (card.value==='draw2'||card.value==='wild4') {
      next(s);const target=s.players.find(p=>p.seat===s.turn);
      event.penaltySeat=target.seat;event.penalty=take(s,target,card.value==='draw2'?2:4,draw);next(s);
    } else next(s);
    if (!player.hand.length) finish(s,player,now);
  } else fail('GAME_ACTION','الخطوة غير متاحة في هذه اللعبة.');
  player.moves++;
  if (!automatic && !player.bot) player.humanMoves++;
  event.sequence=s.sequence+1;
  s.sequence++;s.updatedAt=now;
  s.history=[event,...s.history].slice(0,32);
  const active=s.players.find(p=>p.seat===s.turn);
  s.deadlineAt=now+(active?.bot?(s.kind==='snakes'?1800:1200):30000);
  return s;
}

export function publicGameState(s, seat) {
  if(s.kind==='wheel')return publicFreeWheel(s);
  if (['jackaroo','camel'].includes(s.kind)) return publicBoardState(s,seat);
  const me=s.players.find(p=>p.seat===seat);
  return {
    kind:s.kind,status:s.status,turn:s.turn,direction:s.direction,sequence:s.sequence,
    startedAt:s.startedAt,deadlineAt:s.deadlineAt,result:s.result,history:s.history,
    players:s.players.map(p=>({seat:p.seat,bot:p.bot,position:p.position,cardCount:p.hand.length})),
    hand:s.kind==='uno'?(me?.hand??[]):[],
    playableCardIds:s.kind==='uno'&&s.status==='playing'&&s.turn===seat?me.hand.filter(c=>canPlayCard(s,me,c)).map(c=>c.id):[],
    canPass:s.status==='playing'&&s.kind==='uno'&&s.turn===seat&&s.drawnId!==null,
    canDraw:s.status==='playing'&&s.kind==='uno'&&s.turn===seat&&s.drawnId===null,
    topCard:s.kind==='uno'?s.discard.at(-1):null,activeColor:s.activeColor??null,
    deckCount:s.deck?.length??0,lastMove:s.lastMove??null,
    ladders: s.kind==='snakes'?ladders:null,snakes:s.kind==='snakes'?snakes:null,
  };
}
