import {randomInt} from 'node:crypto';
import {ApiError} from './security.mjs';
export const wheelPoints=Object.freeze([2,3,5,8,13,21,34,55]);
export function newFreeWheel(players,now){return{kind:'wheel',status:'playing',players:players.map(p=>({...p,hand:[],position:0,score:0,spins:0,moves:0,humanMoves:0})),turn:players[0].seat,sequence:0,startedAt:now,deadlineAt:now+30000,history:[],result:null};}
export function spinFreeWheel(original,seat,action,{draw=randomInt,now=Date.now(),automatic=false}={}){
 const s=structuredClone(original),p=s.players.find(x=>x.seat===seat);
 if(s.status!=='playing')throw new ApiError(409,'GAME_ENDED','انتهت الجولة.');
 if(!p||s.turn!==seat)throw new ApiError(409,'GAME_TURN','انتظر دورك.');
 if(action.type!=='spin')throw new ApiError(400,'GAME_ACTION','لفّ العجلة في دورك.');
 const slot=draw(8),points=wheelPoints[slot];p.score+=points;p.spins++;p.moves++;if(!automatic&&!p.bot)p.humanMoves++;
 s.sequence++;s.history=[{sequence:s.sequence,seat,type:'spin',slot,points,at:now,automatic},...s.history].slice(0,32);
 const eligible=s.players.filter(x=>x.spins<3);
 if(!eligible.length){const score=Math.max(...s.players.map(x=>x.score)),winners=s.players.filter(x=>x.score===score).map(x=>x.seat);s.status='finished';s.result={winnerSeat:winners[0],winnerSeats:winners,reason:'free_points',score};}
 else{const at=s.players.indexOf(p);for(let n=1;n<=s.players.length;n++){const next=s.players[(at+n)%s.players.length];if(next.spins<3){s.turn=next.seat;break;}}}
 s.deadlineAt=now+(s.players.find(x=>x.seat===s.turn)?.bot?3200:30000);return s;
}
export function publicFreeWheel(s){return{kind:'wheel',status:s.status,players:s.players.map(({seat,bot,score,spins})=>({seat,bot,score,spins,cardCount:0})),turn:s.turn,sequence:s.sequence,startedAt:s.startedAt,deadlineAt:s.deadlineAt,history:s.history,result:s.result,hand:[],points:wheelPoints,free:true};}
