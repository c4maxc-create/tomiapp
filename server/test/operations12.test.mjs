import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {Readable} from 'node:stream';
import {createReadStream} from 'node:fs';
import {mkdtemp,rm,writeFile,readFile,readdir,stat} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {backupKey,encryptBackup,decryptBackup,fileDigest} from '../src/backup_crypto.mjs';
import {databaseTarget,postgresEnvironment,createPostgresBackup,restorePostgresCheck} from '../tools/backup.mjs';
import {loadOptions,selfTestLoad} from '../tools/local_load.mjs';
import {openDatabase} from '../src/database.mjs';

async function directory(t){const dir=await mkdtemp(join(tmpdir(),'tomi-ops12-'));t.after(()=>rm(dir,{recursive:true,force:true}));return dir;}
test('0.12 backup key is exact and encrypted archives stream back to identical bytes with private permissions',async t=>{
  const dir=await directory(t),key=randomBytes(32),bytes=randomBytes(256*1024),input=join(dir,'data.tomi-backup'),output=join(dir,'restored.dump');
  assert.deepEqual(backupKey(key.toString('base64')),key);assert.throws(()=>backupKey('not-a-key'));assert.throws(()=>backupKey(Buffer.alloc(16).toString('base64')));
  const result=await encryptBackup(Readable.from([bytes.subarray(0,7),bytes.subarray(7)]),input,key);assert.equal(result.sha256,await fileDigest(input));assert.notDeepEqual(await readFile(input),bytes);assert.equal((await stat(input)).mode&0o777,0o600);
  assert.equal((await decryptBackup(input,output,key)).authenticated,true);assert.deepEqual(await readFile(output),bytes);assert.equal((await stat(output)).mode&0o777,0o600);
});
test('0.12 backup authentication rejects wrong keys and tampered header/ciphertext/tag without publishing plaintext',async t=>{
  const dir=await directory(t),key=randomBytes(32),input=join(dir,'input.enc');await encryptBackup(Readable.from([Buffer.from('sensitive records')]),input,key);const original=await readFile(input);
  for(const [name,offset] of [['header',0],['nonce',10],['cipher',21],['tag',original.length-1]]){
    const bytes=Buffer.from(original);bytes[offset]^=1;const path=join(dir,name+'.enc'),output=join(dir,name+'.dump');await writeFile(path,bytes);await assert.rejects(decryptBackup(path,output,key));await assert.rejects(stat(output));
  }
  await assert.rejects(decryptBackup(input,join(dir,'wrong.dump'),randomBytes(32)));
  await writeFile(join(dir,'truncated.enc'),original.subarray(0,20));await assert.rejects(decryptBackup(join(dir,'truncated.enc'),join(dir,'truncated.dump'),key));
  assert.ok(!(await readdir(dir)).some(n=>n.startsWith('.tomi-decrypt-')));
});
test('0.12 archive outputs never overwrite files and empty authenticated streams remain valid',async t=>{
  const dir=await directory(t),key=randomBytes(32),input=join(dir,'archive.enc'),output=join(dir,'restore.dump');await encryptBackup(Readable.from([]),input,key);await decryptBackup(input,output,key);assert.equal((await stat(output)).size,0);
  const saved=await readFile(input);await assert.rejects(encryptBackup(Readable.from([Buffer.from('new')]),input,key));assert.deepEqual(await readFile(input),saved);
  await assert.rejects(decryptBackup(input,output,key));assert.equal((await stat(output)).size,0);assert.ok(!(await readdir(dir)).some(n=>n.startsWith('.tomi-')));
});
test('0.12 PostgreSQL child environment uses a private escaped passfile and cannot weaken remote TLS',async t=>{
  const dir=await directory(t),url='postgresql://test_user:pass%3Aword%5C@db.example.test/tomi_test?sslmode=disable';
  const {env,target}=await postgresEnvironment(url,dir);assert.equal(target.database,'tomi_test');assert.equal(env.PGSSLMODE,'verify-full');assert.equal(env.PGSSLROOTCERT,'system');assert.ok(!('PGPASSWORD'in env)&&!('DATABASE_URL'in env)&&!('TOMI_BACKUP_KEY'in env));
  assert.equal((await stat(env.PGPASSFILE)).mode&0o777,0o600);assert.match(await readFile(env.PGPASSFILE,'utf8'),/pass\\:word\\\\/);
  assert.throws(()=>databaseTarget('postgresql://u:p@production.example/tomi_restore_check',{restore:true}));assert.throws(()=>databaseTarget('postgresql://u:p@127.0.0.1/production',{restore:true}));
  assert.equal(databaseTarget('postgresql://u:p@127.0.0.1/tomi_restore_check',{restore:true}).local,true);assert.throws(()=>databaseTarget('postgresql://u:p@127.0.0.1/test?options=unsafe'));
  await assert.rejects(restorePostgresCheck({connectionString:'postgresql://u:p@production.example/tomi_restore_check',input:'unused',key:randomBytes(32),confirmed:true}));
  await assert.rejects(restorePostgresCheck({connectionString:'postgresql://u:p@127.0.0.1/tomi_restore_check',input:'unused',key:randomBytes(32)}));
});
test('0.12 failed dump processes never publish a partial archive; successful process output is encrypted',async t=>{
  const dir=await directory(t),key=randomBytes(32),broken=join(dir,'broken-dump'),good=join(dir,'good-dump');
  await writeFile(broken,'#!'+process.execPath+'\nprocess.stdout.write("partial");process.exitCode=1;\n',{mode:0o700});
  const output=join(dir,'failed.enc');await assert.rejects(createPostgresBackup({connectionString:'postgresql://test:dummy@127.0.0.1/tomi_test',output,key,dumpBinary:broken}));await assert.rejects(stat(output));
  await writeFile(good,'#!'+process.execPath+'\nif(process.argv.some(x=>x.includes("dummy")))process.exit(2);process.stdout.write("test-only custom dump stream");\n',{mode:0o700});
  const final=join(dir,'good.enc'),result=await createPostgresBackup({connectionString:'postgresql://test:dummy@127.0.0.1/tomi_test',output:final,key,dumpBinary:good});assert.equal(result.payload,'pg_dump-custom');assert.equal((JSON.parse(await readFile(final+'.json','utf8'))).sha256,await fileDigest(final));
  await decryptBackup(final,join(dir,'check.dump'),key);assert.equal(await readFile(join(dir,'check.dump'),'utf8'),'test-only custom dump stream');
});
test('0.12 a real SQLite database restores credentials, gift nonce, user identity, reports and admin audit through encrypted backup',async t=>{
  const dir=await directory(t),source=join(dir,'source.sqlite'),key=randomBytes(32),a=randomUUID(),b=randomUUID(),rid=randomUUID(),gift=randomUUID(),nonce=randomUUID(),report=randomUUID(),stamp=new Date().toISOString();
  let db=await openDatabase({sqliteFile:source});
  for(const [uid,name] of [[a,'restore12a'],[b,'restore12b']])await db.query('INSERT INTO tomi_users(id,username,display_name,password_hash,recovery_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',[uid,name,name,'credential-hash-kept','recovery-hash-kept',stamp,stamp]);
  await db.query('INSERT INTO tomi_voice_rooms(id,title,owner_id,capacity,seat_count,created_at) VALUES(?,?,?,?,?,?)',[rid,'Restore fixture',a,10,4,stamp]);
  await db.query('INSERT INTO tomi_room_gifts(id,room_id,sender_id,recipient_id,request_id,gift_id,quantity,unit_price,total,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)',[gift,rid,a,b,nonce,'diamond',2,100,200,stamp]);
  await db.query('INSERT INTO tomi_user_progress(user_id,spent) VALUES(?,200)',[a]);await db.query("INSERT INTO tomi_user_identity(user_id,frame_id) VALUES(?,'rose')",[a]);
  await db.query("INSERT INTO tomi_reports(id,reporter_id,target_type,target_id,subject_user_id,reason,description,snapshot,status,revision,review_note,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",[report,b,'account',a,a,'other','fixture','{}','reviewing',2,'private note kept',stamp,stamp]);
  await db.query('INSERT INTO tomi_admin_audit(id,actor_id,action,target_type,target_id,reason,details,created_at) VALUES(?,?,?,?,?,?,?,?)',[randomUUID(),a,'review_report','report',report,'fixture','{}',stamp]);
  await db.query('PRAGMA wal_checkpoint(TRUNCATE)');await db.close();
  const encrypted=join(dir,'database.enc'),restored=join(dir,'restored.sqlite');await encryptBackup(createReadStream(source),encrypted,key);await decryptBackup(encrypted,restored,key);db=await openDatabase({sqliteFile:restored});
  try{assert.equal((await db.query('SELECT password_hash FROM tomi_users WHERE id=?',[a])).rows[0].password_hash,'credential-hash-kept');assert.equal((await db.query('SELECT request_id FROM tomi_room_gifts WHERE id=?',[gift])).rows[0].request_id,nonce);assert.equal((await db.query('SELECT frame_id FROM tomi_user_identity WHERE user_id=?',[a])).rows[0].frame_id,'rose');assert.equal((await db.query('SELECT review_note FROM tomi_reports WHERE id=?',[report])).rows[0].review_note,'private note kept');assert.equal(Number((await db.query('SELECT COUNT(*) n FROM tomi_admin_audit')).rows[0].n),1);}finally{await db.close();}
});
test('0.12 load safeguards reject remote URLs, excessive workers, write paths and missing test tokens',()=>{
  for(const change of [{baseUrl:'https://production.example'},{baseUrl:'http://127.0.0.1:22'},{baseUrl:'http://127.0.0.1:9999?secret=bad'},{requests:201},{concurrency:9},{path:'/v1/admin/actions'},{path:'/v1/rooms'}])assert.throws(()=>loadOptions({baseUrl:'http://127.0.0.1:9999',...change}));
  assert.equal(loadOptions({baseUrl:'http://127.0.0.1:9999',requests:2,concurrency:1}).requests,2);
});
test('0.12 bounded local HTTP/database load uses isolated test rooms and returns genuine latency counts',async()=>{
  const result=await selfTestLoad({requests:24,concurrency:4});assert.equal(result.completed,24);assert.equal(result.success,24);assert.equal(result.serverErrors,0);assert.equal(result.fixture.rooms,12);assert.ok(result.p95Ms>0);assert.equal(JSON.stringify(result).includes('Bearer'),false);
});
