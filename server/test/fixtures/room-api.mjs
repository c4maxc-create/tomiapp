import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {once} from 'node:events';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {openDatabase} from '../../src/database.mjs';
import {createApp} from '../../src/app.mjs';

export async function fixture(t,{disabled=false,storage=null}={}){
 const dir=await mkdtemp(join(tmpdir(),'tomi-rooms-')),calls=[];let down=false,db,server,base;
 const provider={ensure:async()=>{if(down)throw Error('offline');},
  grant:async(r,m)=>({url:'wss://test.livekit.cloud',identity:m.identity,token:'test-only',publish:!!m.mic_allowed}),
  permissions:async(r,id,publish)=>{if(down)throw Error('offline');calls.push(['permission',id,publish]);},
  remove:async(r,id)=>{if(down)throw Error('offline');calls.push(['remove',id]);},close:async r=>{if(down)throw Error('offline');calls.push(['close',r.id]);}};
 async function start(reset=false){
  db=await openDatabase({connectionString:process.env.TEST_DATABASE_URL,sqliteFile:join(dir,'rooms.sqlite')});
  if(reset&&process.env.TEST_DATABASE_URL){const u=new URL(process.env.TEST_DATABASE_URL);assert.ok(['localhost','127.0.0.1'].includes(u.hostname)&&u.pathname==='/tomi_test');await db.query('DELETE FROM tomi_users');await db.query('DELETE FROM tomi_rate_limits');}
  server=await createApp({database:db,storage,roomProvider:disabled?null:provider,roomAutoSweep:false,iceProvider:async()=>({}),callAutoSweep:false,pushAutoFlush:false,rateLimitMultiplier:50});
  server.listen(0,'127.0.0.1');await once(server,'listening');base='http://127.0.0.1:'+server.address().port;
 }
 async function stop(){const closed=once(server,'close');server.close();server.closeIdleConnections();await closed;await db.close();}
 await start(true);t.after(async()=>{await stop();await rm(dir,{recursive:true,force:true});});
 const api={get base(){return base;},get db(){return db;},get server(){return server;},calls,set down(v){down=v;},async restart(){await stop();await start();},
  async request(method,path,body,token){const r=await fetch(base+path,{method,headers:{...(body?{'content-type':'application/json'}:{}),...(token?{authorization:'Bearer '+token}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,data:await r.json()};},
  async register(name){const r=await this.request('POST','/v1/auth/register',{username:name,displayName:name,password:'test-only rooms passphrase'});assert.equal(r.status,201);return r.data;},
  async create(a,extra={}){const body={requestId:randomUUID(),title:'غرفة تومي',capacity:10,seatCount:4,tier:'advanced',acceptTerms:true,...extra};if(body.tier==='advanced'&&!(await db.query('SELECT 1 FROM tomi_voice_rooms WHERE id=?',[body.requestId])).rows.length){await this.request('GET','/v1/rooms/wallet',null,a.token);await db.query('UPDATE tomi_room_wallets SET coins=coins+5799 WHERE user_id=?',[a.user.id]);}const r=await this.request('POST','/v1/rooms',body,a.token);assert.equal(r.status,201,JSON.stringify(r.data));return r.data.room;},
  async act(a,r,action,body={}){return this.request('POST',`/v1/rooms/${r.id}/${action}`,body,a.token);},
  async get(a,r){return (await this.request('GET',`/v1/rooms/${r.id}`,null,a.token)).data.room;},
 };return api;
}
