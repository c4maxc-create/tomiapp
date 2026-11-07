import {createFirebaseVerifier,firebaseProject} from './firebase_identity.mjs';
import {edgeKey} from './request_security.mjs';
import {mfaKey} from './mfa.mjs';
import {createVideoWorker} from './video_worker.mjs';
import { mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';
import { openDatabase } from './database.mjs';
import { createApp } from './app.mjs';
import {moderationOwner} from './moderation.mjs';
import {privacyEnvironment} from './privacy.mjs';
import {fcmFromEnvironment} from './push.mjs';
import {iceFromEnvironment} from './ice.mjs';
import {liveProviderFromEnvironment} from './live_provider.mjs';
import {roomProviderFromEnvironment} from './room_provider.mjs';
import { r2FromEnvironment, chatR2FromEnvironment } from './r2.mjs';

const production = process.env.NODE_ENV === 'production';
const sqliteFile = process.env.TOMI_SQLITE_FILE;
if (sqliteFile && !production && sqliteFile !== ':memory:') await mkdir(dirname(sqliteFile), { recursive: true });
const database = await openDatabase({ connectionString: process.env.DATABASE_URL, sqliteFile, production });
const storage = r2FromEnvironment();
const chatStorage=chatR2FromEnvironment(process.env,storage);
const server = await createApp({
  firebaseVerifier:createFirebaseVerifier({projectId:firebaseProject(),enabledProviders:(process.env.TOMI_AUTH_PROVIDERS||'').split(',').map(p=>p.trim()).filter(Boolean)}),
  edgeSecret:edgeKey(process.env.TOMI_EDGE_SECRET),
  mfaEncryptionKey:mfaKey(process.env.TOMI_MFA_KEY),
  requireAdminMfa:process.env.TOMI_REQUIRE_ADMIN_MFA==='1',
  storage,
  pushSender:fcmFromEnvironment(),
  iceProvider:iceFromEnvironment(),
  roomProvider:roomProviderFromEnvironment(),
  liveProvider:liveProviderFromEnvironment(),
  chatStorage,
  database,
  ownerUserId:moderationOwner(),
  privacyConfig:privacyEnvironment(),
  trustProxy: process.env.TRUST_PROXY === '1',
  origins: (process.env.CORS_ORIGINS || '').split(',').map((origin) => origin.trim()).filter(Boolean),
});
const videoWorker=createVideoWorker({database,storage,chatStorage,binary:process.env.TOMI_FFMPEG_BINARY||null});
const port = Number(process.env.PORT || 10000);
server.listen(port, '0.0.0.0', () => console.log(`TOMI API1.5.0-beta.1 listening on port ${port}`));

// Opportunistic retention cleanup; there are no passwords or raw tokens in these tables.
const cleanup = setInterval(() => {
  database.query('DELETE FROM tomi_sessions WHERE expires_at <= ?', [new Date().toISOString()])
    .then(() => database.query('DELETE FROM tomi_rate_limits WHERE window_started < ?', [Date.now() - 86400000]))
    .then(() => database.query('DELETE FROM tomi_security_events WHERE created_at < ?',[new Date(Date.now()-90*86400000).toISOString()]))
    .then(() => server.cleanupMedia())
    .catch((error) => console.error('Cleanup failed:', error.code || error.name));
}, 300000);
cleanup.unref();
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.once(signal, () => {
    clearInterval(cleanup);
    videoWorker.close();
    const deadline = setTimeout(() => process.exit(1), 10000);
    deadline.unref();
    server.close(() => database.close().then(() => process.exit(0)));
  });
}
