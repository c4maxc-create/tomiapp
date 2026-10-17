// Real HTTP/database fixture. Media and SFU are explicit substitutes.
import {once} from 'node:events';
import {randomUUID} from 'node:crypto';
import {openDatabase} from '../../src/database.mjs';
import {createApp} from '../../src/app.mjs';
const database=await openDatabase({sqliteFile:':memory:'});let server,base;
const provider={ensure:async()=>{},grant:async(r,m)=>({url:'wss://contract.livekit.cloud',identity:m.identity,token:'test-only'}),permissions:async()=>{},remove:async()=>{},close:async()=>{}};
async function start(ownerUserId=null){server=await createApp({database,ownerUserId,roomProvider:provider,roomAutoSweep:false,callAutoSweep:false,pushAutoFlush:false,rateLimitMultiplier:100});server.listen(0,'127.0.0.1');await once(server,'listening');base='http://127.0.0.1:'+server.address().port;}
async function stop(){const done=once(server,'close');server.close();server.closeIdleConnections();await done;}
await start();
async function req(user,method,path,body){const r=await fetch(base+path,{method,headers:{...(user?{authorization:'Bearer '+user.token}:{}),...(body?{'content-type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});const d=await r.json();if(!r.ok)throw Error('Moderation fixture request failed: '+r.status);return d;}
const users=[];for(const username of ['contract12owner','contract12member','contract12moderator','contract12reporter'])users.push(await req(null,'POST','/v1/auth/register',{username,displayName:username,password:'test-only moderation contract passphrase'}));
await stop();await start(users[0].user.id);
await req(users[0],'POST','/v1/admin/actions',{action:'grant_moderator',targetId:users[2].user.id,expectedRevision:0,reason:'test-only moderator setup',requestId:randomUUID()});
const post=(await req(users[1],'POST','/v1/posts',{text:'منشور عقد اختبار الإدارة',requestId:randomUUID()})).post;
const room=(await req(users[1],'POST','/v1/rooms',{title:'غرفة عقد الإدارة',requestId:randomUUID(),capacity:10,seatCount:4})).room;
process.stdout.write(JSON.stringify({base,users,post,room})+'\n');
process.once('SIGTERM',()=>void stop().then(()=>database.close()).then(()=>process.exit(0)));
