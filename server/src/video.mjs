import {cleanupVideoDerivatives,abortMultipartUpload} from './media_intents.mjs';
import {ApiError} from './security.mjs';
export const maxVideoBytes=25*1024*1024,maxVideoDurationMs=180000;
const invalid=()=>{throw new ApiError(400,'INVALID_VIDEO','اختَر MP4 بترميز H.264 وصوت AAC، حتى1080p وثلاث دقائق و25 MB.');};
function boxes(b,start=0,end=b.length){
 const out=[];for(let at=start;at<end;){
  if(end-at<8||out.length>=10000)invalid();let n=b.readUInt32BE(at),head=8;
  if(n===1){if(end-at<16)invalid();const x=b.readBigUInt64BE(at+8);if(x>BigInt(maxVideoBytes))invalid();n=Number(x);head=16;}
  if(n===0)n=end-at;if(n<head||at+n>end)invalid();out.push({type:b.toString('ascii',at+4,at+8),start:at+head,end:at+n});at+=n;
 }return out;
}
function metadata(b){
 let video,audio=0;const roots=boxes(b);
 for(const trak of roots.filter(x=>x.type==='trak')){
  const mdia=boxes(b,trak.start,trak.end).find(x=>x.type==='mdia');if(!mdia)invalid();
  const parts=boxes(b,mdia.start,mdia.end),hdlr=parts.find(x=>x.type==='hdlr'),mdhd=parts.find(x=>x.type==='mdhd'),minf=parts.find(x=>x.type==='minf');
  if(!hdlr||hdlr.end-hdlr.start<12||!mdhd||!minf)invalid();const kind=b.toString('ascii',hdlr.start+8,hdlr.start+12);
  if(!['vide','soun'].includes(kind))invalid();let scale,duration;
  if(b[mdhd.start]===0&&mdhd.end-mdhd.start>=24){scale=b.readUInt32BE(mdhd.start+12);duration=b.readUInt32BE(mdhd.start+16);}
  else if(b[mdhd.start]===1&&mdhd.end-mdhd.start>=36){scale=b.readUInt32BE(mdhd.start+20);const d=b.readBigUInt64BE(mdhd.start+24);if(d>BigInt(Number.MAX_SAFE_INTEGER))invalid();duration=Number(d);}else invalid();
  const durationMs=Math.round(duration/scale*1000);if(!scale||!Number.isSafeInteger(durationMs)||durationMs<100||durationMs>maxVideoDurationMs+500)invalid();
  const stbl=boxes(b,minf.start,minf.end).find(x=>x.type==='stbl'),stsd=stbl&&boxes(b,stbl.start,stbl.end).find(x=>x.type==='stsd');
  if(!stsd||stsd.end-stsd.start<8||b.readUInt32BE(stsd.start+4)!==1)invalid();const entries=boxes(b,stsd.start+8,stsd.end);if(entries.length!==1)invalid();const entry=entries[0];
  if(kind==='vide'){
   if(video||!['avc1','avc3'].includes(entry.type)||entry.end-entry.start<78)invalid();
   const width=b.readUInt16BE(entry.start+24),height=b.readUInt16BE(entry.start+26);
   if(!width||!height||Math.max(width,height)>1920||width*height>1920*1080)invalid();
   const config=boxes(b,entry.start+78,entry.end).find(x=>x.type==='avcC');
   if(!config||config.end-config.start<7||b[config.start]!==1)invalid();
   video={width,height,durationMs};
  }else{
   if(++audio>1||entry.type!=='mp4a'||entry.end-entry.start<28)invalid();const channels=b.readUInt16BE(entry.start+16);
   if(channels<1||channels>8||!boxes(b,entry.start+28,entry.end).some(x=>x.type==='esds'))invalid();
  }
 }if(!video)invalid();return video;
}
// Only ftyp/moov are retained; mdat is checksummed by the caller and skipped.
// This also handles metadata at the end and headers split across HTTP chunks.
export class VideoInspector {
 constructor(length){if(!Number.isInteger(length)||length<32||length>maxVideoBytes)invalid();this.length=length;this.received=0;this.header=Buffer.alloc(0);this.remaining=0;this.parts=[];this.retained=0;this.type=null;this.moov=null;this.ftyp=false;this.mdat=false;this.count=0;}
 push(input){
  let chunk=Buffer.from(input);this.received+=chunk.length;if(this.received>this.length)invalid();
  while(chunk.length){
   if(!this.remaining){
    const want=this.header.length>=8&&this.header.readUInt32BE(0)===1?16:8;
    const n=Math.min(want-this.header.length,chunk.length);this.header=Buffer.concat([this.header,chunk.subarray(0,n)]);chunk=chunk.subarray(n);
    if(this.header.length<want)continue;if(want===8&&this.header.readUInt32BE(0)===1)continue;
    let size=this.header.readUInt32BE(0);if(size===1){const big=this.header.readBigUInt64BE(8);if(big>BigInt(this.length))invalid();size=Number(big);}
    const consumed=this.received-chunk.length-this.header.length;if(!size)size=this.length-consumed;
    if(++this.count>10000||size<this.header.length||consumed+size>this.length)invalid();
    this.type=this.header.toString('ascii',4,8);this.remaining=size-this.header.length;this.parts=[];this.retained=0;
    if(this.type==='moov'&&(this.moov||this.remaining>2*1024*1024)||this.type==='ftyp'&&(this.ftyp||this.remaining<8||this.remaining>4096))invalid();
    if(this.type==='mdat'&&this.remaining)this.mdat=true;
    this.header=Buffer.alloc(0);if(!this.remaining){this.finishBox();continue;}
   }
   const n=Math.min(this.remaining,chunk.length);
   if(this.type==='ftyp'||this.type==='moov'){this.parts.push(Buffer.from(chunk.subarray(0,n)));this.retained+=n;}
   chunk=chunk.subarray(n);this.remaining-=n;if(!this.remaining)this.finishBox();
  }
 }
 finishBox(){if(this.type==='moov')this.moov=Buffer.concat(this.parts);if(this.type==='ftyp'){const b=Buffer.concat(this.parts);const brands=[b.toString('ascii',0,4)];for(let at=8;at+4<=b.length;at+=4)brands.push(b.toString('ascii',at,at+4));if(!brands.some(x=>['isom','iso2','mp41','mp42','avc1'].includes(x)))invalid();this.ftyp=true;}this.parts=[];this.type=null;}
 finish(){if(this.received!==this.length||this.remaining||this.header.length||!this.ftyp||!this.moov||!this.mdat)invalid();return metadata(this.moov);}
}
export function videoMetadata(bytes){const inspector=new VideoInspector(bytes.length);inspector.push(bytes);return inspector.finish();}
const cleaning=new WeakSet();
export async function cleanupVideos(database,storage,prefix){
 if(!storage||cleaning.has(storage))return;cleaning.add(storage);
 try{const rows=(await database.query("SELECT id,object_key FROM tomi_video_uploads WHERE state<>'attached' AND expires_at<=? AND object_key LIKE ? ORDER BY expires_at LIMIT 20",[new Date().toISOString(),prefix+'%'])).rows;
  for(const u of rows)try{await cleanupVideoDerivatives(database,storage,u.id,u.object_key);await abortMultipartUpload(database,storage,u.id,u.object_key);await storage.delete(u.object_key);await database.query("DELETE FROM tomi_video_uploads WHERE id=? AND state<>'attached' AND expires_at<=?",[u.id,new Date().toISOString()]);await database.query('DELETE FROM tomi_upload_digests WHERE upload_id=?',[u.id]);}catch{console.error('Video cleanup deferred');}
 }finally{cleaning.delete(storage);}
}
