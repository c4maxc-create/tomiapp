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
const directory=await mkdtemp(join(tmpdir(),'tomi-pg-drill12-')),key=randomBytes(32);
let db,admin,restored,created=false;
try{
  db=await openDatabase({connectionString:source});
  const user=randomUUID(),reporter=randomUUID(),room=randomUUID(),gift=randomUUID(),nonce=randomUUID(),report=randomUUID(),stamp=new Date().toISOString();
  for(const uid of [user,reporter])await db.query('INSERT INTO tomi_users(id,username,display_name,password_hash,recovery_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',[uid,'drill_'+uid.slice(0,12), 'Restore drill','test-only-password-hash','test-only-recovery-hash',stamp,stamp]);
  await db.query('INSERT INTO tomi_voice_rooms(id,title,owner_id,capacity,seat_count,created_at) VALUES(?,?,?,?,?,?)',[room,'CI restore fixture',user,10,4,stamp]);
  await db.query('INSERT INTO tomi_room_gifts(id,room_id,sender_id,recipient_id,request_id,gift_id,quantity,unit_price,total,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)',[gift,room,user,reporter,nonce,'diamond',2,100,200,stamp]);
  await db.query("INSERT INTO tomi_user_identity(user_id,frame_id) VALUES(?,'rose')",[user]);
  await db.query('INSERT INTO tomi_reports(id,reporter_id,target_type,target_id,subject_user_id,reason,description,snapshot,status,review_note,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',[report,reporter,'account',user,user,'other','drill','{}','reviewing','private note preserved',stamp,stamp]);
  await db.query('INSERT INTO tomi_admin_audit(id,actor_id,action,target_type,target_id,reason,details,created_at) VALUES(?,?,?,?,?,?,?,?)',[randomUUID(),user,'review_report','report',report,'drill','{}',stamp]);
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
  console.log('PASS: PostgreSQL encrypted dump, authenticated local restore, row counts and moderation/gift/identity records.');
}finally{
  if(db)await db.close();if(restored)await restored.end();
  if(created&&admin)await admin.query('DROP DATABASE tomi_restore_check');
  if(admin)await admin.end();await rm(directory,{recursive:true,force:true});
}
