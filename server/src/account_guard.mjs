import {AsyncLocalStorage} from 'node:async_hooks';
import {ApiError} from './security.mjs';

// PostgreSQL shares the actor gate across API instances. Shared gates do not
// change existing sorted user/room locks. Erasure takes its exclusive gate.
export function createAccountGuard(raw){
  const context=new AsyncLocalStorage();
  async function gate(db,id,exclusive=false){
    if(raw.dialect==='postgres')await db.query('SELECT '+(exclusive?'pg_advisory_xact_lock':'pg_advisory_xact_lock_shared')+'(172994,hashtext(?))',[id]);
  }
  async function live(db,current){
    await gate(db,current.id);
    const row=(await db.query(`SELECT 1 FROM tomi_sessions s JOIN tomi_users u ON u.id=s.user_id AND u.auth_version=s.auth_version
      WHERE s.token_hash=? AND s.user_id=? AND s.expires_at>? AND NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts d WHERE d.user_id=u.id)
      AND NOT EXISTS(SELECT 1 FROM tomi_account_restrictions a WHERE a.user_id=u.id AND a.suspended=1)`,[current.tokenHash,current.id,new Date().toISOString()])).rows[0];
    if(!row)throw new ApiError(401,'UNAUTHORIZED','انتهت الجلسة؛ سجّل دخولك مرة ثانية.');
  }
  const database={...raw,
    query(sql,values){
      const current=context.getStore();
      if(!current||/^\s*(SELECT|PRAGMA|EXPLAIN)\b/i.test(sql))return raw.query(sql,values);
      return raw.transaction(async db=>{await live(db,current);return db.query(sql,values);});
    },
    transaction(work){const current=context.getStore();return raw.transaction(async db=>{if(current)await live(db,current);return work(db);});},
  };
  return {database,gate,live,run:(current,work)=>context.run(current,work),unbound:work=>context.run(null,work)};
}
