import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtemp, writeFile, readFile, rm, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { videoMetadata } from './video.mjs';
const max = 25 * 1024 * 1024;
export async function transcodeVideo(input, output, height, { binary = 'ffmpeg', timeout = 120000, signal } = {}) {
    if (![540, 720].includes(height))
        throw Error('VIDEO_HEIGHT');
    const args = ['-nostdin', '-hide_banner', '-loglevel', 'error', '-y', '-threads', '1', '-filter_threads', '1', '-protocol_whitelist', 'file,pipe', '-enable_drefs', '0', '-i', input, '-map', '0:v:0', '-map', '0:a:0?', '-map_metadata', '-1', '-map_chapters', '-1', '-t', '180', '-vf', `scale=w='min(${height},iw)':h='min(${height},ih)':force_original_aspect_ratio=decrease:force_divisible_by=2`, '-c:v', 'libx264', '-preset', 'veryfast', '-crf', height === 540 ? '27' : '25', '-maxrate', height === 540 ? '700k' : '1000k', '-bufsize', height === 540 ? '1400k' : '2000k', '-c:a', 'aac', '-b:a', '96k', '-movflags', '+faststart', output];
    await new Promise((resolve, reject) => { const p = spawn(binary, args, { stdio: ['ignore', 'ignore', 'pipe'] }); let size = 0, overflow = false; p.stderr.on('data', b => { size += b.length; if (size > 65536) {
        overflow = true;
        p.kill('SIGKILL');
    } }); const stop = () => p.kill('SIGKILL'); signal?.addEventListener('abort', stop, { once: true }); if (signal?.aborted)
        stop(); const timer = setTimeout(stop, timeout); p.once('error', e => { clearTimeout(timer); reject(e); }); p.once('close', code => { signal?.removeEventListener('abort', stop); clearTimeout(timer); if (code === 0 && !overflow)
        resolve();
    else
        reject(Error('VIDEO_TRANSCODE_FAILED')); }); });
    const info = await stat(output);
    if (info.size < 16 || info.size > max)
        throw Error('VIDEO_OUTPUT_SIZE');
    return videoMetadata(await readFile(output));
}
export function createVideoWorker({ database, storage, chatStorage, binary, auto = true, convert = transcodeVideo }) {
    const abort = new AbortController();
    let closed = false, running = false;
    async function scan() { for (const table of ['tomi_video_uploads', 'tomi_private_uploads'])
        await database.query(`INSERT INTO tomi_video_jobs(upload_id,user_id,source_table,object_key) SELECT u.id,u.user_id,?,u.object_key FROM ${table} u WHERE u.state='attached' ${table === 'tomi_private_uploads' ? "AND u.kind='video'" : ''} AND NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts d WHERE d.user_id=u.user_id) AND NOT EXISTS(SELECT 1 FROM tomi_video_jobs j WHERE j.upload_id=u.id) ORDER BY u.created_at LIMIT 10 ON CONFLICT(upload_id) DO NOTHING`, [table]); }
    async function tick() {
        if (closed || running || !binary)
            return;
        running = true;
        let job, dir;
        try {
            await scan();
            job = await database.transaction(async (db) => { const r = (await db.query("SELECT * FROM tomi_video_jobs WHERE state<>'ready' AND state<>'cancelled' AND attempts<3 AND next_at<=? AND lease_until<=? ORDER BY next_at,upload_id LIMIT 1", [Date.now(), Date.now()])).rows[0]; if (!r)
                return; const claimed = await db.query('UPDATE tomi_video_jobs SET lease_until=?,attempts=attempts+1 WHERE upload_id=? AND lease_until<=? RETURNING upload_id', [Date.now() + 300000, r.upload_id, Date.now()]); return claimed.rows.length ? r : null; });
            if (!job)
                return;
            const store = job.object_key.startsWith('tomi/chat-') ? chatStorage : storage;
            if (!store?.putDerived)
                throw Error('VIDEO_STORAGE_UNAVAILABLE');
            const source = (await database.query('SELECT * FROM ' + job.source_table + ' WHERE id=? AND state=?', [job.upload_id, 'attached'])).rows[0];
            if (!source)
                throw Error('VIDEO_SOURCE_GONE');
            const r = await store.fetcher(store.privateReadUrl(job.object_key), { signal: AbortSignal.any([AbortSignal.timeout(30000), abort.signal]), redirect: 'error' });
            if (!r.ok)
                throw Error('VIDEO_DOWNLOAD_FAILED');
            const chunks = [];
            let bytes = 0;
            for await (const b of r.body) {
                bytes += b.length;
                if (bytes > max) {
                    await r.body.cancel().catch(() => { });
                    throw Error('VIDEO_SOURCE_SIZE');
                }
                chunks.push(b);
            }
            if (bytes !== Number(source.byte_length) || createHash('md5').update(Buffer.concat(chunks)).digest('base64') !== source.content_md5)
                throw Error('VIDEO_SOURCE_CHANGED');
            dir = await mkdtemp(join(tmpdir(), 'tomi-video-'));
            const input = join(dir, 'source.mp4');
            await writeFile(input, Buffer.concat(chunks), { mode: 0o600 });
            for (const height of [540, 720]) {
                if (closed)
                    break;
                const output = join(dir, height + '.mp4');
                await convert(input, output, height, { binary, signal: abort.signal });
                const content = await readFile(output), key = job.object_key + '.' + height + '.mp4';
                await database.transaction(async (db) => { await db.query('UPDATE tomi_users SET updated_at=updated_at WHERE id=?', [job.user_id]); if ((await db.query('SELECT 1 FROM tomi_deleted_accounts WHERE user_id=?', [job.user_id])).rows.length || !(await db.query('SELECT 1 FROM ' + job.source_table + " WHERE id=? AND state='attached'", [job.upload_id])).rows.length)
                    throw Error('VIDEO_SOURCE_GONE'); await store.putDerived(key, content); await db.query('INSERT INTO tomi_video_renditions(upload_id,height,user_id,object_key,byte_length) VALUES(?,?,?,?,?) ON CONFLICT(upload_id,height) DO UPDATE SET byte_length=excluded.byte_length', [job.upload_id, height, job.user_id, key, content.length]); });
            }
            if (!closed)
                await database.query("UPDATE tomi_video_jobs SET state='ready',lease_until=0 WHERE upload_id=?", [job.upload_id]);
        }
        catch (e) {
            if (job)
                await database.query("UPDATE tomi_video_jobs SET state=?,lease_until=0,next_at=? WHERE upload_id=?", [e.message === 'VIDEO_SOURCE_GONE' ? 'cancelled' : 'pending', Date.now() + 60000, job.upload_id]).catch(() => { });
        }
        finally {
            if (dir)
                await rm(dir, { recursive: true, force: true });
            running = false;
        }
    }
    const timer = binary && auto ? setInterval(() => void tick(), 10000) : null;
    timer?.unref();
    return { tick, close() { closed = true; abort.abort(); if (timer)
            clearInterval(timer); } };
}
