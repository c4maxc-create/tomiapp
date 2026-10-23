// Real HTTP + SQLite contract for the 1.1 home controller. No external providers.
import {once} from 'node:events';
import {openDatabase} from '../../src/database.mjs';
import {createApp} from '../../src/app.mjs';
const database=await openDatabase({sqliteFile:':memory:'}),server=await createApp({database,roomAutoSweep:false,callAutoSweep:false,pushAutoFlush:false,deletionAutoSweep:false,rateLimitMultiplier:100});
server.listen(0,'127.0.0.1');await once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
async function register(username){const r=await fetch(base+'/v1/auth/register',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({username,displayName:username,password:'test-only home contract passphrase'})});if(!r.ok)throw Error('Home fixture setup failed');return r.json();}
const users=[];for(const name of ['homecontracta','homecontractb'])users.push(await register(name));
process.stdout.write(JSON.stringify({base,users})+'\n');
process.once('SIGTERM',()=>{const closed=once(server,'close');server.close();server.closeIdleConnections();void closed.then(()=>database.close()).then(()=>process.exit(0));});
