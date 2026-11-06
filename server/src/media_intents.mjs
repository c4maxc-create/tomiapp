import {ApiError,digest} from './security.mjs';
export const validUuid=v=>typeof v==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(v);
export function validateMediaIntent(d){
 if(d.requestId!==undefined&&!validUuid(d.requestId)||d.contentSha256!==undefined&&(typeof d.contentSha256!=='string'||!/^[a-f0-9]{64}$/.test(d.contentSha256)))throw new ApiError(400,'VALIDATION','بيانات ملف الإرسال غير صحيحة.');
}
export async function uploadWithDigest(db,u,expected){
 const row=(await db.query('SELECT sha256 FROM tomi_upload_digests WHERE upload_id=?',[u?.id??''])).rows[0];
 if(expected&&(!row||row.sha256!==expected))throw new ApiError(409,'REQUEST_CHANGED','ملف الإرسال تغيّر؛ استخدم طلبًا جديدًا.');
 return u?{...u,...row?{content_sha256:row.sha256}:{}}:u;
}
export async function prepareIntent({database,viewer,scope,table,d,create,storage}){
 validateMediaIntent(d);
 if(!['tomi_image_uploads','tomi_audio_uploads','tomi_video_uploads','tomi_private_uploads'].includes(table))throw Error('MEDIA_TABLE');
 const fingerprint=digest(JSON.stringify([scope,d.contentType,d.byteLength,d.contentMd5,d.durationMs??null,d.contentSha256??null,...d.fileName?[d.fileName]:[]]));
 const u=await database.transaction(async db=>{
  await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING id',[viewer]);
  const old=d.requestId?(await db.query('SELECT * FROM tomi_media_intents WHERE user_id=? AND request_id=?',[viewer,d.requestId])).rows[0]:null;
  if(old&&(old.scope!==scope||old.payload_hash!==fingerprint))throw new ApiError(409,'REQUEST_CHANGED','محتوى رفع الملف تغيّر.');
  if(old){
   const prior=(await db.query('SELECT * FROM '+table+' WHERE id=? AND user_id=?',[old.upload_id,viewer])).rows[0];
   if(prior?.state==='attached')throw new ApiError(409,'UPLOAD_ATTACHED','الملف مرتبط بإرسال سابق؛ تحقق من نتيجة الطلب.');
   if(prior?.state==='pending'&&prior.expires_at>new Date().toISOString())return prior;
  }
  const fresh=await create(db);
  if(d.contentSha256)await db.query('INSERT INTO tomi_upload_digests(upload_id,sha256,created_at) VALUES(?,?,?)',[fresh.id,d.contentSha256,new Date().toISOString()]);
  if(d.requestId)await db.query('INSERT INTO tomi_media_intents(user_id,request_id,scope,payload_hash,upload_id,created_at) VALUES(?,?,?,?,?,?) ON CONFLICT(user_id,request_id) DO UPDATE SET upload_id=excluded.upload_id',[viewer,d.requestId,scope,fingerprint,fresh.id,new Date().toISOString()]);
  return fresh;
 });
 return {uploadId:u.id,...storage.prepare(u),...(storage.supportsMultipart&&Number(u.byte_length)>5*1024*1024?{resumablePath:`/v1/media/resumable/${table.replace('tomi_','')}/${u.id}`}:{})};
}

export async function abortMultipartUpload(database,storage,id,key){
 const row=(await database.query('SELECT provider_id,completed FROM tomi_multipart_uploads WHERE upload_id=?',[id])).rows[0];
 if(row){if(!Number(row.completed)){if(!storage.abortMultipart)throw Error('MULTIPART_CLEANUP_UNAVAILABLE');await storage.abortMultipart(key,row.provider_id);}await database.query('DELETE FROM tomi_multipart_uploads WHERE upload_id=?',[id]);}
}

export async function cleanupVideoDerivatives(database,storage,id,key){
 const job=(await database.query('SELECT object_key FROM tomi_video_jobs WHERE upload_id=?',[id])).rows[0];
 if(job){if(job.object_key!==key)throw Error('VIDEO_CLEANUP_KEY');for(const height of [540,720])await storage.delete(key+'.'+height+'.mp4');await database.query('DELETE FROM tomi_video_renditions WHERE upload_id=?',[id]);await database.query('DELETE FROM tomi_video_jobs WHERE upload_id=?',[id]);}
}
