import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {readFile} from 'node:fs/promises';
import {fixture} from './fixtures/platform-api.mjs';
import {digest} from '../src/security.mjs';
import {migrateSQLite} from '../src/schema_migrations.mjs';
const create=async(f,a,kind,mode='practice')=>{const r=await f.req(a,'POST','/v1/games/matches',{kind,mode,requestId:randomUUID()});assert.equal(r.status,200,JSON.stringify(r));return r.data.match;};
const act=(f,a,m,choice,requestId=randomUUID())=>f.req(a,'POST',`/v1/games/matches/${m.id}/action`,{type:'choose',choice,expectedRevision:m.revision,requestId});

test('board-game SQLite upgrade retains existing matches, membership and receipt across repeated migration',async()=>{
 const db=new DatabaseSync(':memory:');try{
 db.exec('PRAGMA foreign_keys=ON');db.exec(await readFile(new URL('../schema.sql',import.meta.url),'utf8'));
 db.prepare('INSERT INTO tomi_users(id,username,display_name,password_hash,recovery_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?)').run('u','old','old','hash','hash','stamp','stamp');
 db.prepare('INSERT INTO tomi_game_matches VALUES(?,?,?,?,?,?,?,?,?,?,?)').run('old-match','ABC12345','uno','practice','u','playing',9,'{"saved":true}',123,1,1);
 db.prepare('INSERT INTO tomi_game_players VALUES(?,?,?)').run('old-match','u',0);
 db.prepare('INSERT INTO tomi_game_requests VALUES(?,?,?,?,?,?)').run('u','retry-id','fingerprint','old-match','{"replayed":true}',1);
 migrateSQLite(db);migrateSQLite(db);
 assert.equal(db.prepare('SELECT revision FROM tomi_game_matches').get().revision,9);assert.equal(db.prepare('SELECT fingerprint FROM tomi_game_requests').get().fingerprint,'fingerprint');assert.equal(db.prepare('SELECT COUNT(*) n FROM tomi_game_players').get().n,1);assert.deepEqual(db.prepare('PRAGMA foreign_key_check').all(),[]);assert.equal(db.prepare('PRAGMA foreign_keys').get().foreign_keys,1);
 db.prepare('INSERT INTO tomi_game_matches VALUES(?,?,?,?,?,?,?,?,?,?,?)').run('new-match','ABC12346','jackaroo','practice','u','playing',0,'{}',123,1,1);
 db.prepare('DELETE FROM tomi_game_matches WHERE id=?').run('old-match');assert.equal(db.prepare('SELECT COUNT(*) n FROM tomi_game_requests').get().n,0);assert.equal(db.prepare('SELECT COUNT(*) n FROM tomi_game_players').get().n,0);
 }finally{db.close();}
});
test('jackaroo HTTP plays one persisted choice on duplicate requests and restores private cards after restart',async t=>{
 const f=await fixture(t,{gamesAutoTick:false,gamesClock:()=>1000000}),a=await f.register('jack_owner'),b=await f.register('jack_outsider');const m=await create(f,a,'jackaroo');assert.equal(m.players.length,4);assert.equal(m.hand.length,4);assert.ok(m.players.every(p=>!('hand'in p)));
 assert.equal((await f.req(b,'GET',`/v1/games/matches/${m.id}`)).status,403);const id=randomUUID(),choice=m.choices[0].id;
 const rs=await Promise.all([act(f,a,m,choice,id),act(f,a,m,choice,id)]);assert.ok(rs.every(r=>r.status===200),JSON.stringify(rs));assert.equal(rs[0].data.match.sequence,1);assert.equal((await act(f,a,m,'changed-choice',id)).status,409);
 await f.restart();const restored=(await f.req(a,'GET',`/v1/games/matches/${m.id}`)).data.match;assert.deepEqual(restored.hand,rs[0].data.match.hand);assert.equal(restored.revision,rs[0].data.match.revision);
 const stored=JSON.parse((await f.db.query('SELECT state FROM tomi_game_matches WHERE id=?',[m.id])).rows[0].state);
 stored.turn=0;stored.startedAt=960000;stored.players[0].humanMoves=3;stored.players[0].pawns=[63,65,66,67];stored.players[0].hand=[{id:'win-A',value:'A',suit:'clubs'}];stored.players[2].pawns=[64,65,66,67];
 await f.db.query('UPDATE tomi_game_matches SET state=? WHERE id=?',[JSON.stringify(stored),m.id]);
 const final=(await f.req(a,'GET',`/v1/games/matches/${m.id}`)).data.match,win=final.choices.find(x=>x.steps?.[0].pawn===0&&x.steps[0].steps===1),rid=randomUUID();
 const won=await act(f,a,final,win.id,rid);assert.equal(won.status,200,JSON.stringify(won));assert.equal(won.data.match.earnedXp,60);assert.equal(won.data.coins,1000);assert.equal(won.data.charisma.points,0);
 assert.equal((await act(f,a,final,win.id,rid)).data.match.earnedXp,60);assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_game_awards WHERE source_id=?',[m.id])).rows[0].n),1);

});
test('camel friends share orders while rejecting forged tiles and a fourth member',async t=>{
 const f=await fixture(t,{gamesAutoTick:false}),a=await f.register('camel_owner'),b=await f.register('camel_friend'),c=await f.register('camel_third'),d=await f.register('camel_fourth');let m=await create(f,a,'camel','friends');
 for(const user of [b,c])assert.equal((await f.req(user,'POST','/v1/games/join',{code:m.code,requestId:randomUUID()})).status,200);
 assert.equal((await f.req(d,'POST','/v1/games/join',{code:m.code,requestId:randomUUID()})).data.error.code,'GAME_FULL');
 m=(await f.req(a,'GET',`/v1/games/matches/${m.id}`)).data.match;const begun=await f.req(a,'POST',`/v1/games/matches/${m.id}/action`,{type:'start',expectedRevision:m.revision,requestId:randomUUID()});assert.equal(begun.status,200,JSON.stringify(begun));m=begun.data.match;
 const other=(await f.req(b,'GET',`/v1/games/matches/${m.id}`)).data.match;assert.ok(other.tiles.every(t=>t.id.startsWith('1-')));assert.ok(m.tiles.every(t=>t.id.startsWith('0-')));
 const own=other.choices.find(x=>x.type==='tile');assert.equal((await act(f,b,other,own.id)).status,200);
 const fresh=(await f.req(a,'GET',`/v1/games/matches/${m.id}`)).data.match;assert.equal((await act(f,a,fresh,own.id)).data.error.code,'GAME_CHOICE');
 assert.equal((await f.req(a,'GET','/v1/games')).data.coins,1000);
 const state=JSON.parse((await f.db.query('SELECT state FROM tomi_game_matches WHERE id=?',[m.id])).rows[0].state);
 state.startedAt=Date.now()-40000;for(const p of state.players){p.tiles=[];p.tray=[];p.side=[];p.humanMoves=3;p.cleared=54;}
 state.players[0].tiles=[{id:'final',x:0,y:0,z:0,kind:0}];state.players[0].tray=[{id:'a',kind:0},{id:'b',kind:0}];state.players[0].cleared=51;
 await f.db.query('UPDATE tomi_game_matches SET state=? WHERE id=?',[JSON.stringify(state),m.id]);
 const last=(await f.req(a,'GET',`/v1/games/matches/${m.id}`)).data.match,rid=randomUUID(),won=await act(f,a,last,'final',rid);assert.equal(won.status,200,JSON.stringify(won));assert.deepEqual(won.data.match.result.winnerSeats,[0,1,2]);assert.equal(won.data.match.earnedXp,60);
 await act(f,a,last,'final',rid);for(const member of [a,b,c])assert.equal((await f.req(member,'GET','/v1/games')).data.progress.xp,60);
 assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_game_awards WHERE source_id=?',[m.id])).rows[0].n),3);

});

test('database reopening upgrades the old PostgreSQL kind constraint and preserves pre-upgrade UNO retry fingerprints',async t=>{
 const f=await fixture(t,{gamesAutoTick:false,gamesClock:()=>1000000}),a=await f.register('upgrade_owner'),m=await create(f,a,'uno');
 const d={type:'draw',expectedRevision:m.revision,requestId:randomUUID()},path=`/v1/games/matches/${m.id}/action`;
 const first=await f.req(a,'POST',path,d);assert.equal(first.status,200);
 const old=digest(JSON.stringify(['action',m.id,m.revision,'draw',null,null,null]));
 await f.db.query('UPDATE tomi_game_requests SET fingerprint=? WHERE user_id=? AND request_id=?',[old,a.user.id,d.requestId]);
 if(f.db.dialect==='postgres'){
  await f.db.query('ALTER TABLE tomi_game_matches DROP CONSTRAINT tomi_game_matches_kind_check');
  await f.db.query("ALTER TABLE tomi_game_matches ADD CONSTRAINT tomi_game_matches_kind_check CHECK(kind IN('uno','snakes'))");
 }
 await f.restart();const replay=await f.req(a,'POST',path,d);assert.equal(replay.status,200,JSON.stringify(replay));assert.equal(replay.data.receipt.replayed,true);
 assert.deepEqual(replay.data.match.hand,first.data.match.hand);
 const left=await f.req(a,'POST',path,{type:'leave',expectedRevision:replay.data.match.revision,requestId:randomUUID()});assert.equal(left.status,200);
 const fresh=await create(f,a,'camel');assert.equal(fresh.kind,'camel');
});
