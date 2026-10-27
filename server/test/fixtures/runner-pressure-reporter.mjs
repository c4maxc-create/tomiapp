// Hold the runner's event loop briefly while its child fills the report pipe.
// It models a busy CI worker without stopping another process or leaking one.
export default async function* report(source){
 let paused=false,pass=0,fail=0;
 for await(const event of source){
  if(!paused&&event.type==='test:start'){paused=true;Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,300);}
  if(event.type==='test:pass')pass++;
  if(event.type==='test:fail'){fail++;yield 'ERROR '+(event.data.details?.error?.message??'unknown')+'\n';}
 }
 yield `TOMI_OUTPUT_COUNTS pass=${pass} fail=${fail}\n`;
}
