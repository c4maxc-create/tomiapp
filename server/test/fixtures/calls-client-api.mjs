// Local-only bridge for the optional Flutter/API contract test. No real services.
import {once} from 'node:events';
import {openDatabase} from '../../src/database.mjs';
import {createApp} from '../../src/app.mjs';
const database=await openDatabase({sqliteFile:':memory:'});
const server=await createApp({database,iceProvider:async()=>({iceServers:[]}),callAutoSweep:false,pushAutoFlush:false,rateLimitMultiplier:20});
server.listen(0,'127.0.0.1');await once(server,'listening');
const base='http://127.0.0.1:'+server.address().port,users=[];
for(const username of ['contract_caller','contract_callee']){
 const r=await fetch(base+'/v1/auth/register',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({username,displayName:username,password:'test-only call contract passphrase'})});
 if(!r.ok)throw Error('Fixture registration failed');users.push(await r.json());
}
process.stdout.write(JSON.stringify({base,users})+'\n');
process.once('SIGTERM',()=>{server.close(async()=>{await database.close();process.exit(0);});server.closeIdleConnections();});
