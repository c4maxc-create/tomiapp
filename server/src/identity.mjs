import {ApiError} from './security.mjs';
import {identityStyles,userThresholds,userLevel,styleAllowed} from './identity_catalog.mjs';
import {giftRanking} from './ranking.mjs';
const fail=(s,c,m)=>{throw new ApiError(s,c,m);};
export function createIdentity({database,readJson,respond,limit,userById,usersByIds}){
 async function handle(request,response,url,current){
  const path=url.pathname,method=request.method,viewer=current.id;
  if(path==='/v1/identity/catalog'&&method==='GET'){
   respond(response,200,{styles:identityStyles,thresholds:userThresholds,pointsPolicy:'one_point_per_committed_trial_coin_spent',timeZone:'Asia/Baghdad',entryCooldownSeconds:90,trial:true});return true;
  }
  if(path==='/v1/community/ranking'&&method==='GET'){
   await limit('global-rank:'+viewer,60);respond(response,200,await giftRanking(database,viewer,usersByIds,{period:url.searchParams.get('period')||'all'}));return true;
  }
  if(path!=='/v1/me/identity'||method!=='PUT')return false;
  await limit('identity:'+viewer,30);const d=await readJson(request),keys={frameId:'frame_id',portraitId:'portrait_id',entranceId:'entrance_id'};
  if(!Object.keys(d).some(k=>Object.hasOwn(keys,k))||Object.keys(d).some(k=>!(Object.hasOwn(keys,k))&&k!=='expectedRevision')||d.expectedRevision!==undefined&&(!Number.isSafeInteger(d.expectedRevision)||d.expectedRevision<0))fail(400,'VALIDATION','تعديل الهوية غير صحيح.');
  await database.transaction(async db=>{
   await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING id',[viewer]);
   const p=(await db.query('SELECT spent FROM tomi_user_progress WHERE user_id=?',[viewer])).rows[0],level=userLevel(p?.spent??0).level;
   await db.query('INSERT INTO tomi_user_identity(user_id) VALUES(?) ON CONFLICT(user_id) DO NOTHING',[viewer]);
   const old=(await db.query('SELECT * FROM tomi_user_identity WHERE user_id=?',[viewer])).rows[0];
   if(d.expectedRevision!==undefined&&d.expectedRevision!==Number(old.revision))fail(409,'IDENTITY_CHANGED','الهوية تغيّرت من جهاز آخر؛ حدّث الصفحة.');
   let changed=false;
   for(const [key,column] of Object.entries(keys))if(Object.hasOwn(d,key)){
    const category=key==='frameId'?'frames':key==='portraitId'?'portraits':'entrances';
    if(typeof d[key]!=='string'||!identityStyles[category].some(x=>x.id===d[key]))fail(400,'VALIDATION','اختيار الهوية غير معروف.');
    if(!styleAllowed(category,d[key],level))fail(403,'IDENTITY_LOCKED','هذه الهوية تُفتح عند الوصول للمستوى المطلوب.');
    if(old[column]!==d[key]){changed=true;await db.query('UPDATE tomi_user_identity SET '+column+'=? WHERE user_id=?',[d[key],viewer]);}
   }
   if(changed)await db.query('UPDATE tomi_user_identity SET revision=revision+1 WHERE user_id=?',[viewer]);
  });respond(response,200,{user:await userById(viewer,viewer)});return true;
 }
 return {handle};
}
