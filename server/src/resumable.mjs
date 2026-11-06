import { ApiError } from './security.mjs';
const chunk = 5 * 1024 * 1024;
const tables = { image_uploads: 'tomi_image_uploads', audio_uploads: 'tomi_audio_uploads', video_uploads: 'tomi_video_uploads', private_uploads: 'tomi_private_uploads' };
export function createResumable({ database, storage, chatStorage, readJson, respond, limit }) {
    return { async handle(req, res, url, c) {
            const m = /^\/v1\/media\/resumable\/(image_uploads|audio_uploads|video_uploads|private_uploads)\/([a-f0-9-]{36})(\/complete)?$/.exec(url.pathname);
            if (!m || req.method !== 'POST')
                return false;
            await limit('resumable:' + c.id, 120);
            const body = await readJson(req);
            if (!body || Array.isArray(body) || Object.keys(body).length)
                throw new ApiError(400, 'VALIDATION', 'طلب غير صحيح.');
            const result = await database.transaction(async (db) => {
                const table = tables[m[1]];
                await db.query('UPDATE ' + table + ' SET expires_at=expires_at WHERE id=? AND user_id=?', [m[2], c.id]);
                const u = (await db.query('SELECT * FROM ' + table + ' WHERE id=? AND user_id=?', [m[2], c.id])).rows[0];
                if (!u || u.state !== 'pending' || u.expires_at <= new Date().toISOString())
                    throw new ApiError(409, 'UPLOAD_INVALID', 'انتهت مهلة الملف؛ أعد تجهيز الرفع.');
                const store = u.object_key.startsWith('tomi/chat-') ? chatStorage : storage;
                if (!store?.supportsMultipart)
                    throw new ApiError(503, 'MULTIPART_DISABLED', 'استكمال الرفع غير مهيأ.');
                if (Number(u.byte_length) <= chunk || Number(u.byte_length) > 25 * 1024 * 1024)
                    throw new ApiError(400, 'VALIDATION', 'الملف خارج حدود الرفع المجزأ.');
                let row = (await db.query('SELECT * FROM tomi_multipart_uploads WHERE upload_id=? AND user_id=?', [u.id, c.id])).rows[0];
                if (row?.completed)
                    return { completed: true };
                if (!row) {
                    await db.query('UPDATE ' + table + ' SET expires_at=? WHERE id=?', [new Date(Date.now() + 86400000).toISOString(), u.id]);
                    const provider = await store.startMultipart(u);
                    await db.query('INSERT INTO tomi_multipart_uploads(upload_id,user_id,provider_id,object_key,created_at) VALUES(?,?,?,?,?)', [u.id, c.id, provider, u.object_key, new Date().toISOString()]);
                    row = { provider_id: provider };
                }
                let parts;
                try {
                    parts = await store.listMultipart(u.object_key, row.provider_id);
                }
                catch (e) {
                    if (e.code !== 'MULTIPART_MISSING')
                        throw e;
                    try {
                        const signed = await import('./media_intents.mjs').then(x => x.uploadWithDigest(db, u));
                        if (m[1] === 'image_uploads')
                            await store.verify(signed);
                        else if (m[1] === 'audio_uploads')
                            await store.verifyAudio(signed);
                        else if (m[1] === 'video_uploads')
                            await store.verifyVideo(signed);
                        else if (!await store.hasMultipartObject(u))
                            throw new ApiError(409, 'UPLOAD_INCOMPLETE', 'missing');
                        await db.query('UPDATE tomi_multipart_uploads SET completed=1 WHERE upload_id=?', [u.id]);
                        return { completed: true };
                    }
                    catch (missing) {
                        if (missing.code !== 'UPLOAD_INCOMPLETE' || m[3])
                            throw missing;
                        const provider = await store.startMultipart(u);
                        await db.query('UPDATE tomi_multipart_uploads SET provider_id=?,completed=0 WHERE upload_id=?', [provider, u.id]);
                        row.provider_id = provider;
                        parts = [];
                    }
                }
                const count = Math.ceil(Number(u.byte_length) / chunk), expected = n => Math.min(chunk, Number(u.byte_length) - (n - 1) * chunk);
                const valid = parts.filter(p => p.number >= 1 && p.number <= count && p.size === expected(p.number));
                if (m[3]) {
                    if (valid.length !== count || new Set(valid.map(p => p.number)).size !== count)
                        throw new ApiError(409, 'UPLOAD_INCOMPLETE', 'بعض أجزاء الملف لم تصل؛ أعد المحاولة.');
                    await store.finishMultipart(u.object_key, row.provider_id, valid.sort((a, b) => a.number - b.number));
                    await db.query('UPDATE tomi_multipart_uploads SET completed=1 WHERE upload_id=?', [u.id]);
                    return { completed: true };
                }
                return { completed: false, chunkSize: chunk, total: Number(u.byte_length), parts: Array.from({ length: count }, (_, i) => ({ number: i + 1, size: expected(i + 1), uploaded: valid.some(p => p.number === i + 1), url: store.partMultipart(u.object_key, row.provider_id, i + 1) })) };
            });
            respond(res, 200, result);
            return true;
        } };
}
