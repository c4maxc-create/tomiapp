export const gameMaxLevel=50;
export const gameThresholds=Object.freeze(Array.from({length:gameMaxLevel},(_,i)=>100*i*i));
export function gameProgress(value=0) {
  const xp=Math.max(0,Number(value)||0),index=gameThresholds.findLastIndex(n=>xp>=n);
  const minimum=gameThresholds[index],next=gameThresholds[index+1]??null;
  return {xp,level:index+1,maxLevel:gameMaxLevel,minimum,next,remaining:next===null?0:next-xp,progress:next===null?1:(xp-minimum)/(next-minimum)};
}
export function gameDay(now) {return new Date(now+10800000).toISOString().slice(0,10);}

// This ledger is separate from money, gifts and donor progress. A completed
// server-owned source can credit a player once, regardless of retries/replicas.
export async function awardGameXp(db, userId, kind, sourceId, amount, now) {
  const day=gameDay(now);
  const live=(await db.query('SELECT id FROM tomi_users WHERE id=? AND NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts d WHERE d.user_id=tomi_users.id) AND NOT EXISTS(SELECT 1 FROM tomi_account_restrictions a WHERE a.user_id=tomi_users.id AND a.suspended=1)',[userId])).rows[0];
  if (!live) return 0;
  await db.query('INSERT INTO tomi_game_progress(user_id,xp) VALUES(?,0) ON CONFLICT(user_id) DO NOTHING',[userId]);
  await db.query('UPDATE tomi_game_progress SET xp=xp WHERE user_id=?',[userId]);
  const old=(await db.query('SELECT xp FROM tomi_game_awards WHERE user_id=? AND source_kind=? AND source_id=?',[userId,kind,sourceId])).rows[0];
  if (old) return Number(old.xp);
  const count=Number((await db.query('SELECT COUNT(*) n FROM tomi_game_awards WHERE user_id=? AND day=? AND xp>0',[userId,day])).rows[0].n);
  const earned=count<20?amount:0;
  await db.query('INSERT INTO tomi_game_awards(user_id,source_kind,source_id,day,xp,created_at) VALUES(?,?,?,?,?,?)',[userId,kind,sourceId,day,earned,now]);
  if (earned) await db.query('UPDATE tomi_game_progress SET xp=CASE WHEN xp>=240100-? THEN 240100 ELSE xp+? END WHERE user_id=?',[earned,earned,userId]);
  return earned;
}
