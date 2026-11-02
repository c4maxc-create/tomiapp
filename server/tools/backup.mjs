import {spawn} from 'node:child_process';
import {Readable} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {createReadStream} from 'node:fs';
import {mkdtemp,writeFile,rm,access} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,isAbsolute,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {backupKey,encryptBackup,decryptBackup,fileDigest} from '../src/backup_crypto.mjs';

export function databaseTarget(value,{restore=false}={}){
  let u;try{u=new URL(value);}catch{throw Error('A PostgreSQL connection URL is required');}
  if(!['postgres:','postgresql:'].includes(u.protocol)||u.hash||!u.hostname||!u.username||!u.pathname||u.pathname==='/')throw Error('Invalid PostgreSQL connection URL');
  if([...u.searchParams.keys()].some(k=>!['sslmode','sslrootcert'].includes(k)))throw Error('Unsupported connection options');
  const data={host:u.hostname,port:u.port||'5432',database:decodeURIComponent(u.pathname.slice(1)),user:decodeURIComponent(u.username),password:decodeURIComponent(u.password),local:['localhost','127.0.0.1'].includes(u.hostname)};
  if(Object.values(data).some(v=>typeof v==='string'&&/[\r\n\0]/.test(v)))throw Error('Connection fields contain invalid characters');
  if(restore&&(!data.local||data.database!=='tomi_restore_check'))throw Error('Restore is restricted to localhost/tomi_restore_check');
  return data;
}
const passPart=value=>value.replace(/[\\:]/g,c=>'\\'+c);
export async function postgresEnvironment(value,directory,{restore=false}={}){
  const target=databaseTarget(value,{restore}),passfile=join(directory,'pgpass');
  await writeFile(passfile,[target.host,target.port,target.database,target.user,target.password].map(passPart).join(':')+'\n',{flag:'wx',mode:0o600});
  // Do not forward API secrets or the encryption key into child processes.
  const env={PATH:process.env.PATH??'',PGHOST:target.host,PGPORT:target.port,PGDATABASE:target.database,PGUSER:target.user,PGPASSFILE:passfile,PGCONNECT_TIMEOUT:'10',PGAPPNAME:'tomi-backup12',PGSSLMODE:target.local?'disable':'verify-full'};
  if(!target.local)env.PGSSLROOTCERT=process.env.TOMI_BACKUP_SSLROOTCERT||'system';
  return {target,env};
}
function child(command,args,env){
  const p=spawn(command,args,{env,stdio:['pipe','pipe','pipe'],shell:false});
  const done=new Promise(resolve=>{p.once('error',()=>resolve({failed:true}));p.once('close',(code,signal)=>resolve({failed:code!==0||!!signal}));});
  let warnings=false;p.stderr.on('data',()=>{warnings=true;});
  const timer=setTimeout(()=>p.kill('SIGTERM'),600000);timer.unref();
  done.then(()=>clearTimeout(timer));return {p,done,get warnings(){return warnings;}};
}
async function requireAbsent(path){try{await access(path);}catch(e){if(e.code==='ENOENT')return;throw e;}throw Error('Output already exists; choose a new filename');}
export async function createPostgresBackup({connectionString,output,key,dumpBinary=process.env.TOMI_PG_DUMP_BIN||'pg_dump'}){
  if(!isAbsolute(output))throw Error('Use an absolute backup output path');
  await requireAbsent(output);await requireAbsent(output+'.json');
  const directory=await mkdtemp(join(tmpdir(),'tomi-backup12-'));let processState;
  try{
    const {env}=await postgresEnvironment(connectionString,directory);
    processState=child(dumpBinary,['--format=custom','--no-acl','--no-password'],env);processState.p.stdin.end();
    async function* stream(){
      for await(const chunk of processState.p.stdout)yield chunk;
      if((await processState.done).failed)throw Error('pg_dump failed; check installed PostgreSQL client version and access');
    }
    const result=await encryptBackup(Readable.from(stream()),output,key);
    const manifest={...result,schemaVersion:'1.7.0-beta.1',payload:'pg_dump-custom',hasClientWarnings:processState.warnings};
    await writeFile(output+'.json',JSON.stringify(manifest,null,2)+'\n',{flag:'wx',mode:0o600});return manifest;
  }finally{
    if(processState?.p.exitCode===null)processState.p.kill('SIGTERM');
    await rm(directory,{recursive:true,force:true});
  }
}
export async function assertEmptyRestoreTarget(connectionString){
  databaseTarget(connectionString,{restore:true});
  const {Client}=await import('pg'),client=new Client({connectionString,ssl:false,connectionTimeoutMillis:10000});
  await client.connect();
  try{
    const r=await client.query("SELECT (SELECT COUNT(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname NOT IN('pg_catalog','information_schema') AND n.nspname NOT LIKE 'pg_toast%')+(SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname NOT IN('pg_catalog','information_schema')) AS total");
    if(Number(r.rows[0].total)!==0)throw Error('Restore target is not empty');
  }finally{await client.end();}
}
export async function restorePostgresCheck({connectionString,input,key,confirmed=false,restoreBinary=process.env.TOMI_PG_RESTORE_BIN||'pg_restore'}){
  databaseTarget(connectionString,{restore:true});if(!confirmed)throw Error('Explicit --confirm-empty-local is required');
  const directory=await mkdtemp(join(tmpdir(),'tomi-restore12-'));let state;
  try{
    const dump=join(directory,'authenticated.dump');await decryptBackup(input,dump,key);
    await assertEmptyRestoreTarget(connectionString);
    const {env,target}=await postgresEnvironment(connectionString,directory,{restore:true});
    state=child(restoreBinary,['--dbname='+target.database,'--single-transaction','--exit-on-error','--no-owner','--no-acl','--no-password'],env);
    state.p.stdout.resume();await pipeline(createReadStream(dump),state.p.stdin);
    if((await state.done).failed)throw Error('pg_restore failed; no successful restore is claimed');
    const {Client}=await import('pg'),client=new Client({connectionString,ssl:false,connectionTimeoutMillis:10000});await client.connect();
    try{
      const r=await client.query('SELECT (SELECT COUNT(*) FROM tomi_users) users,(SELECT COUNT(*) FROM tomi_reports) reports,(SELECT COUNT(*) FROM tomi_room_gifts) gifts,(SELECT COUNT(*) FROM tomi_admin_audit) audit_entries');
      return {restored:true,localCheck:true,counts:Object.fromEntries(Object.entries(r.rows[0]).map(([k,v])=>[k,Number(v)])),sha256:await fileDigest(input),hasClientWarnings:state.warnings};
    }finally{await client.end();}
  }finally{if(state?.p.exitCode===null)state.p.kill('SIGTERM');await rm(directory,{recursive:true,force:true});}
}

async function main(){
  const [command,...args]=process.argv.slice(2),options=new Map();let confirmed=false;
  for(let i=0;i<args.length;i++){if(args[i]==='--confirm-empty-local'){confirmed=true;continue;}if(!['--input','--output'].includes(args[i])||!args[i+1])throw Error('Unknown backup option');options.set(args[i],args[++i]);}
  const key=backupKey(process.env.TOMI_BACKUP_KEY);let result;
  if(command==='backup')result=await createPostgresBackup({connectionString:process.env.TOMI_BACKUP_DATABASE_URL||process.env.DATABASE_URL,output:options.get('--output'),key});
  else if(command==='restore-check')result=await restorePostgresCheck({connectionString:process.env.TOMI_RESTORE_DATABASE_URL,input:options.get('--input'),key,confirmed});
  else if(command==='verify'){
    const dir=await mkdtemp(join(tmpdir(),'tomi-verify12-'));try{result=await decryptBackup(options.get('--input'),join(dir,'verified.dump'),key);result.sha256=await fileDigest(options.get('--input'));}finally{await rm(dir,{recursive:true,force:true});}
  }else throw Error('Use backup, verify, or restore-check');
  process.stdout.write(JSON.stringify(result)+'\n');
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)main().catch(()=>{console.error('Backup operation failed. Check the key, paths, database access and local restore safeguards. No credentials were printed.');process.exitCode=1;});
