import {performance} from 'node:perf_hooks';
import {randomUUID,randomBytes} from 'node:crypto';
import {once} from 'node:events';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {openDatabase} from '../src/database.mjs';
import {createApp} from '../src/app.mjs';
import {digest} from '../src/security.mjs';

export function loadOptions({baseUrl,requests=60,concurrency=4,path='/health',token=null}={}){
  let u;try{u=new URL(baseUrl);}catch{throw Error('A local API URL is required');}
  if(u.protocol!=='http:'||!['127.0.0.1','localhost'].includes(u.hostname)||u.username||u.password||u.search||u.hash||u.pathname!=='/'||!u.port||Number(u.port)<1024)throw Error('Load checks are restricted to a local test API on a non-system port');
  if(!Number.isInteger(requests)||requests<1||requests>200||!Number.isInteger(concurrency)||concurrency<1||concurrency>8)throw Error('Use1–200 requests and1–8 workers');
  if(!['/health','/v1/rooms','/v1/posts'].includes(path))throw Error('Only read-only test routes are allowed');
  if(path!=='/health'&&(!token||!/^[A-Za-z0-9_-]{43}$/.test(token)))throw Error('A test account token is required');
  return {baseUrl:u.origin,requests,concurrency,path,token};
}
export async function runLocalLoad(input){
  const options=loadOptions(input),latencies=[],counts={success:0,clientErrors:0,serverErrors:0,networkErrors:0};let next=0;
  const started=performance.now(),deadline=AbortSignal.timeout(30000),memoryBefore=process.memoryUsage().rss;
  await Promise.all(Array.from({length:Math.min(options.concurrency,options.requests)},async()=>{
    while(next<options.requests&&!deadline.aborted){next++;const at=performance.now();
      try{
        const response=await fetch(options.baseUrl+options.path,{headers:options.token?{authorization:'Bearer '+options.token}:{},redirect:'error',signal:AbortSignal.any([deadline,AbortSignal.timeout(5000)])});
        let bytes=0;const reader=response.body?.getReader();
        if(reader)for(;;){const part=await reader.read();if(part.done)break;bytes+=part.value.byteLength;if(bytes>1024*1024){await reader.cancel();throw Error('Response exceeds test limit');}}
        if(response.ok)counts.success++;else if(response.status>=500)counts.serverErrors++;else counts.clientErrors++;
      }catch{counts.networkErrors++;}
      latencies.push(performance.now()-at);
    }
  }));
  latencies.sort((a,b)=>a-b);const elapsedMs=performance.now()-started,percentile=p=>latencies.length?Number(latencies[Math.min(latencies.length-1,Math.ceil(latencies.length*p)-1)].toFixed(2)):0;
  return {kind:'bounded_local_http_sample',route:options.path,requested:options.requests,completed:latencies.length,concurrency:options.concurrency,...counts,elapsedMs:Number(elapsedMs.toFixed(2)),requestsPerSecond:Number((latencies.length/(elapsedMs/1000)).toFixed(2)),p50Ms:percentile(.5),p95Ms:percentile(.95),p99Ms:percentile(.99),maxMs:percentile(1),rssBeforeBytes:memoryBefore,rssAfterBytes:process.memoryUsage().rss,createdAt:new Date().toISOString(),limits:'Local HTTP and database only; no real audio, SFU, storage transfer, production traffic or capacity guarantee.'};
}
export async function selfTestLoad({requests=60,concurrency=4}={}){
  const db=await openDatabase({sqliteFile:':memory:'}),uid=randomUUID(),token=randomBytes(32).toString('base64url'),stamp=new Date().toISOString();
  let server;
  try{
    await db.query('INSERT INTO tomi_users(id,username,display_name,password_hash,recovery_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',[uid,'load_fixture12','اختبار محلي','test-only-no-login','test-only-no-recovery',stamp,stamp]);
    await db.query('INSERT INTO tomi_sessions(token_hash,user_id,auth_version,created_at,expires_at) VALUES(?,?,1,?,?)',[digest(token),uid,stamp,new Date(Date.now()+1800000).toISOString()]);
    for(let i=0;i<12;i++){const owner=randomUUID();await db.query('INSERT INTO tomi_users(id,username,display_name,password_hash,recovery_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',[owner,'load_room_'+i,'اختبار غرفة','test-only','test-only',stamp,stamp]);await db.query('INSERT INTO tomi_voice_rooms(id,title,owner_id,capacity,seat_count,created_at) VALUES(?,?,?,?,?,?)',[randomUUID(),'غرفة اختبار '+i,owner,10,4,stamp]);}
    const provider={ensure:async()=>{},grant:async()=>{throw Error('No media in a load test');},permissions:async()=>{},remove:async()=>{},close:async()=>{}};
    server=await createApp({database:db,roomProvider:provider,roomAutoSweep:false,callAutoSweep:false,pushAutoFlush:false,rateLimitMultiplier:100});server.listen(0,'127.0.0.1');await once(server,'listening');
    const result=await runLocalLoad({baseUrl:'http://127.0.0.1:'+server.address().port,requests,concurrency,path:'/v1/rooms',token});result.fixture={database:'in_memory_sqlite',rooms:12,media:'explicit_test_adapter'};return result;
  }finally{if(server){const done=once(server,'close');server.close();server.closeIdleConnections();await done;}await db.close();}
}
async function main(){
  const args=process.argv.slice(2);if(args[0]==='--self-test'){process.stdout.write(JSON.stringify(await selfTestLoad(),null,2)+'\n');return;}
  const input={};let confirmed=false;
  for(let i=0;i<args.length;i++){if(args[i]==='--confirm-local-test'){confirmed=true;continue;}const key={'--url':'baseUrl','--requests':'requests','--concurrency':'concurrency','--path':'path'}[args[i]];if(!key||args[i+1]===undefined)throw Error('Unknown load option');const value=args[++i];input[key]=['requests','concurrency'].includes(key)?Number(value):value;}
  if(!confirmed)throw Error('Explicit --confirm-local-test is required');input.token=process.env.TOMI_LOCAL_TEST_TOKEN||null;
  process.stdout.write(JSON.stringify(await runLocalLoad(input),null,2)+'\n');
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)main().catch(()=>{console.error('Local load check rejected or failed; use only the documented localhost test environment.');process.exitCode=1;});
