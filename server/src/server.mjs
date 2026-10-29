import { mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';
import { openDatabase } from './database.mjs';
import { createApp } from './app.mjs';
import {moderationOwner} from './moderation.mjs';
import {privacyEnvironment} from './privacy.mjs';
import {fcmFromEnvironment} from './push.mjs';
import {iceFromEnvironment} from './ice.mjs';
import {roomProviderFromEnvironment} from './room_provider.mjs';
import { r2FromEnvironment, chatR2FromEnvironment } from './r2.mjs';

const production = process.env.NODE_ENV === 'production';
const sqliteFile = process.env.TOMI_SQLITE_FILE;
if (sqliteFile && !production && sqliteFile !== ':memory:') await mkdir(dirname(sqliteFile), { recursive: true });
const database = await openDatabase({ connectionString: process.env.DATABASE_URL, sqliteFile, production });
const storage = r2FromEnvironment();
const server = await createApp({
  storage,
  pushSender:fcmFromEnvironment(),
  iceProvider:iceFromEnvironment(),
  roomProvider:roomProviderFromEnvironment(),
  chatStorage:chatR2FromEnvironment(process.env,storage),
  database,
  ownerUserId:moderationOwner(),
  privacyConfig:privacyEnvironment(),
  trustProxy: process.env.TRUST_PROXY === '1',
  origins: (process.env.CORS_ORIGINS || '').split(',').map((origin) => origin.trim()).filter(Boolean),
});
const port = Number(process.env.PORT || 10000);
server.listen(port, '0.0.0.0', () => console.log(`TOMI API1.5.0-beta.1 listening on port ${port}`));

// Opportunistic retention cleanup; there are no passwords or raw tokens in these tables.
const cleanup = setInterval(() => {
  database.query('DELETE FROM tomi_sessions WHERE expires_at <= ?', [new Date().toISOString()])
    .then(() => database.query('DELETE FROM tomi_rate_limits WHERE window_started < ?', [Date.now() - 86400000]))
    .then(() => server.cleanupMedia())
    .catch((error) => console.error('Cleanup failed:', error.code || error.name));
}, 300000);
cleanup.unref();
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.once(signal, () => {
    clearInterval(cleanup);
    const deadline = setTimeout(() => process.exit(1), 10000);
    deadline.unref();
    server.close(() => database.close().then(() => process.exit(0)));
  });
}
