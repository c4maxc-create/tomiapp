// Retired constraints must not be recreated before additive migrations run.
const retiredOwnerIndex=/CREATE UNIQUE INDEX IF NOT EXISTS tomi_one_owned_voice_room ON tomi_voice_rooms\(owner_id\) WHERE state='open';\s*/;
export const portableSchema=source=>source.replace(retiredOwnerIndex,'');
export function postgresSchema(source){
 return portableSchema(source).replace(/CREATE VIEW IF NOT EXISTS /g,'CREATE OR REPLACE VIEW ')+`
DO $tomi_support_upgrade$
BEGIN
 IF EXISTS(SELECT 1 FROM pg_constraint
   WHERE conrelid='tomi_support_events'::regclass
   AND conname='tomi_support_events_gift_id_fkey' AND confdeltype<>'c') THEN
  ALTER TABLE tomi_support_events DROP CONSTRAINT tomi_support_events_gift_id_fkey;
  ALTER TABLE tomi_support_events ADD CONSTRAINT tomi_support_events_gift_id_fkey
   FOREIGN KEY(gift_id) REFERENCES tomi_room_support(id) ON DELETE CASCADE;
 END IF;
END;
$tomi_support_upgrade$;
`;
}
export function migrateSQLite(db){
 const gift=db.prepare('PRAGMA foreign_key_list(tomi_support_events)').all().find(x=>x.from==='gift_id');
 if(!gift||gift.on_delete==='CASCADE')return;
 // This link table has no dependents. Rebuild atomically, retaining every link.
 db.exec('BEGIN IMMEDIATE');
 try{
  db.exec(`CREATE TABLE tomi_support_events_upgrade (
   room_id TEXT NOT NULL,sequence BIGINT NOT NULL,
   gift_id TEXT NOT NULL REFERENCES tomi_room_support(id) ON DELETE CASCADE,
   PRIMARY KEY(room_id,sequence),
   FOREIGN KEY(room_id,sequence) REFERENCES tomi_room_events(room_id,sequence) ON DELETE CASCADE
  );
  INSERT INTO tomi_support_events_upgrade(room_id,sequence,gift_id)
   SELECT room_id,sequence,gift_id FROM tomi_support_events;
  DROP TABLE tomi_support_events;
  ALTER TABLE tomi_support_events_upgrade RENAME TO tomi_support_events;`);
  db.exec('COMMIT');
 }catch(error){db.exec('ROLLBACK');throw error;}
}
