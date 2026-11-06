// Real HTTP + SQLite. No external provider, production account or media request.
import {once} from 'node:events';
import {randomUUID} from 'node:crypto';
import {openDatabase} from '../../src/database.mjs';
import {createApp} from '../../src/app.mjs';
import {policyVersion} from '../../src/privacy.mjs';
const database=await openDatabase({sqliteFile:':memory:'}),server=await createApp({database,roomAutoSweep:false,callAutoSweep:false,pushAutoFlush:false,deletionAutoSweep:false,rateLimitMultiplier:100});
server.listen(0,'127.0.0.1');await once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
const password='test-only privacy contract passphrase';
async function req(user,method,path,body){const r=await fetch(base+path,{method,headers:{...(user?{authorization:'Bearer '+user.token}:{}),...(body?{'content-type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});if(!r.ok)throw Error('Privacy fixture setup failed: '+r.status);return r.json();}
const users=[];for(const username of ['privacycontracta','privacycontractb'])users.push(await req(null,'POST','/v1/auth/register',{username,displayName:username,password,policyVersion}));
const post=(await req(users[0],'POST','/v1/posts',{text:'منشور تجربة حذف الحساب',requestId:randomUUID()})).post;
const thread=(await req(users[0],'POST','/v1/chats',{userId:users[1].user.id})).conversation;
await req(users[0],'POST','/v1/chats/'+thread.id+'/messages',{requestId:randomUUID(),text:'رسالة تجربة حذف الحساب'});
process.stdout.write(JSON.stringify({base,users,post,thread,password,policyVersion})+'\n');
process.once('SIGTERM',()=>{const done=once(server,'close');server.close();server.closeIdleConnections();void done.then(()=>database.close()).then(()=>process.exit(0));});
