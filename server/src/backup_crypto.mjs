import {randomBytes,randomUUID,createCipheriv,createDecipheriv,createHash} from 'node:crypto';
import {createReadStream,createWriteStream} from 'node:fs';
import {mkdir,open,appendFile,link,unlink,stat} from 'node:fs/promises';
import {dirname,isAbsolute,join} from 'node:path';
import {pipeline} from 'node:stream/promises';
import {Readable} from 'node:stream';

const magic=Buffer.from('TOMIBK12'),headerSize=magic.length+12,tagSize=16;
export function backupKey(value){
  if(typeof value!=='string'||!/^[A-Za-z0-9+/]{43}=$/.test(value))throw Error('TOMI_BACKUP_KEY must contain32 random bytes encoded as base64');
  const key=Buffer.from(value,'base64');if(key.length!==32||key.toString('base64')!==value)throw Error('Invalid backup key');return key;
}
function keyCheck(key){if(!Buffer.isBuffer(key)||key.length!==32)throw Error('A32-byte backup key is required');}
function pathCheck(output){if(typeof output!=='string'||!isAbsolute(output))throw Error('Use an absolute output path');}
async function publish(temp,output){
  // A hard link publishes a complete file atomically and never replaces a file.
  await link(temp,output);await unlink(temp);
}
export async function fileDigest(path){const hash=createHash('sha256');for await(const chunk of createReadStream(path))hash.update(chunk);return hash.digest('hex');}
export async function encryptBackup(source,output,key){
  keyCheck(key);pathCheck(output);await mkdir(dirname(output),{recursive:true,mode:0o700});
  const temp=join(dirname(output),'.tomi-encrypt-'+randomUUID()),iv=randomBytes(12),header=Buffer.concat([magic,iv]);
  const cipher=createCipheriv('aes-256-gcm',key,iv);cipher.setAAD(header);
  try{
    const writer=createWriteStream(temp,{flags:'wx',mode:0o600});writer.write(header);
    await pipeline(source,cipher,writer);await appendFile(temp,cipher.getAuthTag());
    const handle=await open(temp,'r+');try{await handle.sync();}finally{await handle.close();}
    const bytes=(await stat(temp)).size,sha256=await fileDigest(temp);await publish(temp,output);
    return {format:'TOMI-AES256GCM-1',bytes,sha256,createdAt:new Date().toISOString()};
  }finally{await unlink(temp).catch(()=>{});}
}
export async function decryptBackup(input,output,key){
  keyCheck(key);pathCheck(output);const size=(await stat(input)).size;
  if(size<headerSize+tagSize)throw Error('Backup is truncated');
  const header=Buffer.alloc(headerSize),tag=Buffer.alloc(tagSize),handle=await open(input,'r');
  try{await handle.read(header,0,header.length,0);await handle.read(tag,0,tag.length,size-tagSize);}finally{await handle.close();}
  if(!header.subarray(0,magic.length).equals(magic))throw Error('Unsupported backup format');
  await mkdir(dirname(output),{recursive:true,mode:0o700});const temp=join(dirname(output),'.tomi-decrypt-'+randomUUID());
  const decipher=createDecipheriv('aes-256-gcm',key,header.subarray(magic.length));decipher.setAAD(header);decipher.setAuthTag(tag);
  try{
    // Plaintext stays private and unpublished until the authentication tag passes.
    const source=size===headerSize+tagSize?Readable.from([]):createReadStream(input,{start:headerSize,end:size-tagSize-1});
    await pipeline(source,decipher,createWriteStream(temp,{flags:'wx',mode:0o600}));
    const bytes=(await stat(temp)).size;await publish(temp,output);return {bytes,authenticated:true};
  }finally{await unlink(temp).catch(()=>{});}
}
