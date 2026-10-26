import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,generateKeyPairSync,verify} from 'node:crypto';
import {TokenVerifier} from 'livekit-server-sdk';
import {roomProviderFromEnvironment} from '../src/room_provider.mjs';
import {fcmFromEnvironment} from '../src/push.mjs';
import {fixture} from './fixtures/room-api.mjs';

test('1.3.2 complete standard LiveKit settings grant audio tokens; incomplete mixed groups are refused',async()=>{
 const env={LIVEKIT_URL:'wss://test.livekit.cloud',LIVEKIT_API_KEY:'test132',LIVEKIT_API_SECRET:'s'.repeat(40)};
 const provider=roomProviderFromEnvironment(env,{client:{}}),room={id:randomUUID()},member={identity:randomUUID(),seat:null,mic_allowed:0};
 const d=await provider.grant(room,member),claims=await new TokenVerifier(env.LIVEKIT_API_KEY,env.LIVEKIT_API_SECRET).verify(d.token);
 assert.equal(d.url,env.LIVEKIT_URL);assert.equal(claims.sub,member.identity);assert.equal(claims.video.canPublish,false);
 assert.throws(()=>roomProviderFromEnvironment({...env,ROOM_LIVEKIT_URL:'wss://other.livekit.cloud'}));
});
test('1.3.2 common Firebase server credential alias signs a real OAuth request and sends a private generic notification',async()=>{
 const {privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:2048});let sent;
 const sender=fcmFromEnvironment({FIREBASE_SERVICE_ACCOUNT_JSON:JSON.stringify({type:'service_account',project_id:'tomi-test-project',client_email:'service@tomi-test-project.iam.gserviceaccount.com',private_key:privateKey.export({type:'pkcs8',format:'pem'})})},{fetcher:async(url,opts)=>{
  if(url.includes('oauth2')){const parts=opts.body.get('assertion').split('.');assert.ok(verify('RSA-SHA256',Buffer.from(parts.slice(0,2).join('.')),publicKey,Buffer.from(parts[2],'base64url')));return Response.json({access_token:'test-only-oauth',expires_in:3600});}
  sent=JSON.parse(opts.body).message;return Response.json({name:'sent'});
 }});
 assert.equal(await sender({token:'test-only',threadId:randomUUID(),recipientId:randomUUID()}),'sent');
 assert.equal(sent.data.type,'chat');assert.equal(sent.notification.body,'وصلتك رسالة جديدة في TOMI');
 assert.throws(()=>fcmFromEnvironment({FCM_SERVICE_ACCOUNT_JSON:'bad',FIREBASE_SERVICE_ACCOUNT_JSON:'{}'}));
});
test('1.3.2 disabled audio service refuses advanced creation before coins or rooms can change',async t=>{
 const api=await fixture(t,{disabled:true}),user=await api.register('unready132');
 const health=(await api.request('GET','/health')).data;assert.equal(health.features.voiceRooms,false);assert.equal(health.features.phoneNotifications,false);
 const result=await api.request('POST','/v1/rooms',{requestId:randomUUID(),title:'غرفة تجريبية',capacity:20,seatCount:8,tier:'advanced',acceptTerms:true},user.token);
 assert.equal(result.status,503);assert.equal(result.data.error.code,'ROOMS_DISABLED');
 assert.equal(Number((await api.db.query('SELECT COUNT(*) n FROM tomi_voice_rooms')).rows[0].n),0);
 assert.equal(Number((await api.db.query('SELECT COUNT(*) n FROM tomi_room_wallets')).rows[0].n),0);
});
