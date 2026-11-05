import {randomUUID,randomBytes} from 'node:crypto';
import {ApiError} from './security.mjs';
import {newGame} from './game_engine.mjs';
const kinds=['uno','snakes','jackaroo','camel','wheel'];
const fail=(code,text)=>{throw new ApiError(409,code,text);};
// One database row serializes each queue across API processes. All account rows
// are locked in sorted order before membership is rechecked and seats assigned.
export function createGameSearch({database,clock,accountGate,emit}){
 const active=async(db,uid)=>(await db.query("SELECT m.id FROM tomi_game_matches m JOIN tomi_game_players p ON p.match_id=m.id WHERE p.user_id=? AND m.status IN('waiting','playing') LIMIT 1",[uid])).rows[0];
 const find=async(db,uid)=>(await db.query('SELECT * FROM tomi_game_searches WHERE user_id=?',[uid])).rows[0];
 const view=row=>row?{status:row.match_id?'matched':'searching',kind:row.kind,queuedAt:Number(row.queued_at),matchId:row.match_id??null}:null;
 async function status(c){
  const row=await find(database,c.id);if(!row)return null;
  if(row.match_id){if((await active(database,c.id))?.id===row.match_id)return view(row);return null;}
  if(Number(row.expires_at)<=clock())return null;
  if(Number(row.expires_at)<clock()+20000)await database.query('UPDATE tomi_game_searches SET expires_at=? WHERE user_id=? AND match_id IS NULL AND expires_at>?',[clock()+45000,c.id,clock()]);
  return view(row);
 }
 async function start(c,kind){
  if(!kinds.includes(kind))throw new ApiError(400,'VALIDATION','اختار لعبة للبحث.');
  const outcome=await database.transaction(async db=>{
   await db.query('UPDATE tomi_game_search_locks SET tick=tick+1 WHERE kind=?',[kind]);
   const candidates=(await db.query(`SELECT q.user_id FROM tomi_game_searches q JOIN tomi_users u ON u.id=q.user_id WHERE q.kind=? AND q.match_id IS NULL AND q.expires_at>? AND q.user_id<>?
    AND NOT EXISTS(SELECT 1 FROM tomi_account_restrictions r WHERE r.user_id=q.user_id AND r.suspended=1)
    AND NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts d WHERE d.user_id=q.user_id)
    AND NOT EXISTS(SELECT 1 FROM tomi_user_blocks b WHERE (b.blocker_id=? AND b.blocked_id=q.user_id) OR (b.blocker_id=q.user_id AND b.blocked_id=?))
    AND NOT EXISTS(SELECT 1 FROM tomi_game_players p JOIN tomi_game_matches m ON m.id=p.match_id WHERE p.user_id=q.user_id AND m.status IN('waiting','playing')) ORDER BY q.queued_at,q.user_id LIMIT 1`,[kind,clock(),c.id,c.id,c.id])).rows;
   const peer=candidates[0]?.user_id;
   for(const uid of [...new Set([c.id,peer].filter(Boolean))].sort()){
    await accountGate(db,uid);await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=?',[uid]);
   }
   const old=await find(db,c.id),running=await active(db,c.id);
   if(running){if(old?.match_id===running.id)return {search:view(old),notify:[]};fail('GAME_ACTIVE','عندك جولة مفتوحة؛ ارجع إلها أولًا.');}
   if(old&&!old.match_id&&old.kind!==kind&&Number(old.expires_at)>clock())fail('GAME_SEARCH_ACTIVE','ألغِ البحث الحالي قبل اختيار لعبة ثانية.');
   const queuedAt=old?.kind===kind&&!old.match_id?Number(old.queued_at):clock();
   const other=peer?await find(db,peer):null;
   if(!other||other.match_id||Number(other.expires_at)<=clock()||await active(db,peer)){
    await db.query('INSERT INTO tomi_game_searches(user_id,kind,queued_at,expires_at,match_id) VALUES(?,?,?,?,NULL) ON CONFLICT(user_id) DO UPDATE SET kind=excluded.kind,queued_at=excluded.queued_at,expires_at=excluded.expires_at,match_id=NULL',[c.id,kind,queuedAt,clock()+45000]);
    return {search:{status:'searching',kind,queuedAt,matchId:null},notify:[]};
   }
   const id=randomUUID(),state=newGame(kind,[{seat:0,bot:false},{seat:1,bot:false}],{now:clock()});state.matchmaking=true;
   let created=false;
   for(let n=0;n<5&&!created;n++)created=(await db.query('INSERT INTO tomi_game_matches(id,code,kind,mode,host_id,status,state,due_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(code) DO NOTHING RETURNING id',[id,randomBytes(4).toString('hex').toUpperCase(),kind,'friends',peer,'playing',JSON.stringify(state),state.deadlineAt,clock(),clock()])).rows.length>0;
   if(!created)fail('GAME_BUSY','تعذّر تجهيز الطاولة؛ حاول مجددًا.');
   for(const [seat,uid] of [peer,c.id].entries()){
    await db.query('INSERT INTO tomi_game_players(match_id,user_id,seat) VALUES(?,?,?)',[id,uid,seat]);
    await db.query('INSERT INTO tomi_game_searches(user_id,kind,queued_at,expires_at,match_id) VALUES(?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET kind=excluded.kind,expires_at=excluded.expires_at,match_id=excluded.match_id',[uid,kind,uid===c.id?queuedAt:Number(other.queued_at),clock()+45000,id]);
   }
   return{search:{status:'matched',kind,queuedAt,matchId:id},notify:[peer,c.id]};
  });
  if(outcome.notify.length)emit(outcome.notify,{type:'games.search.changed',matchId:outcome.search.matchId});
  return outcome.search;
 }
 async function cancel(c,kind){
  if(!kinds.includes(kind))throw new ApiError(400,'VALIDATION','اختار البحث المطلوب إلغاؤه.');
  return database.transaction(async db=>{
   await db.query('UPDATE tomi_game_search_locks SET tick=tick+1 WHERE kind=?',[kind]);
   const row=await find(db,c.id);if(!row||row.kind!==kind)return null;
   if(row.match_id&&await active(db,c.id))return view(row); // A completed pairing is never silently left.
   await db.query('DELETE FROM tomi_game_searches WHERE user_id=? AND kind=? AND match_id IS NULL',[c.id,kind]);return null;
  });
 }
 return{start,status,cancel};
}
