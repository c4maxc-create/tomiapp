import {mkdtemp,open,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,isAbsolute} from 'node:path';
import {spawn} from 'node:child_process';
import {ApiError} from './security.mjs';
// Disabled until a real scanner + signature updater are installed. Configured failures reject uploads.
export function mediaScanner(binary){
 if(!binary)return null;if(!isAbsolute(binary))throw Error('TOMI_CLAMSCAN_BINARY must be an absolute executable path');
 return {async begin(){
  const dir=await mkdtemp(join(tmpdir(),'tomi-scan-')),path=join(dir,'upload'),handle=await open(path,'wx',0o600);let closed=false,bytes=0;
  async function close(){if(!closed){closed=true;await handle.close();}}
  return {async write(chunk){bytes+=chunk.length;if(bytes>160*1024*1024)throw new ApiError(413,'TOO_LARGE','الملف أكبر من المسموح.');await handle.writeFile(chunk);},
   async finish(){await close();
    const code=await new Promise(resolve=>{let done=false;const child=spawn(binary,['--no-summary','--stdout','--max-filesize=160M','--max-scansize=160M','--max-files=1000','--max-recursion=16','--alert-exceeds-max=yes','--alert-encrypted=yes',path],{shell:false,env:{PATH:'/usr/bin:/bin',LANG:'C'},stdio:['ignore','ignore','ignore']});const timer=setTimeout(()=>{child.kill('SIGKILL');finish(-1);},45000);timer.unref();function finish(value){if(done)return;done=true;clearTimeout(timer);resolve(value);}child.on('error',()=>finish(-1));child.on('close',code=>finish(code));});
    if(code===1)throw new ApiError(400,'UNSAFE_FILE','تعذّر قبول الملف لأنه غير آمن.');if(code!==0)throw new ApiError(503,'SCAN_UNAVAILABLE','فحص أمان الملف غير متاح؛ حاول لاحقاً.');
   },async abort(){await close().catch(()=>{});await rm(dir,{recursive:true,force:true});}};
 }};
}
