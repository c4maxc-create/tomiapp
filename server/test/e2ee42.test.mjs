import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,randomBytes,randomUUID,sign} from 'node:crypto';
import {fixture,password} from './fixtures/platform-api.mjs';
import {deviceProof,keyProof,packetProof} from '../src/e2ee.mjs';
import {digest} from '../src/security.mjs';
const raw=bytes=>bytes.toString('base64').replace(/=+$/,'');
function device(a){const keys=generateKeyPairSync('ed25519'),d={id:randomUUID(),signingKey:raw(keys.publicKey.export({type:'spki',format:'der'}).subarray(-32)),identityKey:raw(randomBytes(32)),label:'Test native device'};return {d,sign:text=>raw(sign(null,Buffer.from(text),keys.privateKey)),a};}
async function enroll(f,a){const v=device(a),challenge=(await f.req(a,'POST','/v1/me/secure/challenge',{})).data.challenge,k={id:raw(randomBytes(8)),key:raw(randomBytes(32))};k.signature=v.sign(keyProof(a.user.id,v.d.id,k));v.k=k;const response=await f.req(a,'POST','/v1/me/secure/devices',{...v.d,challenge,signature:v.sign(deviceProof(a.user.id,v.d,challenge)),password,prekeys:[k],fallback:k});assert.equal(response.status,200,JSON.stringify(response));return v;}
function packet(v,tid,roster){const boxes=roster.devices.map(d=>({deviceId:d.id,type:d.id===v.d.id?2:0,body:Buffer.from('opaque encrypted packet').toString('base64')}));const d={deviceId:v.d.id,requestId:randomUUID(),rosterHash:roster.rosterHash,boxes};d.signature=v.sign(packetProof(v.a.user.id,d,tid,digest(JSON.stringify(boxes))));return d;}
test('42 signed devices and claims cannot cross accounts; opaque packets are idempotent, private, deleted and reject legacy plaintext',async t=>{
 const f=await fixture(t),a=await f.register('e2ee_alice42'),b=await f.register('e2ee_bob42'),c=await f.register('e2ee_third42');const tid=(await f.req(a,'POST','/v1/chats',{userId:b.user.id})).data.conversation.id;
 const va=await enroll(f,a),vb=await enroll(f,b);let r=(await f.req(a,'GET',`/v1/chats/${tid}/secure/devices`)).data;assert.equal(r.devices.length,2);
 assert.equal((await f.req(c,'GET',`/v1/chats/${tid}/secure/devices`)).status,404);
 const claim={deviceId:va.d.id,requestId:randomUUID()};claim.signature=va.sign(`TOMI_CLAIM_V1|${a.user.id}|${va.d.id}|${tid}|${vb.d.id}|${claim.requestId}`);
 const key=(await f.req(a,'POST',`/v1/chats/${tid}/secure/claim/${vb.d.id}`,claim)).data;assert.equal(key.key,vb.k.key);assert.deepEqual((await f.req(a,'POST',`/v1/chats/${tid}/secure/claim/${vb.d.id}`,claim)).data,key);
 const enable={deviceId:va.d.id,rosterHash:r.rosterHash,signature:va.sign(`TOMI_ENABLE_V1|${a.user.id}|${va.d.id}|${tid}|${r.rosterHash}`)};assert.equal((await f.req(a,'POST',`/v1/chats/${tid}/secure/enable`,enable)).status,200);
 const body=packet(va,tid,r),first=await f.req(a,'POST',`/v1/chats/${tid}/secure/messages`,body);assert.equal(first.status,201,JSON.stringify(first));assert.deepEqual((await f.req(a,'POST',`/v1/chats/${tid}/secure/messages`,body)).data,first.data);
 assert.equal((await f.req(a,'POST',`/v1/chats/${tid}/messages`,{text:'not encrypted',requestId:randomUUID()})).data.error.code,'SECURE_REQUIRED');
 assert.equal((await f.req(a,'POST','/v1/chats',{userId:b.user.id})).data.conversation.secureEnabled,true);
 const received=await f.req(b,'GET',`/v1/chats/${tid}/secure/messages?deviceId=${vb.d.id}`);assert.equal(received.data.messages[0].box.body,body.boxes.find(x=>x.deviceId===vb.d.id).body);
 assert.equal((await f.req(c,'GET',`/v1/chats/${tid}/secure/messages?deviceId=${vb.d.id}`)).status,403);
 const changed={...body,boxes:body.boxes.map(x=>({...x,body:'QUFBQQ=='}))};assert.equal((await f.req(a,'POST',`/v1/chats/${tid}/secure/messages`,changed)).status,403);
 assert.equal((await f.req(a,'PUT',`/v1/chats/${tid}/messages/${first.data.id}/edit`,{text:'unsafe edit',expectedRevision:0})).data.error.code,'SECURE_REQUIRED');
 assert.equal((await f.req(a,'DELETE',`/v1/chats/${tid}/messages/${first.data.id}`)).status,200);assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_e2ee_envelopes WHERE message_id=?',[first.data.id])).rows[0].n),0);
 assert.deepEqual((await f.req(b,'POST',`/v1/chats/${tid}/secure/status`,{deviceId:vb.d.id,ids:[first.data.id]})).data.deletedIds,[first.data.id]);
 assert.equal((await f.req(b,'DELETE',`/v1/me/secure/devices/${va.d.id}`,{password})).status,404);
 assert.equal((await f.req(a,'DELETE',`/v1/me/secure/devices/${va.d.id}`,{password})).status,200);
 assert.equal((await f.req(a,'POST',`/v1/chats/${tid}/secure/messages`,body)).status,403);
});
