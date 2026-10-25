// Explicit CI drill, never part of the production server or default npm test.
import assert from 'node:assert/strict';
import {randomUUID,randomBytes} from 'node:crypto';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {Client} from 'pg';
import {openDatabase} from '../src/database.mjs';
import {databaseTarget,createPostgresBackup,restorePostgresCheck} from '../tools/backup.mjs';

const source=process.env.TEST_DATABASE_URL,target=databaseTarget(source);
assert.ok(target.local&&target.database==='tomi_test','Drill requires localhost/tomi_test');
const restoreUrl=new URL(source);restoreUrl.pathname='/tomi_restore_check';
const directory=await mkdtemp(join(tmpdir(),'tomi-pg-drill13-')),key=randomBytes(32);
let db,admin,restored,upgraded,created=false;
try{
  db=await openDatabase({connectionString:source});
  const user=randomUUID(),reporter=randomUUID(),erased=randomUUID(),room=randomUUID(),gift=randomUUID(),nonce=randomUUID(),report=randomUUID(),stamp=new Date().toISOString();
  for(const uid of [user,reporter,erased])await db.query('INSERT INTO tomi_users(id,username,display_name,password_hash,recovery_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',[uid,'drill_'+uid.slice(0,12), 'Restore drill','test-only-password-hash','test-only-recovery-hash',stamp,stamp]);
  await db.query("UPDATE tomi_users SET username=?,display_name='حساب محذوف',password_hash='erased:test-only',recovery_hash='erased' WHERE id=?",['deleted_'+erased.replaceAll('-',''),erased]);
  await db.query('INSERT INTO tomi_deleted_accounts(user_id,requested_at) VALUES(?,?)',[erased,stamp]);
  await db.query("INSERT INTO tomi_erasure_media(id,user_id,media_type,upload_id,scope,object_key,final_after,next_at) VALUES(?,?,'image',?,'public',?,?,?)",[randomUUID(),erased,randomUUID(),'tomi/posts/'+erased+'/test-only.png',stamp,stamp]);
  await db.query('INSERT INTO tomi_voice_rooms(id,title,owner_id,capacity,seat_count,created_at) VALUES(?,?,?,?,?,?)',[room,'CI restore fixture',user,10,4,stamp]);
  await db.query('INSERT INTO tomi_room_gifts(id,room_id,sender_id,recipient_id,request_id,gift_id,quantity,unit_price,total,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)',[gift,room,user,reporter,nonce,'diamond',2,100,200,stamp]);
  await db.query("INSERT INTO tomi_user_identity(user_id,frame_id) VALUES(?,'rose')",[user]);
  await db.query('INSERT INTO tomi_reports(id,reporter_id,target_type,target_id,subject_user_id,reason,description,snapshot,status,review_note,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',[report,reporter,'account',user,user,'other','drill','{}','reviewing','private note preserved',stamp,stamp]);
  await db.query('INSERT INTO tomi_admin_audit(id,actor_id,action,target_type,target_id,reason,details,created_at) VALUES(?,?,?,?,?,?,?,?)',[randomUUID(),user,'review_report','report',report,'drill','{}',stamp]);
  // The 1.3 ledger, retry receipt and temporary purchases must survive a real dump.
  const support=randomUUID(),batch=randomUUID(),supportNonce=randomUUID(),expiry=new Date(Date.now()+7*86400000).toISOString();
  await db.query("INSERT INTO tomi_room_policy(room_id,tier,public_id,creator_id,price,last_owner_visit) VALUES(?,'advanced','999950',?,5799,?)",[room,user,stamp]);
  await db.query('INSERT INTO tomi_room_wallets(user_id,coins,next_claim) VALUES(?,1500,?)',[user,stamp]);
  await db.query('INSERT INTO tomi_user_progress(user_id,spent,gifts_sent,received,gifts_received) VALUES(?,300,1,300,1)',[user]);
  await db.query('INSERT INTO tomi_room_support_batches(id,room_id,sender_id,request_id,fingerprint,total,recipients) VALUES(?,?,?,?,?,300,?)',[batch,room,user,supportNonce,'restore-test',JSON.stringify([user])]);
  await db.query("INSERT INTO tomi_room_support(id,room_id,sender_id,recipient_id,request_id,gift_id,quantity,unit_price,total,created_at) VALUES(?,?,?,?,?,'diamond',3,100,300,?)",[support,room,user,user,supportNonce,stamp]);
  await db.query('INSERT INTO tomi_room_options(room_id,next_event) VALUES(?,1)',[room]);
  await db.query("INSERT INTO tomi_room_events(room_id,sequence,actor_id,request_id,kind,body,created_at) VALUES(?,1,?,?,'gift','Restore gift',?)",[room,user,supportNonce,stamp]);
  await db.query('INSERT INTO tomi_support_events(room_id,sequence,gift_id) VALUES(?,1,?)',[room,support]);
  await db.query("INSERT INTO tomi_room_cosmetics(user_id,kind,style_id,expires_at) VALUES(?,'frame','flame',?)",[user,expiry]);
  const expected=(await db.query('SELECT (SELECT COUNT(*) FROM tomi_users) users,(SELECT COUNT(*) FROM tomi_reports) reports,(SELECT COUNT(*) FROM tomi_room_gifts) gifts,(SELECT COUNT(*) FROM tomi_admin_audit) audit_entries')).rows[0];
  await db.close();db=null;
  const file=join(directory,'ci.tomi-backup');await createPostgresBackup({connectionString:source,output:file,key});
  admin=new Client({connectionString:source,ssl:false});await admin.connect();
  assert.equal((await admin.query("SELECT 1 FROM pg_database WHERE datname='tomi_restore_check'")).rows.length,0,'Existing restore-check database must not be overwritten');
  await admin.query('CREATE DATABASE tomi_restore_check TEMPLATE template0');created=true;
  const result=await restorePostgresCheck({connectionString:restoreUrl.toString(),input:file,key,confirmed:true});
  assert.deepEqual(result.counts,Object.fromEntries(Object.entries(expected).map(([k,v])=>[k,Number(v)])));
  restored=new Client({connectionString:restoreUrl.toString(),ssl:false});await restored.connect();
  assert.equal((await restored.query('SELECT password_hash FROM tomi_users WHERE id=$1',[user])).rows[0].password_hash,'test-only-password-hash');
  assert.equal((await restored.query('SELECT request_id FROM tomi_room_gifts WHERE id=$1',[gift])).rows[0].request_id,nonce);
  assert.equal((await restored.query('SELECT frame_id FROM tomi_user_identity WHERE user_id=$1',[user])).rows[0].frame_id,'rose');
  assert.equal((await restored.query('SELECT review_note FROM tomi_reports WHERE id=$1',[report])).rows[0].review_note,'private note preserved');
  assert.equal((await restored.query('SELECT 1 FROM tomi_deleted_accounts WHERE user_id=$1',[erased])).rows.length,1);
  assert.equal((await restored.query('SELECT 1 FROM tomi_erasure_media WHERE user_id=$1',[erased])).rows.length,1);
  assert.equal((await restored.query('SELECT password_hash FROM tomi_users WHERE id=$1',[erased])).rows[0].password_hash,'erased:test-only');
  await restored.end();restored=null;
  // A restored deployment must also initialize safely without changing its data.
  upgraded=await openDatabase({connectionString:restoreUrl.toString()});
  assert.equal((await upgraded.query('SELECT request_id FROM tomi_room_support WHERE id=?',[support])).rows[0].request_id,supportNonce);
  assert.equal(Number((await upgraded.query('SELECT total FROM tomi_room_all_gifts WHERE id=?',[support])).rows[0].total),300);
  assert.equal((await upgraded.query('SELECT gift_id FROM tomi_support_events WHERE room_id=?',[room])).rows[0].gift_id,support);
  assert.equal((await upgraded.query('SELECT request_id FROM tomi_room_support_batches WHERE id=?',[batch])).rows[0].request_id,supportNonce);
  assert.equal(Number((await upgraded.query('SELECT coins FROM tomi_room_wallets WHERE user_id=?',[user])).rows[0].coins),1500);
  assert.equal(Number((await upgraded.query('SELECT received FROM tomi_user_progress WHERE user_id=?',[user])).rows[0].received),300);
  assert.equal((await upgraded.query('SELECT expires_at FROM tomi_room_cosmetics WHERE user_id=?',[user])).rows[0].expires_at,expiry);
  const policy=(await upgraded.query('SELECT tier,public_id,price FROM tomi_room_policy WHERE room_id=?',[room])).rows[0];
  assert.equal(policy.tier,'advanced');assert.equal(policy.public_id,'999950');assert.equal(Number(policy.price),5799);
  assert.equal((await upgraded.query("SELECT confdeltype FROM pg_constraint WHERE conrelid='tomi_support_events'::regclass AND conname='tomi_support_events_gift_id_fkey'")).rows[0].confdeltype,'c');
  await upgraded.close();upgraded=null;
  console.log('PASS: PostgreSQL encrypted dump and authenticated local restore; row counts, credentials, erasure cleanup, moderation, identity, 1.3 support/receipts/coins/charisma/cosmetics/room policy and initialization.');
}finally{
  if(db)await db.close();if(restored)await restored.end();if(upgraded)await upgraded.close();
  if(created&&admin)await admin.query('DROP DATABASE tomi_restore_check');
  if(admin)await admin.end();await rm(directory,{recursive:true,force:true});
}
