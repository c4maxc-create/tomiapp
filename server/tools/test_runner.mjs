import {spawn} from 'node:child_process';
import {readFile,readdir} from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {resolve} from 'node:path';

const root=fileURLToPath(new URL('../',import.meta.url));
export const testFlags=[
 '--import='+fileURLToPath(new URL('../test/sync_stdio.mjs',import.meta.url)),
 '--test','--test-concurrency=1','--test-timeout=60000','--test-force-exit','--test-reporter=spec',
];
export function testSummaryError(output,expected){
 const counts={};
 for(const name of ['tests','pass','fail','cancelled','skipped','todo']){
  const match=output.replaceAll('\r','').match(new RegExp('^ℹ '+name+' (\\d+)\\s*$','m'));
  if(!match)return 'The final test summary is missing or incomplete.';
  counts[name]=Number(match[1]);
 }
 if(!/^ℹ duration_ms \d+(?:\.\d+)?\s*$/m.test(output.replaceAll('\r','')))return 'The final test duration is missing.';
 if(counts.tests!==expected||counts.pass!==expected||counts.fail||counts.cancelled||counts.skipped||counts.todo)return `Expected ${expected} completed passes; received tests=${counts.tests}, pass=${counts.pass}, fail=${counts.fail}, cancelled=${counts.cancelled}, skipped=${counts.skipped}, todo=${counts.todo}.`;
 return null;
}
async function main(){
 if(process.argv.length!==2)throw Error('npm test runs the complete suite; use node --test explicitly for a targeted diagnostic.');
 const {expectedTests}=JSON.parse(await readFile(new URL('./test-suite.json',import.meta.url),'utf8'));
 if(!Number.isSafeInteger(expectedTests)||expectedTests<1)throw Error('Invalid test suite count.');
 const files=(await readdir(new URL('../test/',import.meta.url))).filter(n=>n.endsWith('.test.mjs')).sort().map(n=>'test/'+n);
 const child=spawn(process.execPath,[...testFlags,...files],{cwd:root,env:{...process.env,FORCE_COLOR:'0',NODE_DISABLE_COLORS:'1'},stdio:['ignore','pipe','pipe']});
 let tail='',spawnError;
 child.stdout.setEncoding('utf8');child.stdout.on('data',chunk=>tail=(tail+chunk).slice(-65536));
 child.stdout.pipe(process.stdout,{end:false});child.stderr.pipe(process.stderr,{end:false});
 child.on('error',error=>spawnError=error);
 const forward=signal=>child.kill(signal);
 const interrupt=()=>forward('SIGINT'),terminate=()=>forward('SIGTERM');
 process.on('SIGINT',interrupt);process.on('SIGTERM',terminate);
 const {code,signal}=await new Promise(resolve=>child.once('close',(code,signal)=>resolve({code,signal})));
 process.off('SIGINT',interrupt);process.off('SIGTERM',terminate);
 if(spawnError||signal||code!==0){process.exitCode=code||1;return;}
 const error=testSummaryError(tail,expectedTests);
 if(error){console.error('TOMI test completeness failed: '+error);process.exitCode=1;return;}
 console.log(`TOMI test completeness verified: ${expectedTests}/${expectedTests} passed; no failed, cancelled or skipped tests.`);
}
if(process.argv[1]&&pathToFileURL(resolve(process.argv[1])).href===import.meta.url)main().catch(()=>{console.error('TOMI test runner failed; APK build must remain blocked.');process.exitCode=1;});
