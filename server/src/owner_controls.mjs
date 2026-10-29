import {ApiError,validatePassword,validateProfile,hashPassword,newRecoveryCode,normalizeRecoveryCode,digest,isUniqueConflict} from './security.mjs';
import {welcomeCoins} from './room_catalog.mjs';
export const ownerActions=['add_coins','withdraw_coins','add_charisma','withdraw_charisma','mark_special','unmark_special','create_account'];
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
export async function accountEconomy(db,userId){
 const r=(await db.query('SELECT coins FROM tomi_room_wallets WHERE user_id=?',[userId])).rows[0];
 const p=(await db.query('SELECT received FROM tomi_user_progress WHERE user_id=?',[userId])).rows[0];
 return {coins:r?Number(r.coins):welcomeCoins,charisma:Number(p?.received??0)};
}
export async function prepareOwnerCommand(d){
 if(d.action!=='create_account')return {};
 const password=validatePassword(d.password),profile=validateProfile({username:d.username,displayName:d.displayName,bio:'',avatarPreset:'initials'});
 if(typeof d.special!=='boolean')fail(400,'VALIDATION','حدّد حالة الحساب المميز.');
 return {profile,passwordHash:await hashPassword(password),recoveryCode:newRecoveryCode()};
}
export async function applyOwnerCommand(db,current,d,prepared){
 if(d.action==='create_account'){
  if(d.expectedRevision!==0)fail(400,'VALIDATION','طلب إنشاء الحساب غير صحيح.');
  if((await db.query('SELECT 1 FROM tomi_users WHERE id=?',[d.targetId])).rows.length)fail(409,'ADMIN_CHANGED','معرّف الحساب مستخدم؛ حدّث الصفحة.');
  const stamp=new Date().toISOString();
  try{await db.query('INSERT INTO tomi_users(id,username,display_name,password_hash,recovery_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',[d.targetId,prepared.profile.username,prepared.profile.name,prepared.passwordHash,digest(normalizeRecoveryCode(prepared.recoveryCode)),stamp,stamp]);}
  catch(e){if(isUniqueConflict(e))fail(409,'USERNAME_TAKEN','اسم المستخدم مستخدم.');throw e;}
  await db.query('INSERT INTO tomi_admin_profiles(user_id,special,revision) VALUES(?,?,1)',[d.targetId,d.special?1:0]);
  return {applied:true,revision:1,before:null,after:{username:prepared.profile.username,special:d.special},ephemeral:{recoveryCode:prepared.recoveryCode}};
 }
 await db.query('INSERT INTO tomi_admin_profiles(user_id) VALUES(?) ON CONFLICT(user_id) DO NOTHING',[d.targetId]);
 const profile=(await db.query('SELECT special,revision FROM tomi_admin_profiles WHERE user_id=?',[d.targetId])).rows[0];
 if(Number(profile.revision)!==d.expectedRevision)fail(409,'ADMIN_CHANGED','تغيّرت بيانات الإدارة لهذا الحساب؛ حدّث الصفحة.');
 const before={...await accountEconomy(db,d.targetId),special:!!Number(profile.special)},after={...before};
 if(['mark_special','unmark_special'].includes(d.action))after.special=d.action==='mark_special';
 else {
  if(!Number.isSafeInteger(d.amount)||d.amount<=0||d.amount>9000000000000)fail(400,'VALIDATION','المبلغ عدد صحيح موجب ضمن الحد المسموح.');
  const field=d.action.endsWith('coins')?'coins':'charisma',delta=d.action.startsWith('withdraw_')?-d.amount:d.amount;
  const next=before[field]+delta;if(!Number.isSafeInteger(next)||next<0||next>9000000000000)fail(409,'ADMIN_BALANCE','الرصيد الحالي لا يسمح بهذا التعديل.');
  if(field==='coins'){
   await db.query('INSERT INTO tomi_room_wallets(user_id,coins,next_claim) VALUES(?,?,?) ON CONFLICT(user_id) DO NOTHING',[d.targetId,welcomeCoins,new Date(Date.now()+86400000).toISOString()]);
   const q=await db.query('UPDATE tomi_room_wallets SET coins=coins+? WHERE user_id=? AND coins+? BETWEEN 0 AND 9000000000000 RETURNING coins',[delta,d.targetId,delta]);
   if(q.rows.length!==1)fail(409,'ADMIN_BALANCE','تغيّر الرصيد؛ حدّث بيانات الحساب.');after.coins=Number(q.rows[0].coins);
   if(delta>0)await db.query('INSERT INTO tomi_contribution_credits(user_id,total) VALUES(?,?) ON CONFLICT(user_id) DO UPDATE SET total=CASE WHEN tomi_contribution_credits.total+excluded.total>9000000000000 THEN 9000000000000 ELSE tomi_contribution_credits.total+excluded.total END',[d.targetId,delta]);
  }else{
   await db.query('INSERT INTO tomi_user_progress(user_id) VALUES(?) ON CONFLICT(user_id) DO NOTHING',[d.targetId]);
   const q=await db.query('UPDATE tomi_user_progress SET received=received+? WHERE user_id=? AND received+? BETWEEN 0 AND 9000000000000 RETURNING received',[delta,d.targetId,delta]);
   if(q.rows.length!==1)fail(409,'ADMIN_BALANCE','تغيّر رصيد الكارزما؛ حدّث بيانات الحساب.');after.charisma=Number(q.rows[0].received);
  }
 }
 const applied=JSON.stringify(before)!==JSON.stringify(after),revision=Number(profile.revision)+(applied?1:0);
 if(applied)await db.query('UPDATE tomi_admin_profiles SET special=?,revision=? WHERE user_id=?',[after.special?1:0,revision,d.targetId]);
 return {applied,revision,before,after};
}
