import {recordNotice} from './notices.mjs';
import { randomUUID } from 'node:crypto';
import { requireContact } from './contact_preferences.mjs';
import { ApiError } from './security.mjs';
import type { ExperienceDependencies, CurrentUser, Database } from './contracts.mts';
import type { IncomingMessage, ServerResponse } from 'node:http';
const now = () => new Date().toISOString();
const fail = (s: number, c: string, m: string): never => { throw new ApiError(s, c, m); };
const uuid = (v: unknown): v is string => typeof v === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(v);
function fields(v: unknown, keys: string[]): Record<string, unknown> { if (!v || typeof v !== 'object' || Array.isArray(v) || Object.keys(v).some(k => !keys.includes(k)))
    fail(400, 'VALIDATION', 'طلب غير صحيح.'); return v as Record<string, unknown>; }
function str(v: unknown, max: number, min = 1): string { if (typeof v !== 'string' || [...v.trim()].length < min || [...v.trim()].length > max)
    fail(400, 'VALIDATION', 'راجع طول النص.'); return (v as string).trim(); }
function list(v: unknown, max: number, size: number): string[] { if (!Array.isArray(v) || v.length > max)
    fail(400, 'VALIDATION', 'قائمة غير صحيحة.'); return [...new Set((v as unknown[]).map(x => str(x, size)))]; }
type Dependencies = Pick<ExperienceDependencies, 'database' | 'readJson' | 'respond' | 'limit'> & {
    role(db: Database, user: string): Promise<string>;
    configured: {
        calls: boolean;
        rooms: boolean;
        live: boolean;
        media: boolean;
    };
};
export function createCommunity(deps: Dependencies) {
    const { database: db, readJson, respond, limit } = deps;
    async function pageRows(table: string, condition: string, args: unknown[], url: URL, size: number) {
        const cursor=url.searchParams.get('cursor');let tail='',values=[...args];
        if(cursor){if(!uuid(cursor))fail(400,'VALIDATION','صفحة غير صحيحة.');const prior=(await db.query('SELECT id,created_at FROM '+table+' WHERE id=? AND '+condition,[cursor,...args])).rows[0];if(!prior)fail(400,'VALIDATION','حدّث القائمة.');tail=' AND (created_at<? OR (created_at=? AND id<?))';values.push(prior.created_at,prior.created_at,prior.id);}
        const rows=(await db.query('SELECT * FROM '+table+' WHERE '+condition+tail+' ORDER BY created_at DESC,id DESC LIMIT '+(size+1),values)).rows;
        return {items:rows.slice(0,size),nextCursor:rows.length>size?rows[size-1].id:null};
    }
    async function staff(c: CurrentUser) { if (await deps.role(db, c.id) !== 'owner')
        fail(403, 'FORBIDDEN', 'الرد للإدارة المالكة فقط.'); }
    async function roomAccess(database: Database, room: string, user: string, owner = false) { const row = (await database.query("SELECT owner_id FROM tomi_voice_rooms WHERE id=? AND state='open'", [room])).rows[0]; if (!row || owner && row.owner_id !== user || !owner && row.owner_id !== user && !(await database.query("SELECT 1 FROM tomi_voice_members WHERE room_id=? AND user_id=? AND state='active'", [room, user])).rows.length)
        fail(404, 'ROOM_NOT_FOUND', 'الغرفة غير متاحة.'); }
    async function poll(id: string, c: CurrentUser, database = db) { const row = (await database.query('SELECT * FROM tomi_polls WHERE id=?', [id])).rows[0]; if (!row)
        fail(404, 'NOT_FOUND', 'التصويت غير موجود.'); if (row.room_id)
        await roomAccess(database, String(row.room_id), c.id); const options = JSON.parse(String(row.options)) as string[], votes = (await database.query('SELECT choice,COUNT(*) AS total FROM tomi_poll_votes WHERE poll_id=? GROUP BY choice', [id])).rows; return { id: row.id, question: row.question, options, endsAt: row.ends_at, roomId: row.room_id, closed: String(row.ends_at) <= now(), counts: options.map((_, i) => Number(votes.find(x => Number(x.choice) === i)?.total ?? 0)), mine: (await database.query('SELECT choice FROM tomi_poll_votes WHERE poll_id=? AND user_id=?', [id, c.id])).rows[0]?.choice ?? null }; }
    return { async handle(req: IncomingMessage, res: ServerResponse, url: URL, c: CurrentUser): Promise<boolean> {
            const p = url.pathname, m = req.method;
            if (p === '/v1/me/invitations' && m === 'GET') {
                respond(res, 200, { items: (await db.query("SELECT i.*,u.display_name AS sender_name FROM tomi_invitations i JOIN tomi_users u ON u.id=i.sender_id WHERE i.recipient_id=? AND i.expires_at>? AND NOT EXISTS(SELECT 1 FROM tomi_user_blocks b WHERE (b.blocker_id=i.sender_id AND b.blocked_id=?) OR (b.blocker_id=? AND b.blocked_id=i.sender_id)) ORDER BY i.created_at DESC,i.id DESC LIMIT 50", [c.id, now(), c.id, c.id])).rows });
                return true;
            }
            if (p === '/v1/me/invitations' && m === 'POST') {
                await limit('invitation:' + c.id, 30);
                const d = fields(await readJson(req), ['recipientId', 'kind', 'targetId', 'requestId']);
                if (!uuid(d.recipientId) || !uuid(d.targetId) || !uuid(d.requestId) || d.recipientId === c.id || !['room', 'game', 'live'].includes(String(d.kind)))
                    fail(400, 'VALIDATION', 'دعوة غير صحيحة.');
                await requireContact(db, d.recipientId, c.id, d.kind === 'room' ? 'roomInvites' : 'messages');
                const target = (await db.query(d.kind === 'room' ? "SELECT id FROM tomi_voice_rooms WHERE id=? AND owner_id=? AND state='open'" : d.kind === 'game' ? "SELECT id FROM tomi_game_matches WHERE id=? AND host_id=? AND status='waiting'" : "SELECT id FROM tomi_lives WHERE id=? AND user_id=? AND status='live'", [d.targetId, c.id])).rows[0];
                if (!target)
                    fail(404, 'TARGET_UNAVAILABLE', 'ادعُ أصدقاءك إلى غرفتك أو لعبتك أو بثك المفتوح.');
                await db.query('INSERT INTO tomi_invitations(id,sender_id,recipient_id,kind,target_id,created_at,expires_at,request_id) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(sender_id,request_id) DO NOTHING', [randomUUID(), c.id, d.recipientId, d.kind, d.targetId, now(), new Date(Date.now() + 3600000).toISOString(), d.requestId]);
                const item = (await db.query('SELECT * FROM tomi_invitations WHERE sender_id=? AND request_id=?', [c.id, d.requestId])).rows[0];
                if (item.recipient_id !== d.recipientId || item.kind !== d.kind || item.target_id !== d.targetId)
                    fail(409, 'REQUEST_CHANGED', 'تغيّرت الدعوة.');
                respond(res, 201, { invitation: item });
                return true;
            }
            const invitation = /^\/v1\/me\/invitations\/([a-f0-9-]{36})$/.exec(p);
            if (invitation && m === 'PUT') {
                await limit('invitation-answer:' + c.id, 90);
                const d = fields(await readJson(req), ['state']);
                if (!['accepted', 'declined'].includes(String(d.state)))
                    fail(400, 'VALIDATION', 'اختيار غير صحيح.');
                const item = await db.transaction(async (tx) => { await tx.query('UPDATE tomi_invitations SET state=state WHERE id=? AND recipient_id=?', [invitation[1], c.id]); const item = (await tx.query('SELECT * FROM tomi_invitations WHERE id=? AND recipient_id=?', [invitation[1], c.id])).rows[0]; if (!item || String(item.expires_at) <= now())
                    fail(404, 'NOT_FOUND', 'انتهت الدعوة.'); await requireContact(tx, c.id, String(item.sender_id), item.kind === 'room' ? 'roomInvites' : 'messages'); if (item.state !== 'pending' && item.state !== d.state)
                    fail(409, 'INVITATION_ANSWERED', 'سبق الرد على الدعوة.'); await tx.query('UPDATE tomi_invitations SET state=? WHERE id=?', [d.state, item.id]); let code: null | string = null; if (d.state === 'accepted' && item.kind === 'game') {
                    const row = (await tx.query("SELECT code FROM tomi_game_matches WHERE id=? AND status='waiting'", [item.target_id])).rows[0];
                    if (!row)
                        fail(409, 'TARGET_UNAVAILABLE', 'اللعبة لم تعد بانتظار لاعبين.');
                    code = String(row.code);
                } return { ...item, state: d.state, code }; });
                respond(res, 200, { invitation: item });
                return true;
            }
            if (p === '/v1/me/connection-check' && m === 'GET') {
                respond(res, 200, { serverTime: now(), configured: deps.configured, notice: 'وجود الإعداد ليس اختبار اتصال فعلي؛ جرّب الاتصال على جهازين.' });
                return true;
            }
            if (p === '/v1/me/explore-preferences') {
                if (m === 'GET') {
                    const r = (await db.query('SELECT * FROM tomi_explore_preferences WHERE user_id=?', [c.id])).rows[0];
                    respond(res, 200, { keywords: JSON.parse(String(r?.keywords ?? '[]')), topics: JSON.parse(String(r?.topics ?? '[]')), hidden: (await db.query('SELECT target_type AS type,target_id AS id FROM tomi_explore_hidden WHERE user_id=?', [c.id])).rows });
                    return true;
                }
                if (m === 'PUT') {
                    await limit('explore-prefs:' + c.id, 30);
                    const d = fields(await readJson(req), ['keywords', 'topics']), keywords = list(d.keywords, 30, 40), topics = list(d.topics, 10, 30);
                    await db.query('INSERT INTO tomi_explore_preferences(user_id,keywords,topics) VALUES(?,?,?) ON CONFLICT(user_id) DO UPDATE SET keywords=excluded.keywords,topics=excluded.topics', [c.id, JSON.stringify(keywords), JSON.stringify(topics)]);
                    respond(res, 200, { keywords, topics });
                    return true;
                }
            }
            if (p === '/v1/me/explore-hidden' && (m === 'PUT' || m === 'DELETE')) {
                await limit('explore-hidden:' + c.id, 60);
                const d = fields(await readJson(req), ['type', 'id']);
                if (!['post', 'user'].includes(String(d.type)) || !uuid(d.id))
                    fail(400, 'VALIDATION', 'اختيار غير صحيح.');
                if (m === 'PUT') {
                    if ((await db.query('SELECT 1 FROM tomi_explore_hidden WHERE user_id=?', [c.id])).rows.length >= 500)
                        fail(409, 'LIMIT', 'وصلت حد قائمة الإخفاء.');
                    await db.query('INSERT INTO tomi_explore_hidden(user_id,target_type,target_id) VALUES(?,?,?) ON CONFLICT(user_id,target_type,target_id) DO NOTHING', [c.id, d.type, d.id]);
                }
                else
                    await db.query('DELETE FROM tomi_explore_hidden WHERE user_id=? AND target_type=? AND target_id=?', [c.id, d.type, d.id]);
                respond(res, 200, { ok: true });
                return true;
            }
            if (p === '/v1/me/contact-exceptions') {
                if (m === 'GET') {
                    respond(res, 200, { items: (await db.query('SELECT target_id AS id,kind,allowed FROM tomi_contact_exceptions WHERE user_id=?', [c.id])).rows });
                    return true;
                }
                if (m === 'PUT' || m === 'DELETE') {
                    await limit('contact-exceptions:' + c.id, 30);
                    const d = fields(await readJson(req), ['id', 'kind', 'allowed']);
                    if (!uuid(d.id) || d.id === c.id || !['messages', 'calls', 'roomInvites'].includes(String(d.kind)) || m === 'PUT' && typeof d.allowed !== 'boolean')
                        fail(400, 'VALIDATION', 'اختيار غير صحيح.');
                    if (m === 'PUT') {
                        if (!(await db.query('SELECT id FROM tomi_users WHERE id=?', [d.id])).rows.length)
                            fail(404, 'NOT_FOUND', 'المستخدم غير موجود.');
                        await db.query('INSERT INTO tomi_contact_exceptions(user_id,target_id,kind,allowed) VALUES(?,?,?,?) ON CONFLICT(user_id,target_id,kind) DO UPDATE SET allowed=excluded.allowed', [c.id, d.id, d.kind, d.allowed ? 1 : 0]);
                    }
                    else
                        await db.query('DELETE FROM tomi_contact_exceptions WHERE user_id=? AND target_id=? AND kind=?', [c.id, d.id, d.kind]);
                    respond(res, 200, { ok: true });
                    return true;
                }
            }
            const org = /^\/v1\/chats\/([a-f0-9-]{36})\/organisation$/.exec(p);
            if (org && m === 'PUT') {
                await limit('chat-organise:' + c.id, 90);
                if (!(await db.query('SELECT 1 FROM tomi_chat_members WHERE user_id=? AND thread_id=?', [c.id, org[1]])).rows.length)
                    fail(404, 'CHAT_NOT_FOUND', 'المحادثة غير موجودة.');
                const d = fields(await readJson(req), ['pinned', 'archived', 'markedUnread']);
                if (Object.keys(d).length !== 3 || Object.values(d).some(v => typeof v !== 'boolean'))
                    fail(400, 'VALIDATION', 'اختيار غير صحيح.');
                await db.query('INSERT INTO tomi_chat_organisation(user_id,thread_id,pinned,archived,marked_unread) VALUES(?,?,?,?,?) ON CONFLICT(user_id,thread_id) DO UPDATE SET pinned=excluded.pinned,archived=excluded.archived,marked_unread=excluded.marked_unread', [c.id, org[1], d.pinned ? 1 : 0, d.archived ? 1 : 0, d.markedUnread ? 1 : 0]);
                respond(res, 200, { ok: true });
                return true;
            }
            if(p==='/v1/me/support'&&m==='GET'){const target=url.searchParams.get('targetId');if(target&&!uuid(target))fail(400,'VALIDATION','طلب غير صحيح.');respond(res,200,await pageRows('tomi_support_tickets','user_id=?'+(target?' AND id=?':''),[c.id,...target?[target]:[]],url,50));return true;}
        if (p === '/v1/me/support' && m === 'POST') {
                await limit('support:' + c.id, 5);
                const d = fields(await readJson(req), ['subject', 'body', 'requestId']);
                if (!uuid(d.requestId))
                    fail(400, 'VALIDATION', 'معرف طلب غير صحيح.');
                const subject = str(d.subject, 100), body = str(d.body, 3000);
                const r = await db.transaction(async (tx) => { await tx.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=?', [c.id]); await tx.query('INSERT INTO tomi_support_tickets(id,user_id,subject,body,created_at,updated_at,request_id) VALUES(?,?,?,?,?,?,?) ON CONFLICT(user_id,request_id) DO NOTHING', [randomUUID(), c.id, subject, body, now(), now(), d.requestId]); return (await tx.query('SELECT * FROM tomi_support_tickets WHERE user_id=? AND request_id=?', [c.id, d.requestId])).rows[0]; });
                if (r.subject !== subject || r.body !== body)
                    fail(409, 'REQUEST_CHANGED', 'تغير محتوى الطلب.');
                respond(res, 201, { ticket: r });
                return true;
            }
            if(p==='/v1/admin/support'&&m==='GET'){await staff(c);respond(res,200,await pageRows('tomi_support_tickets','1=1',[],url,100));return true;}
        const ticket = /^\/v1\/admin\/support\/([a-f0-9-]{36})$/.exec(p);
            if (ticket && m === 'PUT') {
                await staff(c);
                await limit('support-reply:' + c.id, 60);
                const d = fields(await readJson(req), ['reply', 'status', 'revision']);
                if (!['open', 'answered', 'closed'].includes(String(d.status)) || !Number.isSafeInteger(d.revision))
                    fail(400, 'VALIDATION', 'طلب غير صحيح.');
                const reply = str(d.reply, 3000);
                const recipient=(await db.query('SELECT user_id FROM tomi_support_tickets WHERE id=?',[ticket[1]])).rows[0];
            if(!recipient)fail(404,'NOT_FOUND','الطلب غير موجود.');
            await db.transaction(async tx=>{
                await tx.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=?',[recipient.user_id]);
                if((await tx.query('SELECT 1 FROM tomi_deleted_accounts WHERE user_id=?',[recipient.user_id])).rows.length)fail(404,'NOT_FOUND','حُذف الحساب.');
                const updated=await tx.query('UPDATE tomi_support_tickets SET reply=?,status=?,revision=revision+1,updated_at=? WHERE id=? AND revision=? RETURNING revision',[reply,d.status,now(),ticket[1],d.revision]);
                if(!updated.rows.length)fail(409,'CHANGED','حدّث الطلب وأعد المحاولة.');
                await recordNotice(tx,{recipientId:String(recipient.user_id),actorId:c.id,kind:'support',targetId:ticket[1],sourceKey:'support:'+ticket[1]+':'+updated.rows[0].revision});
            });
            respond(res, 200, { ok: true });
                return true;
            }
            if (p === '/v1/polls' && m === 'POST') {
                await limit('poll-create:' + c.id, 10);
                const d = fields(await readJson(req), ['question', 'options', 'endsAt', 'requestId', 'roomId']);
                if (!uuid(d.requestId))
                    fail(400, 'VALIDATION', 'طلب غير صحيح.');
                const question = str(d.question, 180), options = list(d.options, 6, 80);
                if (options.length < 2)
                    fail(400, 'VALIDATION', 'اختر خيارين مختلفين على الأقل.');
                const end = Date.parse(String(d.endsAt));
                if (!Number.isFinite(end) || end < Date.now() + 60000 || end > Date.now() + 7 * 86400000)
                    fail(400, 'VALIDATION', 'مدة التصويت من دقيقة إلى أسبوع.');
                const room = d.roomId ?? null;
                if (room !== null) {
                    if (!uuid(room))
                        fail(400, 'VALIDATION', 'غرفة غير صحيحة.');
                    await roomAccess(db, String(room), c.id, true);
                }
                await db.query('INSERT INTO tomi_polls(id,owner_id,room_id,question,options,ends_at,created_at,request_id) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(owner_id,request_id) DO NOTHING', [randomUUID(), c.id, room, question, JSON.stringify(options), new Date(end).toISOString(), now(), d.requestId]);
                const row = (await db.query('SELECT * FROM tomi_polls WHERE owner_id=? AND request_id=?', [c.id, d.requestId])).rows[0];
                if (row.question !== question || row.options !== JSON.stringify(options) || row.room_id !== room || row.ends_at !== new Date(end).toISOString())
                    fail(409, 'REQUEST_CHANGED', 'تغير التصويت.');
                respond(res, 201, { poll: await poll(String(row.id), c) });
                return true;
            }
            if (p === '/v1/polls' && m === 'GET') {
                const room = url.searchParams.get('roomId');
                if (room) {
                    if (!uuid(room))
                        fail(400, 'VALIDATION', 'غرفة غير صحيحة.');
                    await roomAccess(db, room, c.id);
                }
                const rows = (await db.query('SELECT id FROM tomi_polls WHERE ' + (room ? 'room_id=?' : 'room_id IS NULL') + ' ORDER BY created_at DESC,id DESC LIMIT 30', room ? [room] : [])).rows;
                respond(res, 200, { items: await Promise.all(rows.map(r => poll(String(r.id), c))) });
                return true;
            }
            const vote = /^\/v1\/polls\/([a-f0-9-]{36})(\/vote)?$/.exec(p);
            if (vote && m === 'GET' && !vote[2]) {
                respond(res, 200, { poll: await poll(vote[1], c) });
                return true;
            }
            if (vote && m === 'PUT' && vote[2]) {
                await limit('poll-vote:' + c.id, 90);
                const d = fields(await readJson(req), ['choice']);
                await db.transaction(async (tx) => { await tx.query('UPDATE tomi_polls SET question=question WHERE id=?', [vote[1]]); const snapshot = await poll(vote[1], c, tx); if (snapshot.closed)
                    fail(409, 'CLOSED', 'انتهى التصويت.'); if (!Number.isInteger(d.choice) || Number(d.choice) < 0 || Number(d.choice) >= snapshot.options.length)
                    fail(400, 'VALIDATION', 'خيار غير صحيح.'); await tx.query('INSERT INTO tomi_poll_votes(poll_id,user_id,choice) VALUES(?,?,?) ON CONFLICT(poll_id,user_id) DO UPDATE SET choice=excluded.choice', [vote[1], c.id, d.choice]); });
                respond(res, 200, { poll: await poll(vote[1], c) });
                return true;
            }
            if(p==='/v1/me/gift-history'&&m==='GET'){respond(res,200,{trial:true,purchasesEnabled:false,...await pageRows('tomi_room_all_gifts','(sender_id=? OR recipient_id=?)',[c.id,c.id],url,50)});return true;}
        return false;
        } };
}
