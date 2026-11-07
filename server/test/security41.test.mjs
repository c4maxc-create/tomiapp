import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {fixture,password} from './fixtures/platform-api.mjs';
import {base32,totp,mfaKey,seal,unseal} from '../src/mfa.mjs';
import {mediaScanner} from '../src/media_scanner.mjs';
import {verifyDocumentSignature} from '../src/document_security.mjs';
import {mkdtemp,writeFile,readdir,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
const nowCode=s=>totp(s,Math.floor(Date.now()/30000));
test('41 TOTP matches all six RFC6238 SHA1 vectors and rejects malformed server keys',()=>{
 const secret=base32(Buffer.from('12345678901234567890'));
 for(const [time,expected] of [[59,'94287082'],[1111111109,'07081804'],[1111111111,'14050471'],[1234567890,'89005924'],[2000000000,'69279037'],[20000000000,'65353130']])assert.equal(totp(secret,Math.floor(time/30),{digits:8}),expected);
 assert.throws(()=>mfaKey('bad'));assert.equal(mfaKey(randomBytes(32).toString('base64')).length,32);const key=randomBytes(32),encrypted=seal(secret,key,'user-a');assert.equal(unseal(encrypted,key,'user-a'),secret);assert.throws(()=>unseal(encrypted,key,'user-b'));assert.notEqual(encrypted,seal(secret,key,'user-a'));
});
test('41 MFA enrollment, replay prevention, encrypted seeds, one-use backup codes and admin step-up',async t=>{
 const f=await fixture(t,{mfaEncryptionKey:randomBytes(32)}),a=await f.register('mfa41');await f.restart(a.user.id);
 assert.equal((await f.req(a,'POST','/v1/me/security/setup',{password:'wrong'})).status,400);
 const setup=await f.req(a,'POST','/v1/me/security/setup',{password});assert.equal(setup.status,200);const secret=setup.data.secret;
 const stored=(await f.db.query('SELECT secret FROM tomi_mfa WHERE user_id=?',[a.user.id])).rows[0].secret;assert.ok(!stored.includes(secret));
 assert.equal((await f.req(a,'POST','/v1/me/security/enable',{code:'bad'})).status,400);
 const enableCode=nowCode(secret);const enabled=await f.req(a,'POST','/v1/me/security/enable',{code:enableCode});assert.equal(enabled.status,200);assert.equal(enabled.data.recoveryCodes.length,10);assert.equal((await f.req(a,'POST','/v1/me/security/verify',{code:'bad'})).status,400);assert.equal((await f.req(a,'GET','/v1/me')).status,200);
 const code=enabled.data.recoveryCodes[0];
 assert.equal((await f.req(null,'POST','/v1/auth/login',{username:'mfa41',password})).data.error.code,'MFA_REQUIRED');
 assert.equal((await f.req(null,'POST','/v1/auth/login',{username:'mfa41',password,mfaCode:enableCode})).status,401);
 const login=await f.req(null,'POST','/v1/auth/login',{username:'mfa41',password,mfaCode:code});assert.equal(login.status,200);
 assert.equal((await f.req(null,'POST','/v1/auth/login',{username:'mfa41',password,mfaCode:code})).status,401);
 const logged=login.data;assert.equal((await f.req(logged,'GET','/v1/admin/metrics')).status,200);
 await f.db.query("UPDATE tomi_mfa_sessions SET verified_at='2000-01-01T00:00:00.000Z'");
 assert.equal((await f.req(logged,'GET','/v1/admin/metrics')).data.error.code,'MFA_STEP_UP');
 assert.equal((await f.req(logged,'POST','/v1/me/security/verify',{code:enabled.data.recoveryCodes[1]})).status,200);
 assert.equal((await f.req(logged,'GET','/v1/admin/metrics')).status,200);
 assert.equal((await f.req(null,'POST','/v1/auth/recover',{username:'mfa41',password,recoveryCode:a.recoveryCode})).data.error.code,'MFA_REQUIRED');
 assert.equal((await f.req(logged,'POST','/v1/me/security/disable',{password,code:enabled.data.recoveryCodes[2]})).status,200);
 assert.equal((await f.req(null,'POST','/v1/auth/login',{username:'mfa41',password})).status,200);
});
test('41 configured mandatory admin MFA prevents admin access until enrollment; other users cannot read security events',async t=>{
 const f=await fixture(t,{requireAdminMfa:true,mfaEncryptionKey:randomBytes(32)}),a=await f.register('require41'),b=await f.register('other41');await f.restart(a.user.id);
 assert.equal((await f.req(a,'GET','/v1/admin/metrics')).data.error.code,'MFA_ENROLL_REQUIRED');
 assert.equal((await f.req(b,'GET','/v1/me/security')).data.events.length,0);
 assert.equal((await f.req(b,'GET','/v1/admin/metrics')).status,403);
});
test('41 configured edge protection denies origin bypass and accepts proxy-injected secret without exposing it',async t=>{
 const secret=randomBytes(32).toString('base64url'),f=await fixture(t,{edgeSecret:secret});
 assert.equal((await fetch(f.base+'/health')).status,200);
 assert.equal((await fetch(f.base+'/v1/me')).status,403);
 assert.equal((await fetch(f.base+'/v1/me',{headers:{'x-tomi-edge':secret}})).status,401);
 assert.equal((await fetch(f.base+'/v1/me',{headers:{'x-tomi-edge':'fake'}})).status,403);
});
test('41 document magic rejects renamed executables and accepts matching PDF, text and ZIP containers',()=>{
 for(const [content,name] of [['MZfake','a.pdf'],['not pdf','a.pdf'],['hello','a.zip'],['#! /bin/sh','a.txt']])assert.throws(()=>verifyDocumentSignature(Buffer.from(content),name));
 for(const [content,name] of [[Buffer.from('%PDF-1.4'),'a.pdf'],[Buffer.from('hello'),'a.txt'],[Buffer.from('504b0304','hex'),'a.docx']])assert.doesNotThrow(()=>verifyDocumentSignature(content,name));
});
test('41 configured scanner rejects infected and failed scans and cleans private temporary files',async t=>{
 const dir=await mkdtemp(join(tmpdir(),'tomi-scanner-test-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 for(const [code,error] of [[0,null],[1,'UNSAFE_FILE'],[2,'SCAN_UNAVAILABLE']]){
  const binary=join(dir,'scan'+code);await writeFile(binary,'#!/bin/sh\nexit '+code+'\n',{mode:0o700});const scan=await mediaScanner(binary).begin();await scan.write(Buffer.from('test bytes'));
  if(error)await assert.rejects(scan.finish(),e=>e.code===error);else await scan.finish();await scan.abort();
 }
 assert.equal(mediaScanner(null),null);assert.throws(()=>mediaScanner('relative'));assert.equal((await readdir(dir)).length,3);
});
test('41 edge proxy preserves the configured origin and overwrites forged forwarding headers',async()=>{
 const {forward}=await import('../../ops/cloudflare/worker.mjs');let observed;
 const env={TOMI_ORIGIN:'https://origin.example.test',TOMI_PUBLIC_HOST:'api.example.test',TOMI_EDGE_SECRET:'test-only-edge'};
 const r=await forward(new Request('https://api.example.test//attacker.test/v1/me?x=1',{method:'POST',headers:{'x-tomi-edge':'forged','x-forwarded-for':'forged','cf-connecting-ip':'192.0.2.9'},body:'{}'}),env,async request=>{observed=request;return new Response('ok');});
 assert.equal(r.status,200);assert.equal(new URL(observed.url).host,'origin.example.test');assert.equal(observed.redirect,'manual');assert.equal(observed.headers.get('x-tomi-edge'),'test-only-edge');assert.equal(observed.headers.get('x-forwarded-for'),'192.0.2.9');assert.equal(observed.headers.get('x-tomi-client-ip'),'192.0.2.9');assert.equal(await observed.text(),'{}');
 assert.equal((await forward(new Request('https://evil.example.test/v1/me'),env)).status,403);
 const free={...env,TOMI_PUBLIC_HOST:''};let originCalls=0,authCalls=0;
 free.API_RATE={limit:async({key})=>{assert.match(key,/^[a-f0-9]{64}$/);return {success:true};}};
 free.AUTH_RATE={limit:async()=>{authCalls++;return {success:false};}};
 const upstream=async()=>{originCalls++;return new Response('ok');};
 assert.equal((await forward(new Request('https://tomi-test.example.workers.dev/v1/me'),free,upstream)).status,200);
 assert.equal((await forward(new Request('https://tomi-test.example.workers.dev/v1/auth/federated',{method:'POST',body:'{}'}),free,upstream)).status,429);
 assert.equal(authCalls,1);assert.equal(originCalls,1);
 assert.equal((await forward(new Request('https://tomi-test.example.workers.dev/v1/me',{headers:{'content-length':'1048577'}}),free,upstream)).status,413);
 assert.equal((await forward(new Request('http://tomi-test.example.workers.dev/v1/me'),free,upstream)).status,403);
 assert.equal((await forward(new Request('https://tomi-test.example.workers.dev/other',{headers:{upgrade:'websocket'}}),free,upstream)).status,403);
 assert.equal(originCalls,1);

});
