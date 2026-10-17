import {ApiError} from './security.mjs';
const fail=(s,c,m)=>{throw new ApiError(s,c,m);};
export function createRoomSocial({database,readJson,respond,limit}){
 async function preferences(db,roomId,user){
  const r=(await db.query(`SELECT
   COALESCE((SELECT favorite FROM tomi_room_preferences WHERE room_id=? AND user_id=?),0) AS favorite,
   COALESCE((SELECT following FROM tomi_room_preferences WHERE room_id=? AND user_id=?),0) AS following,
   COALESCE((SELECT revision FROM tomi_room_preferences WHERE room_id=? AND user_id=?),0) AS revision,
   (SELECT COUNT(*) FROM tomi_room_preferences WHERE room_id=? AND following=1) AS followers`,[roomId,user,roomId,user,roomId,user,roomId])).rows[0];
  return {favorite:!!Number(r.favorite),following:!!Number(r.following),revision:Number(r.revision),followers:Number(r.followers)};
 }
 async function handle(request,response,url,current){
  const m=/^\/v1\/rooms\/([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})\/preferences$/.exec(url.pathname);
  if(!m||request.method!=='PUT')return false;
  await limit('room-prefs:'+current.id,60);
  const d=await readJson(request),rid=m[1],uid=current.id;
  if(!['favorite','following'].some(k=>Object.hasOwn(d,k))||Object.keys(d).some(k=>!['favorite','following','expectedRevision'].includes(k))||['favorite','following'].some(k=>Object.hasOwn(d,k)&&typeof d[k]!=='boolean')||d.expectedRevision!==undefined&&(!Number.isSafeInteger(d.expectedRevision)||d.expectedRevision<0))fail(400,'VALIDATION','اختيار المفضلة أو المتابعة غير صحيح.');
  await database.transaction(async db=>{
   await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING id',[uid]);
   const r=(await db.query('UPDATE tomi_voice_rooms SET revision=revision WHERE id=? RETURNING state,owner_id',[rid])).rows[0];
   if(!r)fail(404,'ROOM_NOT_FOUND','الغرفة غير موجودة.');
   const old=(await db.query('SELECT * FROM tomi_room_preferences WHERE room_id=? AND user_id=?',[rid,uid])).rows[0]??{favorite:0,following:0,revision:0};
   if(d.expectedRevision!==undefined&&Number(old.revision)!==d.expectedRevision)fail(409,'PREFERENCES_CHANGED','اختيارات الغرفة تغيّرت من جهاز آخر؛ حدّث القائمة.');
   const favorite=d.favorite===undefined?Number(old.favorite):Number(d.favorite),following=d.following===undefined?Number(old.following):Number(d.following);
   if(favorite>Number(old.favorite)||following>Number(old.following)){
    if(r.state!=='open')fail(410,'ROOM_CLOSED','الغرفة مغلقة.');
    if((await db.query('SELECT 1 FROM tomi_user_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)',[uid,r.owner_id,r.owner_id,uid])).rows.length)fail(403,'ROOM_BLOCKED','متابعة هذه الغرفة غير متاحة بسبب الحظر.');
   }
   if(favorite===Number(old.favorite)&&following===Number(old.following))return;
   await db.query('INSERT INTO tomi_room_preferences(room_id,user_id,favorite,following,revision,updated_at) VALUES(?,?,?,?,?,?) ON CONFLICT(room_id,user_id) DO UPDATE SET favorite=excluded.favorite,following=excluded.following,revision=excluded.revision,updated_at=excluded.updated_at',[rid,uid,favorite,following,Number(old.revision)+1,new Date().toISOString()]);
  });respond(response,200,{roomId:rid,preferences:await preferences(database,rid,uid)});return true;
 }
 return {preferences,handle};
}
