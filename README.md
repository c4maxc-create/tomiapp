# TOMI 0.4 — private chats

Flutter Arabic RTL app and Node 24 API, updated from TOMI-0.3-posts-r2.zip.
Existing accounts, recovery, profiles, follows, posts, likes and comments remain.
The database migration adds tables and indexes. Keep the existing DATABASE_URL.

This is source code. Follow START_HERE_AR.md to update your existing Northflank
service and build TOMI-0.4.0.apk in GitHub Actions.

## Features

- Start private chats from a profile, search result or the messages tab.
- Persisted text and images; one conversation per user pair.
- Authenticated WebSocket updates, typing, reconnect with backoff and foreground
  HTTP catch-up every 30 seconds. There are no push notifications in this version.
- Global/per-chat unread counts and sent/read markers. Sent means saved on the
  server. Read means viewed at the latest messages while the app is in the foreground.
- Paginated history and a virtualized list. The client holds up to 500 messages
  per window; older history stays accessible with a return-to-latest action.
- Failed sends have explicit retry controls. A frozen nonce and payload prevent
  duplication after a successful save with a lost reply.
- Sender-only deletion for both participants, preserving a tombstone and nonce.
- Block/unblock private messaging in both directions while preserving history.
  Blocking does not alter follows, profiles or feed visibility.
- Gallery preview and Android interrupted-selection recovery into the correct
  chat, still requiring an explicit send.

Text supports 2,000 Unicode code points. Images support JPEG, PNG, WebP and GIF,
up to 10 MiB and 36 million pixels. Verified direct R2 uploads check owner, thread,
signature, size, dimensions and checksum. PUT signs a create-only precondition.
Chat image GET URLs expire after five minutes and can refresh. Cleanup waits at
least 20 minutes after deletion; abandoned uploads expire after a day.

Saved messages survive app/service restarts. Unsent/failed drafts are held in
memory for the signed-in session; closing the app or logging out may discard them.
The client limits pending drafts to 20 and pending image bytes to 20 MiB.

## Hosting and private image storage

Retain NODE_ENV=production, PostgreSQL DATABASE_URL, the current PORT and
TRUST_PROXY=1 behind the trusted hosting reverse proxy. Production refuses
SQLite fallback. For local development use an explicit TOMI_SQLITE_FILE.

A private existing R2 bucket can serve posts and chats using the existing four
R2_ACCOUNT_ID, R2_BUCKET_NAME, R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY settings.
The chat bucket must have public r2.dev access and public custom domains disabled.
Signed URLs alone do not make a public bucket private.

If your existing feed bucket is public, keep it for posts and use a separate
private chat bucket with all four settings:

```text
R2_CHAT_ACCOUNT_ID
R2_CHAT_BUCKET_NAME
R2_CHAT_ACCESS_KEY_ID
R2_CHAT_SECRET_ACCESS_KEY
```

With R2_PUBLIC_BASE_URL configured, chat images stay disabled until a separate
bucket is configured; text chats work. Partial R2 configuration fails startup.
The API cannot discover public-access settings in the Cloudflare dashboard;
check them before enabling images. Choose and retain the chat bucket before
sending photos: object keys are not automatically migrated between buckets.
Do not apply lifecycle deletion rules to attached image prefixes.

Native Android needs no browser CORS policy. A web client needs CORS_ORIGINS and
an R2 policy for its origin on each bucket; see server/r2-cors.example.json.
server/.env.example documents hosting variables and is not auto-loaded by Node.

WebSocket authentication uses the first frame, never a URL token. Revoking a
session closes its sockets. Events carry invalidations; authenticated REST reads
message contents after transaction commit. Only participants access a chat.
Messages are stored on the server; end-to-end encryption is outside this version.

Use one API instance for immediate realtime updates. Multiple replicas share
PostgreSQL history but require a future event broker for instant cross-instance
fanout; foreground HTTP catch-up still works. No production load capacity is
established by functional tests. Calls, rooms, stories, multiplayer and currency
continue as labeled previews.

## Chat API

Every route requires a signed-in account. Existing account/social APIs remain.

| Method | Path | Purpose |
| --- | --- | --- |
| GET / POST | /v1/chats | List and total unread / open by userId |
| GET | /v1/chats/:id | Participant-only metadata |
| GET / POST | /v1/chats/:id/messages | Sequence pagination / idempotent send |
| GET / DELETE | /v1/chats/:id/messages/:messageId | Refresh / sender deletion |
| PUT | /v1/chats/:id/read | Monotonic bounded read marker |
| POST | /v1/chats/:id/images | Prepare scoped image upload |
| GET | /v1/chat/blocks | Blocked users |
| PUT | /v1/chat/blocks/:userId | Explicit blocked boolean |
| WebSocket | /v1/chat/socket | Authentication, invalidations and typing |

/health identifies 0.4.0. See VALIDATION.md for checks and their limits.
GitHub Actions tests SQLite and PostgreSQL 17, analyzes Dart, runs Flutter tests
and builds a debug APK. Release signing and store publication are separate work.

Local checks:

```sh
cd server
npm ci --ignore-scripts --no-audit --no-fund
npm test
```

From the project root:

```sh
flutter pub get
flutter analyze
flutter test
python3 tool/check_bootstrap.py
```

References: [Flutter WebSockets](https://docs.flutter.dev/cookbook/networking/web-sockets),
[ws](https://github.com/websockets/ws),
[R2 presigned URLs](https://developers.cloudflare.com/r2/api/s3/presigned-urls/),
[R2 public access](https://developers.cloudflare.com/r2/buckets/public-buckets/).
