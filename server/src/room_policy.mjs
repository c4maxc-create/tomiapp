import {randomInt} from 'node:crypto';
import {ApiError} from './security.mjs';
export const advancedPrice=5799,roomLifetime=60*86400000;
export const roomShop=Object.freeze([
 {id:'flame',kind:'frame',name:'إطار اللهب',days:7,price:700},
 {id:'ice',kind:'frame',name:'إطار الجليد',days:7,price:700},
 {id:'royal',kind:'frame',name:'التاج الذهبي',days:30,price:2400},
 {id:'fire',kind:'entrance',name:'دخول ناري',days:7,price:900},
 {id:'comet',kind:'entrance',name:'مسار النجوم',days:7,price:900},
 {id:'royal',kind:'entrance',name:'دخول ملكي',days:30,price:2900},
]);
const iso=()=>new Date().toISOString();
export async function policy(db,r){return (await db.query('SELECT * FROM tomi_room_policy WHERE room_id=?',[r.id])).rows[0];}
export async function createPolicy(db,r,tier){
 let id=null;
 if(tier==='advanced')id=String((await db.query('UPDATE tomi_room_numbers SET value=value+1 WHERE id=1 RETURNING value')).rows[0].value);
 await db.query('INSERT INTO tomi_room_policy(room_id,tier,public_id,creator_id,price,last_owner_visit) VALUES(?,?,?,?,?,?)',[r.id,tier,id,r.owner_id,tier==='advanced'?advancedPrice:0,iso()]);
}
export async function policyFields(db,r){
 const p=await policy(db,r);
 const xp=p.tier==='advanced'?Number((await db.query('SELECT COALESCE(SUM(total),0) xp FROM tomi_room_all_gifts WHERE room_id=?',[r.id])).rows[0].xp):0;
 const thresholds=[0,1000,5000,15000,40000,100000,250000,600000,1500000,3000000];
 const level=p.tier==='advanced'?thresholds.filter(v=>xp>=v).length:null;
 const next=level!==null&&level<10?thresholds[level]:null;
 return {level,levelXp:xp,levelStart:level===null?0:thresholds[level-1],levelNext:next,tier:p.tier,publicId:p.public_id,advancedPrice,hasLevels:p.tier==='advanced',lastOwnerVisit:p.last_owner_visit,
  expiresAt:p.tier==='advanced'?new Date(Date.parse(p.last_owner_visit)+roomLifetime).toISOString():null};
}
// Room row is already locked by caller. Transfer applies only to active peers.
export async function afterDeparture(db,r,removed,job){
 const p=await policy(db,r);
 if(p.tier!=='free'||r.state!=='open')return;
 const peers=(await db.query("SELECT * FROM tomi_voice_members WHERE room_id=? AND state='active' ORDER BY user_id",[r.id])).rows;
 if(!peers.length){await db.query("UPDATE tomi_voice_rooms SET state='closed',empty_since=?,needs_delete=1,revision=revision+1 WHERE id=?",[iso(),r.id]);r.state='closed';return;}
 if(removed.user_id!==r.owner_id)return;
 const next=peers[randomInt(peers.length)];
 await db.query("UPDATE tomi_voice_members SET role='member' WHERE room_id=?",[r.id]);
 await db.query("UPDATE tomi_voice_members SET role='owner',seat=-1,mic_allowed=1,requested_at=NULL WHERE room_id=? AND user_id=?",[r.id,next.user_id]);
 await db.query('UPDATE tomi_voice_rooms SET owner_id=?,revision=revision+1 WHERE id=?',[next.user_id,r.id]);r.owner_id=next.user_id;
 await job(db,r,next,1);
}
export async function roomCosmetics(db,user){return (await db.query('SELECT kind,style_id,expires_at,equipped FROM tomi_room_cosmetics WHERE user_id=? AND expires_at>?',[user,iso()])).rows;}
export async function decorateRoomUsers(db,users){
 const ids=[...users.keys()];if(!ids.length)return;
 const all=(await db.query('SELECT * FROM tomi_room_cosmetics WHERE user_id IN ('+ids.map(()=>'?').join(',')+') AND expires_at>?',[...ids,iso()])).rows;
 const groups=new Map();for(const item of all){if(!groups.has(item.user_id))groups.set(item.user_id,[]);groups.get(item.user_id).push(item);}
 for(const [id,u]of users){
  const items=groups.get(id)??[],frame=items.find(x=>x.kind==='frame'&&Number(x.equipped)),entrance=items.find(x=>x.kind==='entrance'&&Number(x.equipped));
  users.set(id,{...u,identity:{...u.identity,roomFrameId:frame?.style_id??'none',roomFrameExpiresAt:frame?.expires_at??null,roomEntranceId:entrance?.style_id??'none'},roomCosmetics:items.map(x=>({kind:x.kind,styleId:x.style_id,expiresAt:x.expires_at,equipped:!!Number(x.equipped)}))});
 }
}
export async function buyCosmetic(db,current,d,wallet){
 if(Object.keys(d).some(k=>!['requestId','kind','styleId'].includes(k))||!/^([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$/.test(d.requestId??''))throw new ApiError(400,'VALIDATION','طلب الشراء غير صحيح.');
 const item=roomShop.find(x=>x.id===d.styleId&&x.kind===d.kind);if(!item)throw new ApiError(400,'VALIDATION','العنصر غير متاح.');
 const fp=JSON.stringify([item.kind,item.id]);
 await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING id',[current.id]);
 const old=(await db.query('SELECT * FROM tomi_cosmetic_purchases WHERE user_id=? AND request_id=?',[current.id,d.requestId])).rows[0];
 if(old){if(old.fingerprint!==fp)throw new ApiError(409,'REQUEST_CHANGED','طلب الشراء تغيّر.');return {wallet:await wallet(db,current.id),expiresAt:old.expires_at};}
 await wallet(db,current.id);
 if((await db.query('UPDATE tomi_room_wallets SET coins=coins-? WHERE user_id=? AND coins>=?',[item.price,current.id,item.price])).changes!==1)throw new ApiError(409,'ROOM_COINS_LOW','رصيد الكوينز غير كافٍ.');
 const prior=(await db.query('SELECT expires_at FROM tomi_room_cosmetics WHERE user_id=? AND kind=? AND style_id=?',[current.id,item.kind,item.id])).rows[0];
 const expires=new Date(Math.max(Date.now(),Date.parse(prior?.expires_at??'')||0)+item.days*86400000).toISOString();
 await db.query('UPDATE tomi_room_cosmetics SET equipped=0 WHERE user_id=? AND kind=?',[current.id,item.kind]);
 await db.query('INSERT INTO tomi_room_cosmetics(user_id,kind,style_id,expires_at,equipped) VALUES(?,?,?,?,1) ON CONFLICT(user_id,kind,style_id) DO UPDATE SET expires_at=excluded.expires_at,equipped=1',[current.id,item.kind,item.id,expires]);
 await db.query('INSERT INTO tomi_cosmetic_purchases(user_id,request_id,fingerprint,expires_at,total) VALUES(?,?,?,?,?)',[current.id,d.requestId,fp,expires,item.price]);
 return {wallet:await wallet(db,current.id),expiresAt:expires};
}

export async function equipCosmetic(db,current,d){
 if(Object.keys(d).some(k=>!['kind','styleId'].includes(k))||!['frame','entrance'].includes(d.kind)||typeof d.styleId!=='string')throw new ApiError(400,'VALIDATION','اختيار الزينة غير صحيح.');
 await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING id',[current.id]);
 if(d.styleId!=='none'&&!(await db.query('SELECT 1 FROM tomi_room_cosmetics WHERE user_id=? AND kind=? AND style_id=? AND expires_at>?',[current.id,d.kind,d.styleId,iso()])).rows.length)throw new ApiError(409,'COSMETIC_EXPIRED','هذا العنصر غير مملوك أو انتهت مدته.');
 await db.query('UPDATE tomi_room_cosmetics SET equipped=0 WHERE user_id=? AND kind=?',[current.id,d.kind]);
 if(d.styleId!=='none')await db.query('UPDATE tomi_room_cosmetics SET equipped=1 WHERE user_id=? AND kind=? AND style_id=?',[current.id,d.kind,d.styleId]);
 return {owned:await roomCosmetics(db,current.id)};
}
