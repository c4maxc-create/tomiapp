// Invoked only by the runner regression test, outside the *.test.mjs glob.
import test from 'node:test';
await new Promise(resolve=>setTimeout(resolve,300));
for(let i=0;i<64;i++)test('output-'+i+' '+ 'x'.repeat(4096),()=>{
 if(i===63&&process.env.TOMI_RUNNER_OUTPUT_FAILURE==='1')throw Error('TOMI_EXPECTED_LAST_OUTPUT_FAILURE');
});
