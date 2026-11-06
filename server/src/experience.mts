import { randomUUID } from 'node:crypto';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { ApiError } from './security.mjs';
import { roomLifetime } from './room_policy.mjs';
import type { ExperienceDependencies, CurrentUser, SessionView, ClientMetric, Row } from './contracts.mts';
const stamp = () => new Date().toISOString();
const uuid = (v: unknown): v is string => typeof v === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(v);
function object(value: unknown): Record<string, unknown> { if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new ApiError(400, 'VALIDATION', 'طلب غير صحيح.'); return value as Record<string, unknown>; }
function fields(d: Record<string, unknown>, allowed: string[]): void { if (Object.keys(d).some(k => !allowed.includes(k)))
    throw new ApiError(400, 'VALIDATION', 'حقل غير مسموح.'); }
const text = (r: Row, k: string) => String(r[k] ?? '');
const error = (code: string, message: string, status = 400): never => { throw new ApiError(status, code, message); };
export function createExperience(deps: ExperienceDependencies) {
    const { database, readJson, respond, limit } = deps;
    async function ensureSessions(user: string) { const rows = (await database.query('SELECT s.token_hash,s.created_at FROM tomi_sessions s LEFT JOIN tomi_session_devices d ON d.session_hash=s.token_hash WHERE s.user_id=? AND s.expires_at>? AND d.id IS NULL ORDER BY s.created_at DESC LIMIT 100', [user, stamp()])).rows; for (const r of rows)
        await database.query('INSERT INTO tomi_session_devices(id,session_hash,user_id,label,platform,last_seen_at) VALUES(?,?,?,?,?,?) ON CONFLICT(session_hash) DO NOTHING', [randomUUID(), r.token_hash, user, 'جهاز TOMI', 'unknown', r.created_at]); }
    async function sessions(c: CurrentUser): Promise<SessionView[]> { await ensureSessions(c.id); return (await database.query('SELECT d.*,s.created_at,s.expires_at FROM tomi_session_devices d JOIN tomi_sessions s ON s.token_hash=d.session_hash WHERE d.user_id=? AND s.user_id=? AND s.expires_at>? ORDER BY s.created_at DESC,d.id LIMIT 100', [c.id, c.id, stamp()])).rows.map(r => ({ id: text(r, 'id'), label: text(r, 'label'), platform: text(r, 'platform'), createdAt: text(r, 'created_at'), lastSeenAt: text(r, 'last_seen_at'), expiresAt: text(r, 'expires_at'), current: r.session_hash === c.tokenHash })); }
    async function revoke(c: CurrentUser, id: string | null) { const removed = await database.transaction(async (db) => { await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING id', [c.id]); if (id) {
        const d = (await db.query('SELECT session_hash FROM tomi_session_devices WHERE id=? AND user_id=?', [id, c.id])).rows[0];
        if (!d)
            error('SESSION_NOT_FOUND', 'الجهاز غير موجود.', 404);
        if (d.session_hash === c.tokenHash)
            error('CURRENT_SESSION', 'استخدم تسجيل الخروج لهذا الجهاز.');
        return (await db.query('DELETE FROM tomi_sessions WHERE token_hash=? AND user_id=? RETURNING token_hash', [d.session_hash, c.id])).rows;
    } return (await db.query('DELETE FROM tomi_sessions WHERE user_id=? AND token_hash<>? RETURNING token_hash', [c.id, c.tokenHash])).rows; }); for (const r of removed)
        deps.invalidateSession(text(r, 'token_hash')); await deps.afterRevoke(); return removed.length; }
    return { async handle(req: IncomingMessage, res: ServerResponse, url: URL, c: CurrentUser): Promise<boolean> {
            const path = url.pathname, method = req.method;
            if (path === '/v1/search' && method === 'GET') {
                await limit('unified-search:' + c.id, 60);
                const q = (url.searchParams.get('q') ?? '').trim().toLowerCase();
                if ([...q].length < 2) {
                    respond(res, 200, { users: [], rooms: [], posts: [] });
                    return true;
                }
                if ([...q].length > 60)
                    error('VALIDATION', 'البحث حتى60 حرفًا.');
                const pattern = '%' + q.replace(/[\\%_]/g, '\\$&') + '%';
                const visible = "NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts d WHERE d.user_id=u.id) AND NOT EXISTS(SELECT 1 FROM tomi_account_restrictions a WHERE a.user_id=u.id AND a.suspended=1) AND NOT EXISTS(SELECT 1 FROM tomi_user_blocks b WHERE (b.blocker_id=? AND b.blocked_id=u.id) OR (b.blocked_id=? AND b.blocker_id=u.id))";
                const ur = (await database.query(`SELECT u.id FROM tomi_users u WHERE ${visible} AND (LOWER(u.username) LIKE ? ESCAPE '\\' OR LOWER(u.display_name) LIKE ? ESCAPE '\\') ORDER BY u.username LIMIT 15`, [c.id, c.id, pattern, pattern])).rows;
                const rooms = (await database.query(`SELECT r.id,r.title FROM tomi_voice_rooms r JOIN tomi_users u ON u.id=r.owner_id JOIN tomi_room_policy rp ON rp.room_id=r.id WHERE r.state='open' AND (rp.tier='free' OR rp.last_owner_visit>?) AND ${visible} AND LOWER(r.title) LIKE ? ESCAPE '\\' ORDER BY r.created_at DESC,r.id DESC LIMIT 15`, [new Date(Date.now() - roomLifetime).toISOString(), c.id, c.id, pattern])).rows;
                const posts = (await database.query(`SELECT p.id,p.user_id,p.body,p.created_at FROM tomi_posts p JOIN tomi_users u ON u.id=p.user_id WHERE ${visible} AND COALESCE((SELECT audience FROM tomi_post_options o WHERE o.post_id=p.id),'public')='public' AND NOT EXISTS(SELECT 1 FROM tomi_content_moderation m WHERE m.target_type='post' AND m.target_id=p.id AND m.hidden=1) AND LOWER(p.body) LIKE ? ESCAPE '\\' ORDER BY p.created_at DESC,p.id DESC LIMIT 15`, [c.id, c.id, pattern])).rows;
                const ids = [...new Set([...ur.map(r => text(r, 'id')), ...posts.map(r => text(r, 'user_id'))])], users = await deps.usersByIds(ids, c.id);
                respond(res, 200, { users: ur.map(r => users.get(text(r, 'id'))).filter(Boolean), rooms, posts: posts.map(r => ({ id: r.id, text: r.body, createdAt: r.created_at, author: users.get(text(r, 'user_id')) ?? null })) });
                return true;
            }
            if (path === '/v1/me/sessions' && method === 'GET') {
                respond(res, 200, { sessions: await sessions(c) });
                return true;
            }
            if (path === '/v1/me/sessions/current' && method === 'PUT') {
                await limit('session-label:' + c.id, 30);
                const d = object(await readJson(req));
                fields(d, ['label', 'platform']);
                if (typeof d.label !== 'string' || d.label.trim().length < 1 || [...d.label].length > 40 || !['android', 'ios', 'web', 'desktop', 'unknown'].includes(String(d.platform)))
                    error('VALIDATION', 'اسم الجهاز غير صحيح.');
                await ensureSessions(c.id);
                await database.query('UPDATE tomi_session_devices SET label=?,platform=?,last_seen_at=? WHERE session_hash=? AND user_id=?', [String(d.label).trim(), d.platform, stamp(), c.tokenHash, c.id]);
                respond(res, 200, { sessions: await sessions(c) });
                return true;
            }
            const one = path.match(/^\/v1\/me\/sessions\/([a-f0-9-]{36})$/);
            if ((one && method === 'DELETE') || (path === '/v1/me/sessions/revoke-others' && method === 'POST')) {
                await limit('session-revoke:' + c.id, 15);
                respond(res, 200, { removed: await revoke(c, one?.[1] ?? null), sessions: await sessions(c) });
                return true;
            }
            if (path === '/v1/me/collections' && method === 'GET') {
                respond(res, 200, { collections: (await database.query('SELECT c.id,c.name,(SELECT COUNT(*) FROM tomi_collection_items i WHERE i.collection_id=c.id) AS count FROM tomi_saved_collections c WHERE c.user_id=? ORDER BY c.created_at,c.id', [c.id])).rows });
                return true;
            }
            if (path === '/v1/me/collections' && method === 'POST') {
                await limit('collections:' + c.id, 30);
                const d = object(await readJson(req));
                fields(d, ['id', 'name']);
                if (!uuid(d.id) || typeof d.name !== 'string' || d.name.trim().length < 1 || [...d.name].length > 40)
                    error('VALIDATION', 'اكتب اسم مجموعة حتى40 حرفًا.');
                await database.transaction(async (db) => { await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=? RETURNING id', [c.id]); const old = (await db.query('SELECT name FROM tomi_saved_collections WHERE id=? AND user_id=?', [d.id, c.id])).rows[0]; if (old) {
                    if (old.name !== String(d.name).trim())
                        error('REQUEST_CHANGED', 'اسم المجموعة تغيّر.');
                    return;
                } if (Number((await db.query('SELECT COUNT(*) AS n FROM tomi_saved_collections WHERE user_id=?', [c.id])).rows[0]?.n) >= 30)
                    error('COLLECTION_LIMIT', 'الحد30 مجموعة.'); await db.query('INSERT INTO tomi_saved_collections(id,user_id,name,created_at) VALUES(?,?,?,?)', [d.id, c.id, String(d.name).trim(), stamp()]); });
                respond(res, 201, { saved: true });
                return true;
            }
            const collection = path.match(/^\/v1\/me\/collections\/([a-f0-9-]{36})(?:\/posts\/([a-f0-9-]{36}))?$/);
            if (collection) {
                const id = collection[1]!;
                if (!(await database.query('SELECT 1 FROM tomi_saved_collections WHERE id=? AND user_id=?', [id, c.id])).rows.length)
                    error('NOT_FOUND', 'المجموعة غير موجودة.', 404);
                if (!collection[2] && method === 'DELETE') {
                    await database.query('DELETE FROM tomi_saved_collections WHERE id=? AND user_id=?', [id, c.id]);
                    respond(res, 200, { deleted: true });
                    return true;
                }
                if (!collection[2] && method === 'GET') {
                    const raw = url.searchParams.get('before');
                    if (raw && !uuid(raw))
                        error('VALIDATION', 'صفحة غير صحيحة.');
                    const ids = (await database.query('SELECT post_id FROM tomi_collection_items WHERE collection_id=? AND user_id=?' + (raw ? ' AND post_id<?' : '') + ' ORDER BY post_id DESC LIMIT 21', raw ? [id, c.id, raw] : [id, c.id])).rows;
                    const posts: unknown[] = [];
                    for (const r of ids.slice(0, 20)) {
                        try {
                            posts.push(await deps.getPost(text(r, 'post_id'), c.id));
                        }
                        catch (e) {
                            if ((e as {
                                status?: number;
                            }).status !== 404)
                                throw e;
                        }
                    }
                    respond(res, 200, { posts, nextCursor: ids.length > 20 ? ids[19]?.post_id : null });
                    return true;
                }
                if (collection[2] && ['PUT', 'DELETE'].includes(method ?? '')) {
                    const post = collection[2];
                    if (method === 'PUT') {
                        if (!(await database.query('SELECT 1 FROM tomi_post_saves WHERE post_id=? AND user_id=?', [post, c.id])).rows.length)
                            error('NOT_SAVED', 'احفظ المنشور أولًا.');
                        await database.query('INSERT INTO tomi_collection_items(collection_id,user_id,post_id) VALUES(?,?,?) ON CONFLICT(collection_id,user_id,post_id) DO NOTHING', [id, c.id, post]);
                    }
                    else
                        await database.query('DELETE FROM tomi_collection_items WHERE collection_id=? AND user_id=? AND post_id=?', [id, c.id, post]);
                    respond(res, 200, { saved: method === 'PUT' });
                    return true;
                }
            }
            if (path === '/v1/diagnostics/metrics' && method === 'POST') {
                await limit('client-metrics:' + c.id, 6);
                const d = object(await readJson(req));
                fields(d, ['metrics']);
                if (!Array.isArray(d.metrics) || d.metrics.length < 1 || d.metrics.length > 30)
                    error('VALIDATION', 'قياسات غير صحيحة.');
                const metrics: ClientMetric[] = [];
                for (const value of d.metrics as unknown[]) {
                    const m = object(value);
                    fields(m, ['kind', 'area', 'bucket', 'count', 'build']);
                    if (!['flutter_error', 'api_latency', 'slow_frame'].includes(String(m.kind)) || !['ui', 'chat', 'feed', 'games', 'calling', 'live'].includes(String(m.area)) || !Number.isInteger(m.bucket) || Number(m.bucket) < 0 || Number(m.bucket) > 6 || !Number.isInteger(m.count) || Number(m.count) < 1 || Number(m.count) > 1000 || !Number.isInteger(m.build) || Number(m.build) < 1 || Number(m.build) > 100000)
                        error('VALIDATION', 'قياسات غير صحيحة.');
                    metrics.push(m as unknown as ClientMetric);
                }
                const day = stamp().slice(0, 10);
                await database.transaction(async (db) => { for (const m of metrics)
                    await db.query('INSERT INTO tomi_client_metrics(day,kind,area,bucket,build,total) VALUES(?,?,?,?,?,?) ON CONFLICT(day,kind,area,bucket,build) DO UPDATE SET total=tomi_client_metrics.total+excluded.total', [day, m.kind, m.area, m.bucket, m.build, m.count]); await db.query('DELETE FROM tomi_client_metrics WHERE day<?', [new Date(Date.now() - 30 * 86400000).toISOString().slice(0, 10)]); });
                respond(res, 202, { accepted: true });
                return true;
            }
            return false;
        } };
}
