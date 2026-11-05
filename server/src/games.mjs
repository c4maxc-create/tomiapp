import {createGameSearch} from './game_search.mjs';
import {randomUUID,randomBytes} from 'node:crypto';
import {ApiError,digest} from './security.mjs';
import {newGame,performGameAction,automaticAction,publicGameState} from './game_engine.mjs';
import {awardGameXp,gameProgress} from './game_progress.mjs';
import {charismaStatus} from './charisma_catalog.mjs';
import {welcomeCoins} from './room_catalog.mjs';

const uuid=v=>typeof v==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(v);
const fail=(s,c,m)=>{throw new ApiError(s,c,m);};
const policy={winXp:60,completeXp:20,rouletteXp:10,rewardedRoundsPerDay:20,minimumSeconds:30,minimumHumanMoves:3,maxLevel:50,timeZone:'Asia/Baghdad'};
function fields(d,keys) {if(Object.keys(d).some(k=>!keys.includes(k)))fail(400,'VALIDATION','حقل غير مسموح في طلب اللعبة.');}

export function createGames({database,readJson,respond,limit,usersByIds,emit,accountGate,clock=Date.now,autoTick=true,unbound=fn=>fn()}) {
  let timer=null,closed=false,sweeping=null;
  const search=createGameSearch({database,clock,accountGate,emit});
  const getMembers=(db,id)=>db.query('SELECT user_id,seat FROM tomi_game_players WHERE match_id=? ORDER BY user_id',[id]);
  async function notify(id) {
    if(closed)return;
    const rows=(await getMembers(database,id)).rows;
    emit(rows.map(r=>r.user_id),{type:'games.changed',matchId:id});
  }
  function startTimer() {
    if(!autoTick||timer||closed)return;
    timer=setInterval(()=>{unbound(sweep).catch(()=>{});},1000);timer.unref?.();
  }
  async function lock(db,id) {
    const {rows}=await db.query('UPDATE tomi_game_matches SET revision=revision WHERE id=? RETURNING *',[id]);
    if(!rows[0])fail(404,'GAME_NOT_FOUND','الجولة غير موجودة.');
    return rows[0];
  }
  async function transact(id,work) {
    // Acquire shared account gates before the match row, so account erasure
    // cannot be caught behind a row held by a game waiting for that account.
    const ids=(await getMembers(database,id)).rows.map(r=>r.user_id).sort();
    return database.transaction(async db=>{
      for(const uid of ids)await accountGate(db,uid);
      const row=await lock(db,id);
      return work(db,row,(await getMembers(db,id)).rows);
    });
  }
  async function save(db,row,state) {
    const result=await db.query('UPDATE tomi_game_matches SET state=?,status=?,revision=revision+1,due_at=?,updated_at=? WHERE id=? RETURNING *',[JSON.stringify(state),state.status,state.deadlineAt??clock()+300000,clock(),row.id]);
    return result.rows[0];
  }
  async function rewards(db,row,state,members) {
    if(state.status!=='finished')return;
    for(const member of members) {
      const player=state.players.find(p=>p.seat===Number(member.seat));
      if(!player||player.bot||player.humanMoves<policy.minimumHumanMoves||clock()-state.startedAt<policy.minimumSeconds*1000)continue;
      await awardGameXp(db,member.user_id,row.kind,row.id,(state.result.winnerSeats??[state.result.winnerSeat]).includes(player.seat)?policy.winXp:policy.completeXp,clock());
    }
  }
  async function advance(db,row,members) {
    let state=JSON.parse(row.state);
    if(row.status==='waiting'&&clock()-Number(row.created_at)>=600000||row.status==='playing'&&clock()-state.startedAt>=3600000) {
      state.status='cancelled';row=await save(db,row,state);
    } else if(row.status==='playing'&&clock()>=Number(row.due_at)) {
      state=performGameAction(state,state.turn,automaticAction(state),{now:clock(),automatic:true});
      row=await save(db,row,state);await rewards(db,row,state,members);
    }
    return row;
  }
  async function sweep() {
    if(sweeping)return sweeping;
    sweeping=(async()=>{
      const rows=(await database.query("SELECT id FROM tomi_game_matches WHERE status IN('playing','waiting') AND due_at<=? ORDER BY due_at LIMIT 24",[clock()])).rows;
      for(const r of rows) {
        const changed=await transact(r.id,async(db,row,members)=>Number((await advance(db,row,members)).revision)!==Number(row.revision));
        if(changed)await notify(r.id);
      }
      const active=(await database.query("SELECT id FROM tomi_game_matches WHERE status IN('playing','waiting') LIMIT 1")).rows;
      if(!active.length&&timer){clearInterval(timer);timer=null;}
    })().finally(()=>{sweeping=null;});
    return sweeping;
  }
  async function known(db,c,d,fp) {
    const old=(await db.query('SELECT * FROM tomi_game_requests WHERE user_id=? AND request_id=?',[c.id,d.requestId])).rows[0];
    if(!old)return null;
    if(old.fingerprint!==fp)fail(409,'REQUEST_CHANGED','تغيّرت المحاولة؛ ابدأ خطوة جديدة.');
    return {...JSON.parse(old.result),matchId:old.match_id,replayed:true};
  }
  async function remember(db,c,d,fp,id,result={}) {
    await db.query('INSERT INTO tomi_game_requests(user_id,request_id,fingerprint,match_id,result,created_at) VALUES(?,?,?,?,?,?)',[c.id,d.requestId,fp,id,JSON.stringify(result),clock()]);
    return {...result,matchId:id};
  }
  async function oneActive(db,uid) {
    return (await db.query("SELECT m.id FROM tomi_game_matches m JOIN tomi_game_players p ON p.match_id=m.id WHERE p.user_id=? AND m.status IN('waiting','playing') LIMIT 1",[uid])).rows[0];
  }
  async function summary(c) {
    await database.query('INSERT INTO tomi_room_wallets(user_id,coins,next_claim) VALUES(?,?,?) ON CONFLICT(user_id) DO NOTHING',[c.id,welcomeCoins,new Date(Date.now()+86400000).toISOString()]);
    const row=(await database.query('SELECT w.coins,w.next_claim,g.xp,p.received FROM tomi_room_wallets w LEFT JOIN tomi_game_progress g ON g.user_id=w.user_id LEFT JOIN tomi_user_progress p ON p.user_id=w.user_id WHERE w.user_id=?',[c.id])).rows[0];
    const active=(await database.query("SELECT m.id,m.code,m.kind,m.mode,m.status,m.revision FROM tomi_game_matches m JOIN tomi_game_players p ON p.match_id=m.id WHERE p.user_id=? AND m.status IN('waiting','playing') ORDER BY m.updated_at DESC LIMIT 4",[c.id])).rows;
    if(active.length)startTimer();
    return {coins:Number(row.coins),nextClaim:row.next_claim,progress:gameProgress(row.xp??0),charisma:charismaStatus(row.received??0),activeMatches:active,availableGames:['uno','snakes','jackaroo','camel','wheel'],search:await search.status(c),policy};
  }
  async function snapshot(id,c) {
    const row=await transact(id,async(db,row,members)=>{
      if(!members.some(m=>m.user_id===c.id))fail(403,'GAME_MEMBERSHIP','ادخل إلى هذه الجولة أولًا.');
      return advance(db,row,members);
    });
    const members=(await getMembers(database,id)).rows,me=members.find(m=>m.user_id===c.id);
    if(!me)fail(403,'GAME_MEMBERSHIP','غادرت هذه الجولة.');
    const state=JSON.parse(row.state),profiles=await usersByIds(members.map(m=>m.user_id),c.id);
    const publicState=row.status==='cancelled'||state.status==='waiting'?{status:row.status,players:(state.players??[]).map(p=>({seat:p.seat,bot:p.bot,position:p.position??0,cardCount:p.hand?.length??0})),hand:[],history:[],sequence:0,result:null}:publicGameState(state,Number(me.seat));
    const award=(await database.query('SELECT xp FROM tomi_game_awards WHERE user_id=? AND source_kind=? AND source_id=?',[c.id,row.kind,id])).rows[0];
    if(row.status==='playing'||row.status==='waiting')startTimer();
    return {...publicState,id:row.id,code:row.code,kind:row.kind,mode:row.mode,revision:Number(row.revision),lobbyType:state.matchmaking?'public':'private',host:row.host_id===c.id,mySeat:Number(me.seat),serverTime:clock(),earnedXp:Number(award?.xp??0),policy,
      players:publicState.players.map(p=>({...p,user:profiles.get(members.find(m=>Number(m.seat)===p.seat)?.user_id)??null}))};
  }
  async function create(c,d) {
    fields(d,['requestId','kind','mode']);
    if(!uuid(d.requestId)||!['uno','snakes','jackaroo','camel','wheel'].includes(d.kind)||!['practice','friends'].includes(d.mode))fail(400,'VALIDATION','اختَر اللعبة وطريقة اللعب.');
    const fp=digest(JSON.stringify(['create',d.kind,d.mode]));
    return database.transaction(async db=>{
      await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=?',[c.id]);
      const replay=await known(db,c,d,fp);if(replay)return replay;
      if(await oneActive(db,c.id))fail(409,'GAME_ACTIVE','عندك جولة مفتوحة؛ أكملها أو غادرها أولًا.');
      const id=randomUUID(),seats=d.mode==='practice'?Array.from({length:['uno','jackaroo'].includes(d.kind)?4:d.kind==='camel'?3:2},(_,seat)=>({seat,bot:seat!==0})):[{seat:0,bot:false}];
      const state=d.mode==='practice'?newGame(d.kind,seats,{now:clock()}):{status:'waiting',players:seats,deadlineAt:clock()+600000};
      let inserted=false;
      for(let i=0;i<5&&!inserted;i++) {
        const code=randomBytes(4).toString('hex').toUpperCase();
        const r=await db.query('INSERT INTO tomi_game_matches(id,code,kind,mode,host_id,status,state,due_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(code) DO NOTHING RETURNING id',[id,code,d.kind,d.mode,c.id,state.status,JSON.stringify(state),state.deadlineAt,clock(),clock()]);inserted=!!r.rows[0];
      }
      if(!inserted)fail(503,'GAME_BUSY','تعذّر إنشاء كود الجولة؛ حاول مرة ثانية.');
      await db.query('INSERT INTO tomi_game_players(match_id,user_id,seat) VALUES(?,?,0)',[id,c.id]);
      return remember(db,c,d,fp,id);
    });
  }
  async function join(c,d) {
    fields(d,['requestId','code']);
    if(!uuid(d.requestId)||typeof d.code!=='string'||! /^[A-F0-9]{8}$/.test(d.code))fail(400,'VALIDATION','اكتب كود الغرفة المكوّن من8رموز.');
    const fp=digest(JSON.stringify(['join',d.code]));
    const old=await known(database,c,d,fp);if(old)return old;
    const match=(await database.query('SELECT id FROM tomi_game_matches WHERE code=?',[d.code])).rows[0];
    if(!match)fail(404,'GAME_NOT_FOUND','كود الغرفة غير موجود.');
    return transact(match.id,async(db,row,members)=>{
      const replay=await known(db,c,d,fp);if(replay)return replay;
      await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=?',[c.id]);
      if(members.some(m=>m.user_id===c.id))return remember(db,c,d,fp,row.id);
      if(row.status!=='waiting'||row.mode!=='friends'||clock()>=Number(row.due_at))fail(409,'GAME_STARTED','بدأت الجولة أو انتهى وقت انتظارها.');
      if(members.length>=(row.kind==='camel'?3:4))fail(409,'GAME_FULL','الغرفة ممتلئة.');
      if(await oneActive(db,c.id))fail(409,'GAME_ACTIVE','غادر جولتك الحالية أولًا.');
      for(const m of members) {
        const blocked=(await db.query('SELECT 1 FROM tomi_user_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)',[c.id,m.user_id,m.user_id,c.id])).rows[0];
        if(blocked)fail(403,'GAME_BLOCKED','لا يمكن الانضمام إلى هذه الغرفة.');
      }
      const state=JSON.parse(row.state),seat=[0,1,2,3].find(n=>!members.some(m=>Number(m.seat)===n));
      state.players.push({seat,bot:false});state.players.sort((a,b)=>a.seat-b.seat);
      await db.query('INSERT INTO tomi_game_players(match_id,user_id,seat) VALUES(?,?,?)',[row.id,c.id,seat]);await save(db,row,state);
      return remember(db,c,d,fp,row.id);
    });
  }
  async function action(c,id,d) {
    fields(d,['requestId','expectedRevision','type','cardId','color','uno','choice']);
    if(!uuid(d.requestId)||!Number.isSafeInteger(d.expectedRevision)||d.expectedRevision<0||!['start','leave','play','draw','pass','roll','choose','spin'].includes(d.type)||d.uno!==undefined&&typeof d.uno!=='boolean'||d.cardId!==undefined&&typeof d.cardId!=='string'||d.color!==undefined&&typeof d.color!=='string')fail(400,'VALIDATION','خطوة اللعبة غير صحيحة.');
    if(d.type==='choose'&&(typeof d.choice!=='string'||d.choice.length>100)||d.type!=='choose'&&d.choice!==undefined)fail(400,'VALIDATION','اختَر حركة صحيحة.');
    if(d.type!=='play'&&(d.cardId!==undefined||d.color!==undefined||d.uno!==undefined))fail(400,'VALIDATION','حقول الورقة متاحة عند لعبها فقط.');
    const fp=digest(JSON.stringify(['action',id,d.expectedRevision,d.type,d.cardId??null,d.color??null,d.uno??null,...(d.type==='choose'?[d.choice]:[])]));
    return transact(id,async(db,row,members)=>{
      const old=await known(db,c,d,fp);if(old)return old;
      const me=members.find(m=>m.user_id===c.id);if(!me)fail(403,'GAME_MEMBERSHIP','لست ضمن هذه الجولة.');
      row=await advance(db,row,members);
      if(d.expectedRevision!==Number(row.revision))fail(409,'GAME_CHANGED','تغيّر الدور؛ حدّث الطاولة وحاول من جديد.');
      let state=JSON.parse(row.state);
      if(d.type==='leave') {
        const player=state.players.find(p=>p.seat===Number(me.seat));
        if(row.status==='waiting')state.players=state.players.filter(p=>p.seat!==Number(me.seat));else if(player)player.bot=true;
        if(row.status==='playing'&&state.turn===Number(me.seat))state.deadlineAt=clock()+850;
        await db.query('DELETE FROM tomi_game_players WHERE match_id=? AND user_id=?',[id,c.id]);
        members=members.filter(m=>m.user_id!==c.id);
        if(!members.length)state.status='cancelled';
        await db.query('UPDATE tomi_game_matches SET host_id=? WHERE id=?',[members[0]?.user_id??null,id]);
        await save(db,row,state);return remember(db,c,d,fp,id,{left:true});
      }
      if(d.type==='start') {
        if(row.host_id!==c.id)fail(403,'GAME_HOST','صاحب الغرفة يبدأ الجولة.');
        if(row.status!=='waiting'||members.length<2)fail(409,'GAME_PLAYERS','تحتاج لاعبين على الأقل لبدء الجولة.');
        state=newGame(row.kind,state.players,{now:clock()});
      } else state=performGameAction(state,Number(me.seat),d,{now:clock()});
      row=await save(db,row,state);await rewards(db,row,state,members);
      return remember(db,c,d,fp,id);
    });
  }
  async function handle(req,res,url,c) {
    if(!url.pathname.startsWith('/v1/games'))return false;
    if(url.pathname.startsWith('/v1/games/live-roulette'))return false;
    if(req.method==='GET'&&url.pathname==='/v1/games'){respond(res,200,await summary(c));return true;}
    if(req.method==='POST'&&['/v1/games/search','/v1/games/search/cancel'].includes(url.pathname)){
      await limit('game-search:'+c.id,30);const d=await readJson(req);fields(d,['kind']);
      const found=url.pathname.endsWith('/cancel')?await search.cancel(c,d.kind):await search.start(c,d.kind);
      if(found?.matchId)startTimer();
      respond(res,200,{...await summary(c),search:found,match:found?.matchId?await snapshot(found.matchId,c):null});return true;
    }
    const match=url.pathname.match(/^\/v1\/games\/matches\/([a-f0-9-]{36})(?:\/(action))?$/);
    if(req.method==='GET'&&match&&!match[2]){respond(res,200,{match:await snapshot(match[1],c)});return true;}
    let result;
    if(req.method==='POST') {
      await limit('game-action:'+c.id,120);
      const d=await readJson(req);
      if(url.pathname==='/v1/games/matches')result=await create(c,d);
      else if(url.pathname==='/v1/games/join')result=await join(c,d);
      else if(match&&match[2])result=await action(c,match[1],d);
    }
    if(!result)fail(404,'NOT_FOUND','مسار اللعبة غير موجود.');
    startTimer();await notify(result.matchId);
    respond(res,200,{receipt:result,match:result.left?null:await snapshot(result.matchId,c),...await summary(c)});return true;
  }
  return {handle,sweep,close(){closed=true;if(timer)clearInterval(timer);}};
}
