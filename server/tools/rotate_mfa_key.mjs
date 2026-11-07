import {openDatabase} from '../src/database.mjs';
import {mfaKey,seal,unseal} from '../src/mfa.mjs';
// Run with all API workers stopped; never prints keys or seeds.
let db;
try{
 if(process.argv[2]!=='--apply-offline')throw Error('Stop workers first');
 const oldKey=mfaKey(process.env.TOMI_MFA_OLD_KEY),newKey=mfaKey(process.env.TOMI_MFA_NEW_KEY);
 if(!oldKey||!newKey||oldKey.equals(newKey))throw Error('Two distinct keys are required');
 db=await openDatabase({connectionString:process.env.DATABASE_URL,production:true});
 let count=0;await db.transaction(async tx=>{const rows=(await tx.query('SELECT user_id,secret FROM tomi_mfa')).rows;for(const row of rows){const secret=unseal(row.secret,oldKey,row.user_id);await tx.query('UPDATE tomi_mfa SET secret=? WHERE user_id=?',[seal(secret,newKey,row.user_id),row.user_id]);count++;}});
 console.log(JSON.stringify({rotated:count,next:'Replace TOMI_MFA_KEY with the new key before restarting workers.'}));
}catch{console.error('MFA rotation failed; no secrets printed. Check offline mode, keys and database access.');process.exitCode=1;}finally{await db?.close();}
