import {mkdir,mkdtemp,rm} from 'node:fs/promises';
import {join,isAbsolute} from 'node:path';
import {tmpdir} from 'node:os';
import {randomUUID} from 'node:crypto';
import {createPostgresBackup} from './backup.mjs';
import {backupKey,decryptBackup} from '../src/backup_crypto.mjs';
// Non-overwriting encrypted output; systemd excludes overlapping runs.
try{
 const root=process.env.TOMI_BACKUP_DIRECTORY;if(!root||!isAbsolute(root))throw Error('path');
 await mkdir(root,{recursive:true,mode:0o700});
 const output=join(root,'tomi-'+new Date().toISOString().replaceAll(':','-')+'-'+randomUUID()+'.enc'),key=backupKey(process.env.TOMI_BACKUP_KEY);
 const result=await createPostgresBackup({connectionString:process.env.TOMI_BACKUP_DATABASE_URL,output,key});
 const temp=await mkdtemp(join(tmpdir(),'tomi-backup-verify-'));
 try{await decryptBackup(output,join(temp,'verified.dump'),key);}finally{await rm(temp,{recursive:true,force:true});}
 console.log(JSON.stringify({encrypted:true,authenticated:true,bytes:result.bytes,at:result.createdAt}));
}catch{console.error('Encrypted backup failed. Check the protected service configuration.');process.exitCode=1;}
