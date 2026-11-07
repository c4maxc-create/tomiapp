import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign,randomBytes,randomUUID} from 'node:crypto';
import {createFirebaseVerifier} from '../src/firebase_identity.mjs';
import {fixture,password} from './fixtures/platform-api.mjs';
import {totp} from '../src/mfa.mjs';
function issuer(){const pair=generateKeyPairSync('rsa',{modulusLength:2048}),project='tomi-test42';let hits=0;const verifier=createFirebaseVerifier({projectId:project,fetcher:async()=>{hits++;return new Response(JSON.stringify({testkey:pair.publicKey.export({type:'spki',format:'pem'})}),{headers:{'cache-control':'max-age=3600'}});}});
 const issue=(extra={},header={})=>{const time=Math.floor(Date.now()/1000),payload={iss:`https://securetoken.google.com/${project}`,aud:project,sub:'google-uid-1',iat:time,exp:time+3600,auth_time:time,firebase:{sign_in_provider:'google.com'},name:'Test name',...extra};const a=Buffer.from(JSON.stringify({alg:'RS256',kid:'testkey',typ:'JWT',...header})).toString('base64url'),b=Buffer.from(JSON.stringify(payload)).toString('base64url');return a+'.'+b+'.'+sign('RSA-SHA256',Buffer.from(a+'.'+b),pair.privateKey).toString('base64url');};return {verifier,issue,get hits(){return hits;}};}
test('42 Firebase proof requires Google-signed RS256, exact project/issuer, recent auth and an allowed nonanonymous provider',async()=>{
 const i=issuer();assert.equal((await i.verifier.verify(i.issue())).subject,'google-uid-1');
 assert.equal((await i.verifier.verify(i.issue({firebase:{sign_in_provider:'phone'},phone_number:'+9647701234567'}))).provider,'phone');assert.equal((await i.verifier.verify(i.issue({firebase:{sign_in_provider:'apple.com'}}))).provider,'apple.com');
 for(const extra of [{aud:'another-project'},{iss:'https://attacker.test'},{exp:1},{auth_time:1},{auth_time:Math.floor(Date.now()/1000)+300},{firebase:{sign_in_provider:'custom'}},{firebase:{sign_in_provider:'anonymous'}},{firebase:{sign_in_provider:'phone'},phone_number:'invalid'}])await assert.rejects(i.verifier.verify(i.issue(extra)),e=>e.code==='IDENTITY_INVALID');
 await assert.rejects(i.verifier.verify(i.issue({}, {alg:'HS256'})));await assert.rejects(i.verifier.verify(i.issue({}, {jku:'https://attacker.test/keys'})));assert.equal(i.hits,1);
 const v=createFirebaseVerifier({projectId:'tomi-test42',enabledProviders:[],fetcher:async()=>new Response('{}')});assert.deepEqual(v.providers,[]);
});
test('42 external identities are separate despite the same email; only confirmed linking joins the same TOMI account and MFA cannot be bypassed',async t=>{
 const i=issuer(),f=await fixture(t,{firebaseVerifier:i.verifier,mfaEncryptionKey:randomBytes(32)});
 const token=i.issue({email:'same@example.test'}),tokenB=i.issue({sub:'different-uid',email:'same@example.test',firebase:{sign_in_provider:'facebook.com'}});
 const a=(await f.req(null,'POST','/v1/auth/federated',{identityToken:token})).data,b=(await f.req(null,'POST','/v1/auth/federated',{identityToken:tokenB})).data;assert.ok(a.token);assert.notEqual(a.user.id,b.user.id);
 assert.equal((await f.req(null,'POST','/v1/auth/federated',{identityToken:token})).data.user.id,a.user.id);
 const local=await f.register('link_local42');assert.equal((await f.req(local,'POST','/v1/me/auth/link',{password:'wrong',identityToken:token})).status,400);
 assert.equal((await f.req(local,'POST','/v1/me/auth/link',{password,identityToken:token})).data.error.code,'IDENTITY_ALREADY_LINKED');
 const third=i.issue({sub:'new-third-uid',email:'same@example.test'});assert.equal((await f.req(local,'POST','/v1/me/auth/link',{password,identityToken:third})).status,200);assert.equal((await f.req(null,'POST','/v1/auth/federated',{identityToken:third})).data.user.id,local.user.id);

 const otherLocal=await f.register('link_racing42'),contested=i.issue({sub:'contested-proof'});
 const racing=await Promise.all([f.req(local,'POST','/v1/me/auth/link',{password,identityToken:contested}),f.req(otherLocal,'POST','/v1/me/auth/link',{password,identityToken:contested})]);assert.deepEqual(racing.map(r=>r.status).sort(),[200,409]);
 assert.equal((await f.req(a,'GET','/v1/me/auth/methods')).data.hasPassword,false);
 assert.equal((await f.req(a,'POST','/v1/me/security/setup',{identityToken:tokenB})).status,403);
 const setup=await f.req(a,'POST','/v1/me/security/setup',{identityToken:token});assert.equal(setup.status,200);
 const enabled=await f.req(a,'POST','/v1/me/security/enable',{code:totp(setup.data.secret,Math.floor(Date.now()/30000))});assert.equal(enabled.status,200);
 assert.equal((await f.req(null,'POST','/v1/auth/federated',{identityToken:token})).data.error.code,'MFA_REQUIRED');
 assert.equal((await f.req(null,'POST','/v1/auth/federated',{identityToken:token,mfaCode:enabled.data.recoveryCodes[0]})).status,200);
 const receipt={requestId:randomUUID(),receiptToken:randomBytes(32).toString('base64url'),confirmation:'حذف حسابي',password:'',identityToken:tokenB};assert.equal((await f.req(b,'POST','/v1/account/deletion',receipt)).status,202);assert.equal(Number((await f.db.query('SELECT COUNT(*) n FROM tomi_external_identities WHERE user_id=?',[b.user.id])).rows[0].n),0);
});
