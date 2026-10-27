import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {testFlags,testSummaryError} from '../tools/test_runner.mjs';
const flags=testFlags.map(x=>x.startsWith('--test-timeout=')?'--test-timeout=150':x);
const fixture=fileURLToPath(new URL('./fixtures/runner-lingering.mjs',import.meta.url));
for(const mode of ['failure','timeout'])test('1.3.1 CI runner reports '+mode+' and exits even with a listening test server',()=>{
 const r=spawnSync(process.execPath,[...flags,fixture],{env:{PATH:process.env.PATH??'',TOMI_RUNNER_FIXTURE:mode},encoding:'utf8',timeout:5000});
 assert.equal(r.error,undefined);assert.equal(r.status,1);
 assert.match(r.stdout+r.stderr,mode==='failure'?/TOMI_EXPECTED_FIXTURE_FAILURE/:/timed out|testTimeoutFailure/);
});

for(const failure of [false,true])test('1.4 CI report pipe preserves all verdicts and the final '+(failure?'failure':'pass')+' under backpressure',()=>{
 const flags=testFlags.filter(x=>!x.startsWith('--test-reporter=')).map(x=>x.startsWith('--test-timeout=')?'--test-timeout=5000':x);
 const reporter=fileURLToPath(new URL('./fixtures/runner-pressure-reporter.mjs',import.meta.url)),fixture=fileURLToPath(new URL('./fixtures/runner-output.mjs',import.meta.url));
 const r=spawnSync(process.execPath,[...flags,'--test-reporter='+reporter,fixture],{env:{PATH:process.env.PATH??'',...(failure?{TOMI_RUNNER_OUTPUT_FAILURE:'1'}:{})},encoding:'utf8',timeout:8000});
 assert.equal(r.error,undefined);assert.equal(r.status,failure?1:0);assert.match(r.stdout,new RegExp('TOMI_OUTPUT_COUNTS pass='+(failure?63:64)+' fail='+(failure?1:0)));
 if(failure)assert.match(r.stdout,/TOMI_EXPECTED_LAST_OUTPUT_FAILURE/);
});
test('1.4 incomplete or partial-success output cannot pass the APK completeness gate',()=>{
 assert.ok(testSummaryError('✔ last visible case passed\n',173));
 const summary=n=>`ℹ tests ${n}\nℹ pass ${n}\nℹ fail 0\nℹ cancelled 0\nℹ skipped 0\nℹ todo 0\nℹ duration_ms 1.5\n`;
 assert.ok(testSummaryError(summary(57),173));assert.equal(testSummaryError(summary(173),173),null);
 assert.ok(testSummaryError(summary(173).replace('ℹ skipped 0','ℹ skipped 1'),173));
});
