import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {once} from 'node:events';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {openDatabase} from '../../src/database.mjs';
import {createApp} from '../../src/app.mjs';
import {iceFromEnvironment} from '../../src/ice.mjs';
const password='test-only moderation12 passphrase',connectionString=process.env.TEST_DATABASE_URL;
if(connectionString){const u=new URL(connectionString);assert.ok(['localhost','127.0.0.1'].includes(u.hostname)&&u.pathname==='/tomi_test','Use only local tomi_test');}
export async function fixture(t,options={}){
  const dir=await mkdtemp(join(tmpdir(),'tomi12-'));let db,server,base,ownerUserId=null,providerFails=false;
  const removed=[],provider={ensure:async()=>{},grant:async(r,m)=>({url:'wss://test.livekit.cloud',identity:m.identity,token:'test-only'}),permissions:async()=>{},remove:async(r,id)=>{if(providerFails)throw Error('Offline');removed.push(id);},close:async()=>{if(providerFails)throw Error('Offline');}};
  async function start(reset=false){db=await openDatabase({connectionString,sqliteFile:join(dir,'state.sqlite')});if(reset&&connectionString){await db.query('DELETE FROM tomi_users');await db.query('DELETE FROM tomi_game_matches');await db.query('DELETE FROM tomi_admin_audit');await db.query('DELETE FROM tomi_rate_limits');}server=await createApp({database:db,ownerUserId,roomProvider:provider,iceProvider:iceFromEnvironment({CALL_TURN_URLS:'turn:relay.example.com:3478',CALL_TURN_SECRET:'test-only-'.repeat(5)}),roomAutoSweep:false,callAutoSweep:false,pushAutoFlush:false,rateLimitMultiplier:100,...options});server.listen(0,'127.0.0.1');await once(server,'listening');base='http://127.0.0.1:'+server.address().port;}
  async function stop(){const done=once(server,'close');server.close();server.closeIdleConnections();await done;await db.close();}
  t.after(async()=>{if(server)await stop();else if(db)await db.close();await rm(dir,{recursive:true,force:true});});await start(true);
  return {get db(){return db;},get server(){return server;},get base(){return base;},removed,set providerFails(value){providerFails=value;},async restart(owner=ownerUserId){await stop();ownerUserId=owner;await start();},
    async req(a,method,path,body){const r=await fetch(base+path,{method,headers:{...(a?{authorization:'Bearer '+a.token}:{}),...(body!==undefined?{'content-type':'application/json'}:{})},...(body!==undefined?{body:JSON.stringify(body)}:{})});return {status:r.status,data:await r.json()};},
    async register(username){const r=await this.req(null,'POST','/v1/auth/register',{username,displayName:username,password});assert.equal(r.status,201);return r.data;},
    async post(a){const r=await this.req(a,'POST','/v1/posts',{text:'نص بلاغ اختبار خاص',requestId:randomUUID()});assert.equal(r.status,201);return r.data.post;},
    async report(a,type,targetId,extra={}){return this.req(a,'POST','/v1/reports',{requestId:randomUUID(),targetType:type,targetId,reason:'harassment',description:'وصف خاص للبلاغ',...extra});},
    async command(a,action,targetId,extra={}){return this.req(a,'POST','/v1/admin/actions',{requestId:randomUUID(),action,targetId,reason:'سبب اختبار إجراء الإدارة',expectedRevision:0,...extra});},
    async create(a){await this.req(a,'GET','/v1/rooms/wallet');await db.query('UPDATE tomi_room_wallets SET coins=coins+5799 WHERE user_id=?',[a.user.id]);const r=await this.req(a,'POST','/v1/rooms',{title:'غرفة اختبار الإدارة',requestId:randomUUID(),capacity:10,seatCount:4,tier:'advanced',acceptTerms:true});assert.equal(r.status,201);return r.data.room;},
    async auditCount(){return Number((await db.query('SELECT COUNT(*) n FROM tomi_admin_audit')).rows[0].n);},
  };
}
export async function people(f){const owner=await f.register('owner12'),member=await f.register('member12'),mod=await f.register('moderator12');await f.restart(owner.user.id);return {owner,member,mod};}

export {password};
