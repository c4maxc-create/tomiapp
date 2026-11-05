import {randomInt,createHash} from 'node:crypto';
import {ApiError} from './security.mjs';
const reject=(code,message)=>{throw new ApiError(409,code,message);};
const clone=x=>structuredClone(x);
const key=x=>createHash('sha256').update(JSON.stringify(x)).digest('hex').slice(0,32);
function shuffle(a,draw){for(let i=a.length-1;i>0;i--){const j=draw(i+1);[a[i],a[j]]=[a[j],a[i]];}return a;}
const ranks=['A','2','3','4','5','6','7','8','9','10','J','Q','K'];
function dealJack(s,draw){
 const n=s.players.length*4;
 if(s.deck.length<n){s.deck.push(...s.discard);s.discard=[];shuffle(s.deck,draw);}
 for(const p of s.players)p.hand=s.deck.splice(-4);
 s.round++;
}
export function newBoardGame(kind,players,{draw=randomInt,now=Date.now()}={}){
 if(!['jackaroo','camel'].includes(kind)||players.length<2||players.length>(kind==='camel'?3:4)||new Set(players.map(p=>p.seat)).size!==players.length)throw Error('Invalid board game setup');
 const seats=players.map(p=>({...p}));
 if(kind==='jackaroo')for(let i=0;i<4;i++)if(!seats.some(p=>p.seat===i))seats.push({seat:i,bot:true});
 seats.sort((a,b)=>a.seat-b.seat);
 const s={kind,status:'playing',players:seats.map(p=>({seat:p.seat,bot:!!p.bot,moves:0,humanMoves:0,hand:[],pawns:[-1,-1,-1,-1]})),turn:seats[0].seat,sequence:0,startedAt:now,deadlineAt:now+30000,history:[],result:null};
 if(kind==='jackaroo'){
  s.deck=shuffle(ranks.flatMap(value=>['clubs','diamonds','hearts','spades'].map(suit=>({id:suit+'-'+value,value,suit}))),draw);s.discard=[];s.round=0;dealJack(s,draw);
 }else{
  s.orders={kind:0,count:0,required:2,completed:0};
  for(const p of s.players){const board=makeTiles(p.seat,draw);p.tiles=board.tiles;p.solution=board.solution;p.tray=[];p.side=[];p.tools={remove:1,undo:1,shuffle:1};p.lastPick=null;p.cleared=0;}
 }
 return s;
}
const globalCell=(seat,pos)=>(seat*16+pos)%64;
function pawnAt(s,cell){for(const p of s.players)for(let i=0;i<4;i++)if(p.pawns[i]>=0&&p.pawns[i]<64&&globalCell(p.seat,p.pawns[i])===cell)return {p,i};return null;}
function controlled(s,seat){const own=s.players.find(p=>p.seat===seat);return own.pawns.every(x=>x>=64)?s.players.find(p=>p.seat===(seat+2)%4):own;}
function movePawn(s,owner,index,steps,enter=false,sweep=false){
 const p=s.players.find(p=>p.seat===owner),from=p.pawns[index];
 if(enter){
  if(from!==-1)return false;
  const at=pawnAt(s,globalCell(owner,0));if(at&&(at.p.seat===owner||at.p.pawns[at.i]===0))return false;
  if(at)at.p.pawns[at.i]=-1;p.pawns[index]=0;return true;
 }
 if(from<0||from>=64&&steps<0)return false;
 const dest=steps<0?(from+steps+64)%64:from+steps;
 if(dest>67)return false;
 for(let n=1;n<=Math.abs(steps);n++){
  const pos=steps<0?(from-n+64)%64:from+n;
  if(pos>=64){if(p.pawns.some((x,i)=>i!==index&&x===pos))return false;continue;}
  const at=pawnAt(s,globalCell(owner,pos));if(!at||at.p===p&&at.i===index)continue;
  if(at.p.pawns[at.i]===0)return false;
  if(at.p.seat===owner){if(n===Math.abs(steps))return false;}
  else if(sweep||n===Math.abs(steps))at.p.pawns[at.i]=-1;
 }
 p.pawns[index]=dest;return true;
}
function executeJack(s,seat,plan){
 const own=controlled(s,seat);if(!own)return false;
 if(plan.swap){
  const a=own,b=s.players.find(p=>p.seat===plan.swap.seat),i=plan.pawn,j=plan.swap.pawn;
  if(!b||a===b&&i===j||a.pawns[i]<=0||a.pawns[i]>=64||b.pawns[j]<=0||b.pawns[j]>=64)return false;
  const ca=globalCell(a.seat,a.pawns[i]),cb=globalCell(b.seat,b.pawns[j]);a.pawns[i]=(cb-a.seat*16+64)%64;b.pawns[j]=(ca-b.seat*16+64)%64;return true;
 }
 for(const step of plan.steps)if(!movePawn(s,own.seat,step.pawn,step.steps,plan.enter,plan.sweep))return false;
 return true;
}
export function jackChoices(s,seat){
 if(s.status!=='playing'||s.turn!==seat)return [];
 const p=s.players.find(p=>p.seat===seat),owner=controlled(s,seat),choices=[];
 const add=(card,plan,label)=>{const copy=clone(s);if(executeJack(copy,seat,plan))choices.push({id:key([card.id,plan]),cardId:card.id,label,...plan});};
 for(const card of p.hand){
  if(card.value==='J'){
   for(let a=0;a<4;a++)for(const b of s.players)for(let n=0;n<4;n++)add(card,{pawn:a,swap:{seat:b.seat,pawn:n}},`J • تبديل حجر ${a+1} مع لاعب ${b.seat+1} حجر ${n+1}`);
  }else if(card.value==='7'){
   // All 120 allocations of seven steps; ascending pawn order is the published TOMI split rule.
   for(let a=0;a<=7;a++)for(let b=0;b<=7-a;b++)for(let c=0;c<=7-a-b;c++){
    const counts=[a,b,c,7-a-b-c],steps=counts.flatMap((n,pawn)=>n?[{pawn,steps:n}]:[]);
    add(card,{steps},'7 • '+steps.map(x=>`حجر ${x.pawn+1}: ${x.steps}`).join(' / '));
   }
  }else{
   const values=card.value==='A'?[1,11]:card.value==='4'?[-4]:[card.value==='Q'?12:card.value==='K'?13:Number(card.value)];
   for(let pawn=0;pawn<4;pawn++){
    if(card.value==='A'||card.value==='K')add(card,{steps:[{pawn,steps:0}],enter:true},`${card.value} • إخراج حجر ${pawn+1}`);
    for(const steps of values)add(card,{steps:[{pawn,steps}],sweep:card.value==='K'},`${card.value} • حجر ${pawn+1} ${steps<0?'للخلف':'للأمام'} ${Math.abs(steps)}`);
   }
  }
 }
 // Discard only when the entire hand has no legal action.
 if(!choices.length)for(const card of p.hand)choices.push({id:key(['discard',card.id]),cardId:card.id,discard:true,label:`تخلّص من ${card.value} • لا حركة متاحة`});
 return choices;
}
function covered(a,b){return b.z>a.z&&Math.abs(a.x-b.x)<2&&Math.abs(a.y-b.y)<2;}
export function freeTile(p,t){return p.tiles.some(x=>x.id===t.id)&&!p.tiles.some(x=>covered(t,x));}
function makeTiles(seat,draw){
 const tiles=[];for(let z=0;z<3;z++){const cols=z===2?4:6,rows=z===0?4:3;for(let y=0;y<rows;y++)for(let x=0;x<cols;x++)tiles.push({id:`${seat}-${tiles.length}`,x:2*x+z,y:2*y+z,z,kind:0});}
 // Assign types in a removable topological order, in triples: every new board has a solution.
 const remaining=[...tiles],solution=[];let n=0;while(remaining.length){const free=remaining.filter(t=>!remaining.some(b=>covered(t,b))),tile=free[draw(free.length)];tile.kind=Math.floor(n++/3)%9;solution.push(tile.id);remaining.splice(remaining.indexOf(tile),1);}
 return {tiles,solution};
}
export function camelChoices(s,seat){
 const p=s.players.find(p=>p.seat===seat);if(!p||s.status!=='playing')return [];
 const choices=p.tiles.filter(t=>freeTile(p,t)).map(t=>({id:t.id,type:'tile',kind:t.kind}));
 for(const t of p.side)choices.push({id:'side:'+t.id,type:'side',kind:t.kind});
 if(p.tools.remove>0&&p.tray.length&&p.side.length<=0)choices.push({id:'tool:remove',type:'remove'});
 if(p.tools.undo>0&&p.lastPick&&p.tray.some(t=>t.id===p.lastPick.id))choices.push({id:'tool:undo',type:'undo'});
 if(p.tools.shuffle>0&&p.tiles.length>1)choices.push({id:'tool:shuffle',type:'shuffle'});
 return choices;
}
function pickCamel(s,p,choice,draw){
 if(choice.type==='remove'){p.side.push(...p.tray.splice(0,3));p.tools.remove--;p.lastPick=null;return;}
 if(choice.type==='undo'){const old=p.lastPick;p.tray=p.tray.filter(t=>t.id!==old.id);if(old.source==='side')p.side.push(old.tile);else p.tiles.push(old.tile);p.tools.undo--;p.lastPick=null;return;}
 if(choice.type==='shuffle'){const kinds=shuffle(p.tiles.map(t=>t.kind),draw);p.tiles.forEach((t,i)=>t.kind=kinds[i]);p.tools.shuffle--;p.lastPick=null;return;}
 const source=choice.type==='side'?p.side:p.tiles,id=choice.id.replace(/^side:/,''),i=source.findIndex(t=>t.id===id),tile=source.splice(i,1)[0];
 p.tray.push(tile);p.lastPick={id:tile.id,tile,source:choice.type};
 const same=p.tray.filter(t=>t.kind===tile.kind);
 if(same.length>=3){const ids=new Set(same.slice(0,3).map(t=>t.id));p.tray=p.tray.filter(t=>!ids.has(t.id));p.cleared+=3;p.lastPick=null;
  if(tile.kind===s.orders.kind){s.orders.count++;if(s.orders.count>=s.orders.required){s.orders.completed++;s.orders.kind=(s.orders.kind+1)%9;s.orders.count=0;for(const member of s.players)member.tools.shuffle=Math.min(2,member.tools.shuffle+1);}}
 }
 if(p.tray.length>=7){s.status='finished';s.result={winnerSeat:null,winnerSeats:[],lostSeat:p.seat,reason:'tray_full'};}
 else if(s.players.every(x=>!x.tiles.length&&!x.tray.length&&!x.side.length)){s.status='finished';s.result={winnerSeat:s.players[0].seat,winnerSeats:s.players.map(p=>p.seat),reason:'team_clear'};}
}
export function performBoardAction(original,seat,action,{draw=randomInt,now=Date.now(),automatic=false}={}){
 const s=clone(original),p=s.players.find(p=>p.seat===seat);
 if(s.status!=='playing')reject('GAME_ENDED','انتهت الجولة.');
 if(!p||s.kind==='jackaroo'&&s.turn!==seat)reject('GAME_TURN','انتظر دورك.');
 if(action.type!=='choose'||typeof action.choice!=='string')reject('GAME_ACTION','اختَر حركة من الطاولة.');
 const options=s.kind==='jackaroo'?jackChoices(s,seat):camelChoices(s,seat),choice=options.find(x=>x.id===action.choice);
 if(!choice)reject('GAME_CHOICE','هذه الحركة غير متاحة؛ حدّث الطاولة.');
 if(s.kind==='jackaroo'){
  if(!choice.discard&&!executeJack(s,seat,choice))reject('GAME_CHOICE','الحجر محمي أو المسار مغلق.');
  const index=p.hand.findIndex(c=>c.id===choice.cardId);s.discard.push(...p.hand.splice(index,1));
  const winner=s.players.find(a=>a.pawns.every(x=>x>=64)&&s.players.find(b=>b.seat===(a.seat+2)%4).pawns.every(x=>x>=64));
  if(winner){s.status='finished';s.result={winnerSeat:winner.seat,winnerSeats:[winner.seat,(winner.seat+2)%4],reason:'team_home'};}
  if(s.status==='playing'&&s.players.every(x=>!x.hand.length))dealJack(s,draw);
 }else pickCamel(s,p,choice,draw);
 p.moves++;if(!automatic&&!p.bot)p.humanMoves++;
 const movements=s.kind==='jackaroo'?s.players.flatMap(a=>a.pawns.flatMap((to,pawn)=>{const from=original.players.find(b=>b.seat===a.seat).pawns[pawn];return from===to?[]:[{seat:a.seat,pawn,from,to,delta:choice.steps?.filter(x=>x.pawn===pawn).reduce((n,x)=>n+x.steps,0)??null}];})):[];
 s.sequence++;s.history=[{sequence:s.sequence,movements,seat,type:'choose',at:now,automatic,...(s.kind==='jackaroo'?{card:s.discard.at(-1),label:choice.label}:{kind:choice.kind??null,tool:choice.type})},...s.history].slice(0,32);
 // Skip exhausted hands/boards. The co-op game accepts human actions independently of this sweep cursor.
 const active=s.players.filter(x=>s.kind==='jackaroo'?x.hand.length:x.tiles.length||x.tray.length||x.side.length);
 if(active.length){const seats=s.players.map(x=>x.seat),index=seats.indexOf(seat);for(let n=1;n<=seats.length;n++){const next=seats[(index+n)%seats.length];if(active.some(x=>x.seat===next)){s.turn=next;break;}}}
 if(s.kind==='camel'&&!automatic&&original.turn!==seat&&active.some(x=>x.seat===original.turn)){s.turn=original.turn;s.deadlineAt=original.deadlineAt;}
 else s.deadlineAt=now+(s.players.find(x=>x.seat===s.turn)?.bot?(s.kind==='jackaroo'?1600:1200):30000);return s;
}
export function automaticBoardAction(s){
 const options=s.kind==='jackaroo'?jackChoices(s,s.turn):camelChoices(s,s.turn);
 if(s.kind==='camel'){
  const p=s.players.find(x=>x.seat===s.turn),tiles=options.filter(x=>x.type==='tile'||x.type==='side');
  tiles.sort((a,b)=>p.tray.filter(t=>t.kind===b.kind).length-p.tray.filter(t=>t.kind===a.kind).length);
  if(p.bot&&p.solution)tiles.sort((a,b)=>p.solution.indexOf(a.id.replace(/^side:/,''))-p.solution.indexOf(b.id.replace(/^side:/,'')));
  if(p.tray.length>=5){const rescue=options.find(x=>x.type==='remove');if(rescue)return {type:'choose',choice:rescue.id};}
  if(tiles.length)return {type:'choose',choice:tiles[0].id};
 }
 return {type:'choose',choice:options[0]?.id??''};
}
export function publicBoardState(s,seat){
 const me=s.players.find(p=>p.seat===seat);
 return {kind:s.kind,status:s.status,turn:s.turn,sequence:s.sequence,startedAt:s.startedAt,deadlineAt:s.deadlineAt,result:s.result,history:s.history,
  players:s.players.map(p=>({seat:p.seat,bot:p.bot,cardCount:p.hand.length,pawns:p.pawns,team:p.seat%2,position:p.cleared??0,remaining:p.tiles?.length??0,progress:s.kind==='camel'?Math.round((p.cleared??0)/54*100):0})),
  hand:s.kind==='jackaroo'?me.hand:[],choices:s.kind==='jackaroo'?jackChoices(s,seat):camelChoices(s,seat),
  ...(s.kind==='camel'?{tiles:me.tiles,tray:me.tray,side:me.side,tools:me.tools,orders:s.orders}: {round:s.round,controlledSeat:controlled(s,seat)?.seat,ringSize:64,homeSize:4})};
}
