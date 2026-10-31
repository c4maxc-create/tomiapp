import {charismaStatus} from './charisma_catalog.mjs';
import {ApiError} from './security.mjs';

// User XP is separate from room XP: one point per trial coin spent on a
// committed gift. No client claims, login farming, or duplicate replay grants.
export const userThresholds=Object.freeze([0,50,200,500,1200,2500,5000,10000,20000,40000]);
export const identityStyles=Object.freeze({
 frames:[
  {id:'none',name:'بلا إطار',level:1},
  {id:'orbit',name:'مدار تومي',level:2},
  {id:'rose',name:'وهج الورد',level:3},
  {id:'royal',name:'التاج الملكي',level:5},
  {id:'aurora',name:'الشفق',level:7},
 ],
 portraits:[
  {id:'none',name:'صورتي الحالية',level:1},
  {id:'moon',name:'قمر متحرك',level:2},
  {id:'panda',name:'باندا تومي',level:3},
  {id:'nova',name:'نجمة مضيئة',level:5},
 ],
 entrances:[
  {id:'none',name:'دخول هادئ',level:1},
  {id:'glow',name:'هالة ترحيب',level:2},
  {id:'comet',name:'مسار النجوم',level:4},
  {id:'royal',name:'دخول ملكي',level:6},
 ],
});
export function userLevel(value){
 const xp=Math.max(0,Number(value)||0);let index=0;
 while(index<userThresholds.length-1&&xp>=userThresholds[index+1])index++;
 const floor=userThresholds[index],next=userThresholds[index+1]??null;
 return {level:index+1,xp,floor,next,remaining:next===null?0:next-xp,progress:next===null?1:(xp-floor)/(next-floor)};
}
export function styleAllowed(category,id,level){return identityStyles[category].some(x=>x.id===id&&x.level<=level);}
export function identityFields(r){
 const spent=Number(r.user_spent??0),sent=Number(r.user_gifts_sent??0),received=Number(r.user_received??0),giftsReceived=Number(r.user_gifts_received??0),rooms=Number(r.user_rooms_created??0),status=userLevel(spent);
 const badges=[];
 if(sent>0)badges.push({id:'first_gift',name:'أول هدية',icon:'gift'});
 if(spent>=1000)badges.push({id:'generous',name:'كريم المجلس',icon:'heart'});
 if(rooms>0)badges.push({id:'host',name:'صاحب مجلس',icon:'room'});
 if(giftsReceived>=3)badges.push({id:'welcomed',name:'محبوب السالفة',icon:'star'});
 const safe=(category,id)=>styleAllowed(category,id,status.level)?id:'none';
 return {identity:{...status,spent,special:!!Number(r.special_account??0),charisma:received,charismaTier:charismaStatus(received),giftsSent:sent,received,giftsReceived,roomsCreated:rooms,badges,
  frameId:safe('frames',r.identity_frame),portraitId:safe('portraits',r.identity_portrait),entranceId:safe('entrances',r.identity_entrance),revision:Number(r.identity_revision??0)}};
}
export async function giftProgress(db,sender,recipient,total){
 for(const uid of [...new Set([sender,recipient])].sort()){
  const outgoing=uid===sender;
  const q=await db.query(`INSERT INTO tomi_user_progress(user_id,spent,gifts_sent,received,gifts_received) VALUES(?,?,?,?,?)
   ON CONFLICT(user_id) DO UPDATE SET spent=tomi_user_progress.spent+excluded.spent,gifts_sent=tomi_user_progress.gifts_sent+excluded.gifts_sent,
   received=tomi_user_progress.received+excluded.received,gifts_received=tomi_user_progress.gifts_received+excluded.gifts_received
   WHERE tomi_user_progress.spent+excluded.spent<=9000000000000 AND tomi_user_progress.received+excluded.received<=9000000000000`,[uid,outgoing?total:0,outgoing?1:0,uid===recipient?total:0,uid===recipient?1:0]);
  if(q.changes!==1)throw new ApiError(409,'USER_XP_LIMIT','وصل الحساب إلى الحد الأعلى للنقاط.');
 }
}
