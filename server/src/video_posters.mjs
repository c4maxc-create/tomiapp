import {ApiError} from './security.mjs';
import {imageDimensions} from './images.mjs';
export function createVideoPosters({database,readJson,respond,limit}){return {async handle(req,res,url,current){
 const m=url.pathname.match(/^\/v1\/media\/videos\/([a-f0-9-]{36})\/poster$/);if(!m||req.method!=='PUT')return false;
 await limit('video-poster:'+current.id,20);const d=await readJson(req,45056);
 if(!d||Object.keys(d).length!==1||typeof d.poster!=='string'||d.poster.length>44000||!/^data:image\/png;base64,[A-Za-z0-9+/]+={0,2}$/.test(d.poster))throw new ApiError(400,'VALIDATION','صورة المعاينة غير صحيحة.');
 const bytes=Buffer.from(d.poster.slice('data:image/png;base64,'.length),'base64');if(bytes.length>32768||bytes.toString('base64')!==d.poster.slice(22))throw new ApiError(400,'VALIDATION','صورة المعاينة أكبر من المسموح.');
 const size=imageDimensions(bytes,'image/png');if(size.width>320||size.height>320)throw new ApiError(400,'VALIDATION','صورة المعاينة أكبر من المسموح.');
 await database.transaction(async db=>{
  const stamp=new Date().toISOString();let table='tomi_video_posters';
  let r=(await db.query("SELECT id FROM tomi_video_uploads WHERE id=? AND user_id=? AND state='pending' AND expires_at>?",[m[1],current.id,stamp])).rows[0];
  if(!r){table='tomi_private_video_posters';r=(await db.query("SELECT id FROM tomi_private_uploads WHERE id=? AND user_id=? AND kind='video' AND state='pending' AND expires_at>?",[m[1],current.id,stamp])).rows[0];}
  if(!r)throw new ApiError(404,'UPLOAD_INVALID','الرفع غير متاح.');
  await db.query('INSERT INTO '+table+'(upload_id,poster) VALUES(?,?) ON CONFLICT(upload_id) DO NOTHING',[m[1],d.poster]);
  const saved=(await db.query('SELECT poster FROM '+table+' WHERE upload_id=?',[m[1]])).rows[0];if(saved.poster!==d.poster)throw new ApiError(409,'REQUEST_CHANGED','المعاينة السابقة محفوظة لهذا الفيديو.');
 });respond(res,200,{saved:true});return true;
}};}
