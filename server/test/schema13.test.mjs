import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {openDatabase} from '../src/database.mjs';
const connectionString=process.env.TEST_DATABASE_URL;
if(connectionString){const u=new URL(connectionString);assert.ok(['localhost','127.0.0.1'].includes(u.hostname)&&u.pathname==='/tomi_test');}
async function fixture(t){
 const dir=await mkdtemp(join(tmpdir(),'tomi-schema13-'));let db;
 const close=async()=>{const old=db;db=null;if(old)await old.close();};
 t.after(async()=>{await close();await rm(dir,{recursive:true,force:true});});
 const start=async()=>{db=await openDatabase({connectionString,sqliteFile:join(dir,'state.sqlite')});};
 await start();if(connectionString){await db.query('DELETE FROM tomi_users');await db.query('DELETE FROM tomi_rate_limits');}
 return {get db(){return db;},async restart(){await close();await start();}};
}
async function seed(db){
 const a=randomUUID(),b=randomUUID(),r=randomUUID(),free=randomUUID(),gift=randomUUID(),batch=randomUUID(),nonce=randomUUID(),date=new Date().toISOString();
 for(const [id,name]of [[a,'schema13a'],[b,'schema13b']])await db.query('INSERT INTO tomi_users(id,username,display_name,password_hash,recovery_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',[id,name,name,'test-only','test-only',date,date]);
 for(const id of [r,free])await db.query('INSERT INTO tomi_voice_rooms(id,title,owner_id,capacity,seat_count,created_at) VALUES(?,?,?,?,?,?)',[id,'Preserved room',a,10,4,date]);
 await db.query("INSERT INTO tomi_room_policy(room_id,tier,public_id,creator_id,price,last_owner_visit) VALUES(?,'advanced','999901',?,5799,?)",[r,a,date]);
 await db.query("INSERT INTO tomi_room_policy(room_id,tier,public_id,creator_id,last_owner_visit) VALUES(?,'free',NULL,?,?)",[free,b,date]);
 await db.query('INSERT INTO tomi_room_wallets(user_id,coins,next_claim) VALUES(?,1500,?)',[a,date]);
 await db.query('INSERT INTO tomi_user_progress(user_id,spent,gifts_sent,received,gifts_received) VALUES(?,300,1,300,1)',[a]);
 await db.query('INSERT INTO tomi_room_support_batches(id,room_id,sender_id,request_id,fingerprint,total,recipients) VALUES(?,?,?,?,?,300,?)',[batch,r,a,nonce,'test-only',JSON.stringify([a])]);
 await db.query("INSERT INTO tomi_room_support(id,room_id,sender_id,recipient_id,request_id,gift_id,quantity,unit_price,total,created_at) VALUES(?,?,?,?,?,'diamond',3,100,300,?)",[gift,r,a,a,nonce,date]);
 await db.query('INSERT INTO tomi_room_options(room_id,next_event) VALUES(?,1)',[r]);
 await db.query("INSERT INTO tomi_room_events(room_id,sequence,actor_id,request_id,kind,body,created_at) VALUES(?,1,?,?,'gift','ألماسة',?)",[r,a,nonce,date]);
 await db.query('INSERT INTO tomi_support_events(room_id,sequence,gift_id) VALUES(?,1,?)',[r,gift]);
 await db.query("INSERT INTO tomi_room_cosmetics(user_id,kind,style_id,expires_at) VALUES(?,'frame','flame',?)",[a,new Date(Date.now()+86400000).toISOString()]);
 return {a,b,r,free,gift,batch,nonce};
}
async function makeLegacy(db){
 if(db.dialect==='postgres'){
  await db.query('ALTER TABLE tomi_support_events DROP CONSTRAINT tomi_support_events_gift_id_fkey');
  await db.query('ALTER TABLE tomi_support_events ADD CONSTRAINT tomi_support_events_gift_id_fkey FOREIGN KEY(gift_id) REFERENCES tomi_room_support(id)');
 }else{
  await db.query('CREATE TABLE tomi_support_events_legacy(room_id TEXT NOT NULL,sequence BIGINT NOT NULL,gift_id TEXT NOT NULL REFERENCES tomi_room_support(id),PRIMARY KEY(room_id,sequence),FOREIGN KEY(room_id,sequence) REFERENCES tomi_room_events(room_id,sequence) ON DELETE CASCADE)');
  await db.query('INSERT INTO tomi_support_events_legacy SELECT * FROM tomi_support_events');
  await db.query('DROP TABLE tomi_support_events');await db.query('ALTER TABLE tomi_support_events_legacy RENAME TO tomi_support_events');
 }
}
async function cascade(db){
 return db.dialect==='postgres'?(await db.query("SELECT confdeltype FROM pg_constraint WHERE conrelid='tomi_support_events'::regclass AND conname='tomi_support_events_gift_id_fkey'")).rows[0].confdeltype==='c':(await db.query("SELECT * FROM pragma_foreign_key_list('tomi_support_events') WHERE \"from\"='gift_id'")).rows[0].on_delete==='CASCADE';
}
test('1.3.1 new support links cascade when a parent gift is removed; unrelated event/room remains',async t=>{
 const f=await fixture(t),s=await seed(f.db);assert.equal(await cascade(f.db),true);
 await f.db.query('DELETE FROM tomi_room_support WHERE id=?',[s.gift]);
 assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_support_events')).rows[0].n),0);
 assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_room_events WHERE room_id=?',[s.r])).rows[0].n),1);
});
test('1.3.1 existing 1.3 support links migrate twice without losing gifts, receipts, charisma, coins or multiple room ownership',async t=>{
 const f=await fixture(t),s=await seed(f.db);await makeLegacy(f.db);assert.equal(await cascade(f.db),false);
 if(f.db.dialect==='postgres')await assert.rejects(f.db.query('DELETE FROM tomi_room_support WHERE id=?',[s.gift]),e=>e.code==='23503');
 await f.restart();await f.restart();assert.equal(await cascade(f.db),true);
 assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_voice_rooms WHERE owner_id=?',[s.a])).rows[0].n),2);
 assert.equal((await f.db.query('SELECT request_id FROM tomi_room_support WHERE id=?',[s.gift])).rows[0].request_id,s.nonce);
 assert.equal(Number((await f.db.query('SELECT total FROM tomi_room_all_gifts WHERE id=?',[s.gift])).rows[0].total),300);
 assert.equal((await f.db.query('SELECT gift_id FROM tomi_support_events WHERE room_id=?',[s.r])).rows[0].gift_id,s.gift);
 assert.equal((await f.db.query('SELECT request_id FROM tomi_room_support_batches WHERE id=?',[s.batch])).rows[0].request_id,s.nonce);
 assert.equal(Number((await f.db.query('SELECT coins FROM tomi_room_wallets WHERE user_id=?',[s.a])).rows[0].coins),1500);
 assert.equal(Number((await f.db.query('SELECT spent FROM tomi_user_progress WHERE user_id=?',[s.a])).rows[0].spent),300);
 assert.equal((await f.db.query('SELECT style_id FROM tomi_room_cosmetics WHERE user_id=?',[s.a])).rows[0].style_id,'flame');
 await f.db.query('DELETE FROM tomi_users WHERE id=?',[s.a]);
 assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_support_events')).rows[0].n),0);
 assert.equal((await f.db.query('SELECT id FROM tomi_users WHERE id=?',[s.b])).rows[0].id,s.b);
});
