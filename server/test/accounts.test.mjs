import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { once } from 'node:events';
import { openDatabase } from '../src/database.mjs';
import { createApp } from '../src/app.mjs';
import { digest } from '../src/security.mjs';

const password = 'a long password for TOMI';
const secondPassword = 'another long passphrase for TOMI';
const connectionString = process.env.TEST_DATABASE_URL;
if (connectionString) {
  const url = new URL(connectionString);
  assert.ok(['127.0.0.1', 'localhost'].includes(url.hostname) && url.pathname === '/tomi_test',
    'Integration tests only accept the isolated local tomi_test database.');
}

async function fixture(t, options = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'tomi-account-test-'));
  const sqliteFile = join(directory, 'accounts.sqlite');
  let database;
  let server;
  let base;
  async function start(reset = false) {
    database = await openDatabase({ connectionString, sqliteFile });
    if (reset && connectionString) {
      await database.query('DELETE FROM tomi_users');
      await database.query('DELETE FROM tomi_rate_limits');
    }
    server = await createApp({ database, ...options });
    server.listen(0, '127.0.0.1');
    await once(server, 'listening');
    base = `http://127.0.0.1:${server.address().port}`;
  }
  async function stop() {
    if (server) {
      const closed = new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
      server.closeIdleConnections();
      await closed;
      server = null;
    }
    if (database) { await database.close(); database = null; }
  }
  t.after(async () => { await stop(); await rm(directory, { recursive: true, force: true }); });
  await start(true);
  return {
    get database() { return database; },
    get base() { return base; },
    async restart() { await stop(); await start(); },
    async request(method, path, body, token) {
      const response = await fetch(`${base}${path}`, {
        method,
        headers: { ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
          ...(token ? { authorization: `Bearer ${token}` } : {}) },
        ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
      });
      return { status: response.status, data: await response.json(), headers: response.headers };
    },
    async register(username, displayName = 'مستخدم تومي') {
      const response = await this.request('POST', '/v1/auth/register', { username, displayName, password });
      assert.equal(response.status, 201);
      return response.data;
    },
  };
}

test('two accounts persist across server restart; profiles, search and follows are real', async (t) => {
  const app = await fixture(t);
  const alice = await app.register('ALIce', 'أليس');
  const bob = await app.register('bob_user', 'باسم');
  assert.equal(alice.user.username, 'alice');
  assert.equal(alice.user.followersCount, 0);
  assert.equal(alice.user.postsCount, 0);
  const duplicate = await app.request('POST', '/v1/auth/register', { username: 'Alice', displayName: 'آخر', password });
  assert.equal(duplicate.status, 409);
  assert.equal(duplicate.data.error.code, 'USERNAME_TAKEN');

  assert.equal((await app.request('GET', '/v1/me')).status, 401);
  assert.equal((await app.request('GET', '/v1/users?q=bob')).status, 401);
  const found = await app.request('GET', '/v1/users?q=%D8%A8%D8%A7%D8%B3', undefined, alice.token);
  assert.equal(found.data.users.length, 1);
  assert.equal(found.data.users[0].id, bob.user.id);
  assert.equal('password_hash' in found.data.users[0], false);
  assert.equal('recovery_hash' in found.data.users[0], false);

  const target = `/v1/users/${bob.user.id}/follow`;
  for (let attempt = 0; attempt < 2; attempt++) {
    const follow = await app.request('PUT', target, { follow: true }, alice.token);
    assert.equal(follow.status, 200);
    assert.equal(follow.data.user.followersCount, 1);
    assert.equal(follow.data.me.followingCount, 1);
    assert.equal(follow.data.user.isFollowing, true);
  }
  assert.equal((await app.request('PUT', `/v1/users/${alice.user.id}/follow`, { follow: true }, alice.token)).status, 400);
  const forbidden = await app.request('PATCH', '/v1/me', {
    username: 'alice', displayName: 'أليس', bio: '', coins: 999999, id: bob.user.id,
  }, alice.token);
  assert.equal(forbidden.status, 400);

  const edited = await app.request('PATCH', '/v1/me', {
    username: 'alice_new', displayName: 'أليس الجديدة', bio: 'نبذة محفوظة 💜', avatarPreset: 'panda',
  }, alice.token);
  assert.equal(edited.status, 200);
  assert.equal(edited.data.user.id, alice.user.id);
  const taken = await app.request('PATCH', '/v1/me', {
    username: 'bob_user', displayName: 'أليس', bio: '', avatarPreset: 'initials',
  }, alice.token);
  assert.equal(taken.status, 409);
  assert.equal((await app.request('GET', '/v1/me', undefined, bob.token)).data.user.username, 'bob_user');

  const secrets = (await app.database.query('SELECT password_hash, recovery_hash FROM tomi_users WHERE id = ?', [alice.user.id])).rows[0];
  assert.match(secrets.password_hash, /^scrypt\$131072\$8\$1\$/);
  assert.equal(secrets.password_hash.includes(password), false);
  assert.equal(secrets.recovery_hash.includes(alice.recoveryCode), false);
  const stored = (await app.database.query('SELECT token_hash FROM tomi_sessions')).rows;
  assert.ok(stored.some((row) => row.token_hash === digest(alice.token)));
  assert.ok(stored.every((row) => row.token_hash !== alice.token && row.token_hash !== bob.token));

  await app.restart();
  const restored = await app.request('GET', '/v1/me', undefined, alice.token);
  assert.equal(restored.status, 200);
  assert.equal(restored.data.user.username, 'alice_new');
  assert.equal(restored.data.user.bio, 'نبذة محفوظة 💜');
  assert.equal(restored.data.user.avatarPreset, 'panda');
  assert.equal(restored.data.user.followingCount, 1);
  const secondDevice = await app.request('POST', '/v1/auth/login', { username: 'alice_new', password });
  assert.equal(secondDevice.status, 200);
  assert.deepEqual(secondDevice.data.user, restored.data.user);
  assert.notEqual(secondDevice.data.token, alice.token);
  const unfollow = await app.request('PUT', target, { follow: false }, secondDevice.data.token);
  assert.equal(unfollow.data.user.followersCount, 0);
  assert.equal(unfollow.data.me.followingCount, 0);
  assert.equal((await app.request('POST', '/v1/auth/logout', {}, alice.token)).status, 200);
  assert.equal((await app.request('GET', '/v1/me', undefined, alice.token)).status, 401);
  assert.equal((await app.request('GET', '/v1/me', undefined, secondDevice.data.token)).status, 200);
});

test('password changes revoke all old sessions; recovery codes work once and rotate', async (t) => {
  const app = await fixture(t);
  const user = await app.register('secure_user');
  const device2 = await app.request('POST', '/v1/auth/login', { username: 'secure_user', password });
  const wrong = await app.request('POST', '/v1/auth/password', { currentPassword: 'wrong', newPassword: secondPassword }, user.token);
  assert.equal(wrong.status, 400);
  const changed = await app.request('POST', '/v1/auth/password', { currentPassword: password, newPassword: secondPassword }, user.token);
  assert.equal(changed.status, 200);
  for (const token of [user.token, device2.data.token]) {
    assert.equal((await app.request('GET', '/v1/me', undefined, token)).status, 401);
  }
  assert.equal((await app.request('POST', '/v1/auth/login', { username: 'secure_user', password })).status, 401);
  assert.equal((await app.request('POST', '/v1/auth/recover', {
    username: 'secure_user', recoveryCode: user.recoveryCode, password,
  })).status, 400);
  const recovered = await app.request('POST', '/v1/auth/recover', {
    username: 'secure_user', recoveryCode: changed.data.recoveryCode, password,
  });
  assert.equal(recovered.status, 200);
  assert.notEqual(recovered.data.recoveryCode, changed.data.recoveryCode);
  assert.equal((await app.request('GET', '/v1/me', undefined, changed.data.token)).status, 401);
  assert.equal((await app.request('GET', '/v1/me', undefined, recovered.data.token)).status, 200);
  assert.equal((await app.request('POST', '/v1/auth/recover', {
    username: 'secure_user', recoveryCode: changed.data.recoveryCode, password: secondPassword,
  })).status, 400);
  assert.equal((await app.request('POST', '/v1/auth/login', { username: 'secure_user', password })).status, 200);
});

test('concurrent registration cannot create duplicate usernames', async (t) => {
  const app = await fixture(t);
  const register = () => app.request('POST', '/v1/auth/register', { username: 'same_user', displayName: 'متزامن', password });
  const results = await Promise.all([register(), register()]);
  assert.deepEqual(results.map((result) => result.status).sort(), [201, 409]);
  const { rows } = await app.database.query('SELECT COUNT(*) AS total FROM tomi_users');
  assert.equal(Number(rows[0].total), 1);
});

test('failed-login limits survive server restarts and generic errors do not reveal accounts', async (t) => {
  const app = await fixture(t);
  const user = await app.register('rate_user');
  const existing = await app.request('POST', '/v1/auth/login', { username: 'rate_user', password: 'incorrect' });
  const missing = await app.request('POST', '/v1/auth/login', { username: 'missing_user', password: 'incorrect' });
  assert.equal(existing.status, 401);
  assert.deepEqual(existing.data, missing.data);
  const period = 900000;
  const start = Date.now() - (Date.now() % period);
  await app.database.query(`INSERT INTO tomi_rate_limits (bucket_key, window_started, hits) VALUES (?, ?, 10)
    ON CONFLICT (bucket_key) DO UPDATE SET hits = 10, window_started = excluded.window_started`,
    [digest('login:pair:127.0.0.1:rate_user'), start]);
  await app.restart();
  const limited = await app.request('POST', '/v1/auth/login', { username: 'rate_user', password });
  assert.equal(limited.status, 429);
  assert.equal(limited.data.error.code, 'RATE_LIMITED');
  assert.ok(limited.headers.get('retry-after'));
  await app.database.query('DELETE FROM tomi_rate_limits WHERE bucket_key=?',[digest('login:pair:127.0.0.1:rate_user')]);
  await app.database.query(`INSERT INTO tomi_rate_limits(bucket_key,window_started,hits) VALUES(?,?,100) ON CONFLICT(bucket_key) DO UPDATE SET hits=100,window_started=excluded.window_started`,[digest('login:failed:rate_user'),start]);
  assert.equal((await app.request('POST','/v1/auth/login',{username:'rate_user',password})).status,200,'Failed guesses from other IPs cannot lock out a correct password');
  assert.equal((await app.request('POST','/v1/auth/login',{username:'rate_user',password:'incorrect'})).status,429);
  assert.equal((await app.request('GET', '/v1/me', undefined, user.token)).status, 200);
});

test('validation, escaped search, expiry and body limits reject unsafe requests', async (t) => {
  const app = await fixture(t);
  assert.equal((await app.request('POST', '/v1/auth/register', { username: 'valid', displayName: 'صحيح', password: '12345678' })).status, 400);
  const user = await app.register('viewer');
  await app.register('target_one');
  await app.register('targettwo');
  const literal = await app.request('GET', '/v1/users?q=target_', undefined, user.token);
  assert.equal(literal.data.users.length, 1);
  assert.equal(literal.data.users[0].username, 'target_one');
  const injection = await app.request('GET', '/v1/users?q=' + encodeURIComponent("' OR 1=1 --"), undefined, user.token);
  assert.equal(injection.data.users.length, 0);
  assert.equal((await app.request('PUT', `/v1/users/00000000-0000-0000-0000-000000000000/follow`, { follow: true }, user.token)).status, 404);
  assert.equal((await app.request('PATCH', '/v1/me', { username: 'viewer', displayName: 'صحيح', bio: 'x'.repeat(141) }, user.token)).status, 400);
  const response = await fetch(`${app.base}/v1/auth/login`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{broken' });
  assert.equal(response.status, 400);
  const huge = await app.request('POST', '/v1/auth/login', { username: 'viewer', password: 'x'.repeat(20000) });
  assert.equal(huge.status, 413);
  const origin = await fetch(`${app.base}/v1/me`, { headers: { origin: 'https://untrusted.example', authorization: `Bearer ${user.token}` } });
  assert.equal(origin.status, 403);
  await app.database.query('UPDATE tomi_sessions SET expires_at = ? WHERE token_hash = ?', ['2000-01-01T00:00:00.000Z', digest(user.token)]);
  assert.equal((await app.request('GET', '/v1/me', undefined, user.token)).status, 401);
});

test('production refuses ephemeral fallback storage', async () => {
  await assert.rejects(openDatabase({ production: true, sqliteFile: ':memory:' }), /DATABASE_URL is required/);
});
