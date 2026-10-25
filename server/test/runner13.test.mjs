import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const script=JSON.parse(await readFile(new URL('../package.json',import.meta.url),'utf8')).scripts.test;
const [command,...words]=script.split(/\s+/);assert.equal(command,'node');
const flags=words.filter(x=>x.startsWith('--')).map(x=>x.startsWith('--test-timeout=')?'--test-timeout=150':x);
const fixture=fileURLToPath(new URL('./fixtures/runner-lingering.mjs',import.meta.url));
for(const mode of ['failure','timeout'])test('1.3.1 CI runner reports '+mode+' and exits even with a listening test server',()=>{
 const r=spawnSync(process.execPath,[...flags,fixture],{env:{PATH:process.env.PATH??'',TOMI_RUNNER_FIXTURE:mode},encoding:'utf8',timeout:5000});
 assert.equal(r.error,undefined);assert.equal(r.status,1);
 assert.match(r.stdout+r.stderr,mode==='failure'?/TOMI_EXPECTED_FIXTURE_FAILURE/:/timed out|testTimeoutFailure/);
});
