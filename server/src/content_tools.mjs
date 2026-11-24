import {recordMentions} from './content_preferences.mjs';
import {ApiError} from './security.mjs';
const uuid=/^[a-f0-9-]{36}$/, fail=(s,c,t)=>{throw new ApiError(s,c,t);};
const fields=(d,keys)=>{if(Object.keys(d).some(k=>!keys.includes(k)))fail(400,'VALIDATION','طلب غير صحيح.');};
export function createContentTools({database,accountGate,readJson,respond,limit,social,emit}){
 async function access(db,viewer,kind,tid,mid,lock=false){
  const group=kind==='groups',table=group?'tomi_group_messages':'tomi_chat_messages',column=group?'group_id':'thread_id';
  if(lock)await db.query(group?'UPDATE tomi_groups SET updated_at=updated_at WHERE id=?':'UPDATE tomi_chat_threads SET updated_at=updated_at WHERE id=?',[tid]);
  const members=group?(await db.query('SELECT user_id,joined_seq FROM tomi_group_members WHERE group_id=? AND left_at IS NULL',[tid])).rows:(await db.query('SELECT user_id,0 AS joined_seq FROM tomi_chat_members WHERE thread_id=?',[tid])).rows;
  const member=members.find(x=>x.user_id===viewer);if(!member)fail(404,'CHAT_NOT_FOUND','المحادثة غير متاحة.');
  const row=(await db.query(`SELECT * FROM ${table} WHERE id=? AND ${column}=? AND sequence>?`,[mid,tid,Number(member.joined_seq)])).rows[0];if(!row)fail(404,'MESSAGE_NOT_FOUND','الرسالة غير متاحة.');
  return {row,table,members,group};
 }
 return {async handle(req,res,url,current){
  const viewer=current.id,path=url.pathname,method=req.method;
  const post=/^\/v1\/posts\/([a-f0-9-]{36})$/.exec(path);
  if(post&&method==='PUT'){
   await limit('post-edit:'+viewer,30);const d=await readJson(req);fields(d,['text','audience','expectedRevision']);
   if(typeof d.text!=='string'||[...d.text.trim()].length>2000||!['public','followers'].includes(d.audience)||!Number.isInteger(d.expectedRevision)||d.expectedRevision<0)fail(400,'VALIDATION','راجع الوصف والجمهور.');
   await database.transaction(async db=>{
    await db.query('UPDATE tomi_posts SET body=body WHERE id=?',[post[1]]);
    const p=(await db.query('SELECT * FROM tomi_posts WHERE id=?',[post[1]])).rows[0];if(!p)fail(404,'POST_NOT_FOUND','المنشور غير متاح.');if(p.user_id!==viewer)fail(403,'FORBIDDEN','تعديل منشوراتك فقط.');
    const old=await social.getPost(post[1],viewer,db);if(!d.text.trim()&&!old.image&&!old.video)fail(400,'VALIDATION','المنشور فارغ.');
    if(old.revision!==d.expectedRevision)fail(409,'POST_CHANGED','تغيّر المنشور؛ حدّثه ثم عدّل.');
    await recordMentions(db,{actor:viewer,text:d.text.trim(),kind:'mention_post',targetId:post[1],gate:accountGate});
    await db.query('UPDATE tomi_posts SET body=? WHERE id=?',[d.text.trim(),post[1]]);
    await db.query('INSERT INTO tomi_post_options(post_id,audience,revision,edited_at) VALUES(?,?,1,?) ON CONFLICT(post_id) DO UPDATE SET audience=excluded.audience,revision=tomi_post_options.revision+1,edited_at=excluded.edited_at',[post[1],d.audience,new Date().toISOString()]);
   });respond(res,200,{post:await social.getPost(post[1],viewer)});return true;
  }
  const batch=/^\/v1\/(chats|groups)\/([a-f0-9-]{36})\/receipts$/.exec(path);
  if(batch&&method==='PUT'){
   await limit('receipts:'+viewer,90);const d=await readJson(req);fields(d,['ids','event']);if(!Array.isArray(d.ids)||d.ids.length<1||d.ids.length>80||d.ids.some(x=>typeof x!=='string'||!uuid.test(x))||!['delivered','read'].includes(d.event))fail(400,'VALIDATION','إيصال غير صحيح.');
   const group=batch[1]==='groups',tid=batch[2],member=(await database.query(group?'SELECT joined_seq FROM tomi_group_members WHERE group_id=? AND user_id=? AND left_at IS NULL':'SELECT 0 AS joined_seq FROM tomi_chat_members WHERE thread_id=? AND user_id=?',[tid,viewer])).rows[0];if(!member)fail(404,'CHAT_NOT_FOUND','المحادثة غير متاحة.');
   const ids=[...new Set(d.ids)],slots=ids.map(()=>'?').join(','),rows=(await database.query(`SELECT id FROM ${group?'tomi_group_messages':'tomi_chat_messages'} WHERE ${group?'group_id':'thread_id'}=? AND sender_id<>? AND sequence>? AND id IN (${slots})`,[tid,viewer,Number(member.joined_seq),...ids])).rows;
   if(rows.length){const time=new Date().toISOString(),values=rows.flatMap(r=>[r.id,viewer,time,d.event==='read'?time:null]);await database.query('INSERT INTO tomi_message_receipts(message_id,user_id,delivered_at,read_at) VALUES '+rows.map(()=>'(?,?,?,?)').join(',')+' ON CONFLICT(message_id,user_id) DO UPDATE SET delivered_at=COALESCE(tomi_message_receipts.delivered_at,excluded.delivered_at),read_at=COALESCE(tomi_message_receipts.read_at,excluded.read_at)',values);}
   respond(res,200,{ok:true});return true;
  }
  const m=/^\/v1\/(chats|groups)\/([a-f0-9-]{36})\/messages\/([a-f0-9-]{36})\/(edit|info|receipt)$/.exec(path);
  if(!m||!uuid.test(m[2])||!uuid.test(m[3]))return false;
  await limit('message-tools:'+viewer,180);
  if(m[4]==='info'&&method==='GET'){
   const {row}=await access(database,viewer,m[1],m[2],m[3]);
   const receipts=(await database.query('SELECT user_id,delivered_at,read_at FROM tomi_message_receipts WHERE message_id=?'+(row.sender_id===viewer?'':' AND user_id=?'),row.sender_id===viewer?[row.id]:[row.id,viewer])).rows;
   const edit=(await database.query('SELECT edited_at FROM tomi_message_edits WHERE message_id=?',[row.id])).rows[0];
   respond(res,200,{sentAt:row.created_at,editedAt:edit?.edited_at??null,receipts:receipts.map(r=>({userId:r.user_id,deliveredAt:r.delivered_at,readAt:r.read_at}))});return true;
  }
  if(m[4]==='receipt'&&method==='PUT'){
   const d=await readJson(req);fields(d,['event']);if(!['delivered','read'].includes(d.event))fail(400,'VALIDATION','حالة الرسالة غير صحيحة.');
   const a=await access(database,viewer,m[1],m[2],m[3]);if(a.row.sender_id===viewer)fail(400,'VALIDATION','الإيصال للطرف المستلم.');
   const time=new Date().toISOString();await database.query('INSERT INTO tomi_message_receipts(message_id,user_id,delivered_at,read_at) VALUES(?,?,?,?) ON CONFLICT(message_id,user_id) DO UPDATE SET delivered_at=COALESCE(tomi_message_receipts.delivered_at,excluded.delivered_at),read_at=COALESCE(tomi_message_receipts.read_at,excluded.read_at)',[m[3],viewer,time,d.event==='read'?time:null]);
   respond(res,200,{ok:true});return true;
  }
  if(m[4]==='edit'&&method==='PUT'){
   const d=await readJson(req);fields(d,['text','expectedRevision']);if(typeof d.text!=='string'||!d.text.trim()||[...d.text.trim()].length>2000||!Number.isInteger(d.expectedRevision)||d.expectedRevision<0)fail(400,'VALIDATION','اكتب نصًا حتى2000 حرف.');
   const a=await database.transaction(async db=>{
    const a=await access(db,viewer,m[1],m[2],m[3],true),r=a.row;if(!a.group&&(await db.query('SELECT 1 FROM tomi_e2ee_threads WHERE thread_id=?',[m[2]])).rows.length)fail(409,'SECURE_REQUIRED','استخدم واجهة المحادثة المشفرة.');if(r.sender_id!==viewer)fail(403,'FORBIDDEN','تعديل رسائلك فقط.');if(r.deleted_at)fail(409,'MESSAGE_DELETED','الرسالة محذوفة.');
    if(!a.group&&(await db.query('SELECT 1 FROM tomi_chat_threads t JOIN tomi_user_blocks b ON (b.blocker_id=t.low_user_id AND b.blocked_id=t.high_user_id) OR (b.blocker_id=t.high_user_id AND b.blocked_id=t.low_user_id) WHERE t.id=?',[m[2]])).rows.length)fail(403,'CHAT_BLOCKED','المراسلة غير متاحة.');
    const revision=a.group?Number(r.revision):Number((await db.query('SELECT revision FROM tomi_chat_message_meta WHERE message_id=?',[r.id])).rows[0]?.revision??0);
    if(revision!==d.expectedRevision)fail(409,'MESSAGE_CHANGED','تغيّرت الرسالة؛ حدّثها ثم عدّل.');
    await db.query(`UPDATE ${a.table} SET body=?${a.group?',revision=revision+1':''} WHERE id=?`,[d.text.trim(),r.id]);
    if(!a.group)await db.query('INSERT INTO tomi_chat_message_meta(message_id,revision) VALUES(?,1) ON CONFLICT(message_id) DO UPDATE SET revision=tomi_chat_message_meta.revision+1',[r.id]);
    await db.query('INSERT INTO tomi_message_edits(message_id,edited_at) VALUES(?,?) ON CONFLICT(message_id) DO UPDATE SET edited_at=excluded.edited_at',[r.id,new Date().toISOString()]);return a;
   });emit(a.members.map(r=>r.user_id),{type:'chat.updated',conversationId:m[2],group:a.group,messageId:m[3]});respond(res,200,{ok:true});return true;
  }
  return false;
 }};
}
