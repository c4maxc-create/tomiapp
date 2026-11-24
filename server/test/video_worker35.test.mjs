import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {transcodeVideo} from '../src/video_worker.mjs';
import {videoMetadata} from '../src/video.mjs';
test('35 actual FFmpeg produces bounded playable 540 and 720 H264/AAC variants and strips metadata',async t=>{
 const dir=await mkdtemp(join(tmpdir(),'tomi-ffmpeg-test-'));t.after(()=>rm(dir,{recursive:true,force:true}));const input=join(dir,'input.mp4');
 await new Promise((resolve,reject)=>{const p=spawn('/usr/bin/ffmpeg',['-nostdin','-hide_banner','-loglevel','error','-f','lavfi','-i','testsrc=size=960x540:rate=12','-f','lavfi','-i','sine=frequency=500','-t','1','-c:v','libx264','-pix_fmt','yuv420p','-c:a','aac','-metadata','title=private title','-y',input],{stdio:'ignore'});p.on('error',reject);p.on('close',c=>c===0?resolve():reject(Error('fixture ffmpeg')));});
 for(const height of [540,720]){const output=join(dir,height+'.mp4');await transcodeVideo(input,output,height,{binary:'/usr/bin/ffmpeg'});const bytes=await readFile(output),m=videoMetadata(bytes);assert.ok(m.width<=height&&m.height<=height);assert.ok(m.durationMs>=500);assert.equal(bytes.includes(Buffer.from('private title')),false);}
 await assert.rejects(transcodeVideo(input,join(dir,'bad.mp4'),1080),/VIDEO_HEIGHT/);
});

test('35 video queue routes private media privately, persists both variants and cancels erased users before upload',async t=>{
 const {openDatabase}=await import('../src/database.mjs'),{createVideoWorker}=await import('../src/video_worker.mjs'),{cleanupVideoDerivatives}=await import('../src/media_intents.mjs'),{writeFile}=await import('node:fs/promises'),{randomUUID}=await import('node:crypto');const db=await openDatabase({connectionString:process.env.TEST_DATABASE_URL,sqliteFile:':memory:'});if(process.env.TEST_DATABASE_URL){await db.query('DELETE FROM tomi_users');await db.query('DELETE FROM tomi_rate_limits');}t.after(()=>db.close());const uid=randomUUID(),stamp=new Date().toISOString();await db.query('INSERT INTO tomi_users(id,username,display_name,password_hash,recovery_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',[uid,'worker35','worker','fixture','fixture',stamp,stamp]);
 const bytes=Buffer.from('fixture source bytes'),key='tomi/chat-videos/'+uid+'/video.mp4',id=randomUUID();await db.query("INSERT INTO tomi_video_uploads(id,user_id,object_key,content_type,byte_length,content_md5,width,height,duration_ms,state,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?,'attached',?,?)",[id,uid,key,'video/mp4',bytes.length,(await import('node:crypto')).createHash('md5').update(bytes).digest('base64'),960,540,1000,stamp,stamp]);
 const saved=[],removed=[];const privateStore={privateReadUrl:k=>'https://private.example/'+k,fetcher:async()=>new Response(bytes),putDerived:async(k,b)=>saved.push(k),delete:async k=>removed.push(k)};const publicStore={putDerived:async()=>assert.fail('private data in public bucket')};let erased=false;
 const convert=async(i,o,h)=>{await writeFile(o,Buffer.from('converted'+h));if(erased)await db.query('INSERT INTO tomi_deleted_accounts(user_id,requested_at) VALUES(?,?) ON CONFLICT(user_id) DO NOTHING',[uid,stamp]);};
 const worker=createVideoWorker({database:db,storage:publicStore,chatStorage:privateStore,binary:'fixture',auto:false,convert});t.after(()=>worker.close());await worker.tick();assert.equal(saved.length,2);assert.equal((await db.query('SELECT * FROM tomi_video_renditions WHERE upload_id=?',[id])).rows.length,2);await cleanupVideoDerivatives(db,privateStore,id,key);assert.equal(removed.length,2);assert.equal((await db.query('SELECT * FROM tomi_video_renditions')).rows.length,0);
 erased=true;await worker.tick();assert.equal(saved.length,2);assert.equal((await db.query('SELECT state FROM tomi_video_jobs WHERE upload_id=?',[id])).rows[0].state,'cancelled');
});
