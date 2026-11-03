import {once} from 'node:events';
import {openDatabase} from '../../src/database.mjs';
import {createApp} from '../../src/app.mjs';
const database=await openDatabase({sqliteFile:':memory:'}),server=await createApp({database,roomAutoSweep:false,callAutoSweep:false,pushAutoFlush:false,deletionAutoSweep:false,gamesAutoTick:false,gamesClock:()=>1000000,liveRouletteAutoTick:false,rateLimitMultiplier:100});
server.listen(0,'127.0.0.1');await once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
const users=[];
for(const username of ['gamescontracta','gamescontractb']){
 const r=await fetch(base+'/v1/auth/register',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({username,displayName:username,password:'test-only games contract passphrase'})});
 if(!r.ok)throw Error('Game fixture failed');users.push(await r.json());
}
process.stdout.write(JSON.stringify({base,users})+'\n');
process.once('SIGTERM',()=>{const done=once(server,'close');server.close();server.closeIdleConnections();void done.then(()=>database.close()).then(()=>process.exit(0));});
