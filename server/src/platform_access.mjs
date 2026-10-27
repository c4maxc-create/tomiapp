import {ApiError} from './security.mjs';
export const staffPermissions=['reports','accounts','bans','posts','rooms','metrics','audit'];
export const legacyPermissions=['reports','accounts','posts','rooms','metrics','audit'];
export function validatePermissions(value){
 if(!Array.isArray(value)||value.length>staffPermissions.length||value.some(p=>typeof p!=='string'||!staffPermissions.includes(p))||new Set(value).size!==value.length)throw new ApiError(400,'VALIDATION','اختَر صلاحيات المشرف من القائمة.');
 return staffPermissions.filter(p=>value.includes(p));
}
export async function effectivePermissions(db,userId,role){
 if(role==='owner')return [...staffPermissions,'economy','staff','special','create_accounts'];
 if(role!=='moderator')return [];
 const row=(await db.query('SELECT permissions FROM tomi_staff_permissions WHERE user_id=?',[userId])).rows[0];
 return row?validatePermissions(JSON.parse(row.permissions)):[...legacyPermissions];
}
