// Intentionally failing child fixture; never selected by the normal test glob.
import test from 'node:test';
import {createServer} from 'node:http';
test('intentional diagnostic failure',async()=>{
 createServer((q,r)=>r.end()).listen(0,'127.0.0.1');
 if(process.env.TOMI_RUNNER_FIXTURE==='timeout')await new Promise(()=>{});
 throw Error('TOMI_EXPECTED_FIXTURE_FAILURE');
});
