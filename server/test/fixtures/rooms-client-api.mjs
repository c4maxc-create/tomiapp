// Real HTTP/database contract with an explicit fake SFU: no external media.
import {once} from 'node:events';
import {openDatabase} from '../../src/database.mjs';
import {createApp} from '../../src/app.mjs';
const database=await openDatabase({sqliteFile:':memory:'});
const roomProvider={ensure:async()=>{},grant:async(r,m)=>({url:'wss://contract.livekit.cloud',identity:m.identity,token:'fake-sfu-contract-token'}),permissions:async()=>{},remove:async()=>{},close:async()=>{}};
const server=await createApp({database,roomProvider,roomAutoSweep:false,callAutoSweep:false,pushAutoFlush:false,rateLimitMultiplier:20});
server.listen(0,'127.0.0.1');await once(server,'listening');
const base='http://127.0.0.1:'+server.address().port,users=[];
for(const username of ['contract_owner','contract_listener']){
 const r=await fetch(base+'/v1/auth/register',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({username,displayName:username,password:'test-only rooms contract passphrase'})});
 if(!r.ok)throw Error('Room fixture registration failed');users.push(await r.json());
}
process.stdout.write(JSON.stringify({base,users})+'\n');
process.once('SIGTERM',()=>{server.close(async()=>{await database.close();process.exit(0);});server.closeIdleConnections();});
