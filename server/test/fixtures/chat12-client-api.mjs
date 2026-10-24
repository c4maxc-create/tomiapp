// Real HTTP/SQLite contract. R2 transport is isolated in memory on loopback.
import {once} from 'node:events';
import {openDatabase} from '../../src/database.mjs';
import {createApp} from '../../src/app.mjs';
import {R2Images} from '../../src/r2.mjs';
const objects=new Map(),bucket='tomi-chat12-test';
const storage=new R2Images({endpoint:'https://'+'a'.repeat(32)+'.r2.cloudflarestorage.com',bucket,accessKeyId:'test-only',secretAccessKey:'test-only'},{fetcher:async(url,opts)=>{const key=decodeURIComponent(new URL(url).pathname.slice(bucket.length+2));if(opts?.method==='DELETE'){objects.delete(key);return new Response(null,{status:204});}const f=objects.get(key);return f?new Response(f.bytes,{headers:{'content-type':f.type,'content-length':String(f.bytes.length)}}):new Response(null,{status:404});}});
const database=await openDatabase({sqliteFile:':memory:'}),server=await createApp({database,storage,roomAutoSweep:false,callAutoSweep:false,pushAutoFlush:false,deletionAutoSweep:false,rateLimitMultiplier:100});
const handlers=server.listeners('request');server.removeAllListeners('request');server.on('request',async(req,res)=>{
 if(req.url.startsWith('/'+bucket+'/')){if(req.method!=='PUT'){res.writeHead(405);res.end();return;}const parts=[];let length=0;for await(const part of req){length+=part.length;if(length>25*1024*1024){res.writeHead(413);res.end();return;}parts.push(part);}const key=decodeURIComponent(new URL(req.url,'http://loopback').pathname.slice(bucket.length+2));objects.set(key,{bytes:Buffer.concat(parts),type:req.headers['content-type']});res.writeHead(204);res.end();return;}
 for(const handler of handlers)handler.call(server,req,res);
});
server.listen(0,'127.0.0.1');await once(server,'listening');const base='http://127.0.0.1:'+server.address().port,users=[];
for(const username of ['chatcontracta','chatcontractb','chatcontractc']){const r=await fetch(base+'/v1/auth/register',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({username,displayName:username,password:'test-only chat contract passphrase'})});if(!r.ok)throw Error('Chat fixture setup failed');users.push(await r.json());}
process.stdout.write(JSON.stringify({base,users})+'\n');
process.once('SIGTERM',()=>{const closed=once(server,'close');server.close();server.closeIdleConnections();void closed.then(()=>database.close()).then(()=>process.exit(0));});
