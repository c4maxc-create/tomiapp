# TOMI 0.3 — posts, images and interactions

Updated from the user-provided TOMI-0.2-fixed.zip. Flutter Arabic RTL app and
Node 24 API, with the existing accounts and five-tab design retained.

This is a **source package**, not a compiled APK or a deployed update.
Follow [START_HERE_AR.md](START_HERE_AR.md) to update the existing Northflank
service and build TOMI-0.3.0.apk in the existing GitHub repository.

## New behavior

- Persisted text posts (up to 2,000 Unicode code points) and optional images.
- All, following (including your own posts), and own feeds; author profile feeds.
- Real author information, post counts, likes and comments across devices.
- Explicit idempotent like/unlike, one like per user/post.
- Persisted comments (500 code points), pagination and deletion permissions.
- Owners can delete their posts; comment authors and post owners can delete comments.
- Cursor pagination ordered by creation time and ID, including timestamp ties.
- Stable per-draft request IDs prevent duplicate posts/comments after retries.
- Composer preserves the draft after a failed request and blocks duplicate taps.
- Gallery picker, image preview and Android lost-selection recovery.
- Direct upload to R2: server-issued PUT URL valid for 15 minutes, exact content
  type and Content-MD5, and signed If-None-Match to prohibit overwrites.
- Before publishing, the server verifies ownership, byte length, checksum,
  supported image signature and bounded dimensions. It streams verification
  with a 256 KiB header buffer and at most two simultaneous verifications.
- JPEG, PNG, WebP and GIF; 10 MiB file limit, 36 million pixel limit.
- Stored object keys, not client-provided URLs. R2 credentials stay on the server.
- Private buckets work using signed GET URLs, without a public bucket/domain.
- Expired unattached uploads and deleted-post images are removed periodically.
  Deletion waits at least 20 minutes so an issued PUT URL cannot resurrect data.
- Text posting, likes and comments work without R2 configuration.

The 0.2 authentication, recovery, profiles, search, follows and secure session
behavior is retained. Schema changes only add tables and indexes. Keep the
existing DATABASE_URL to retain the existing accounts and sessions.
Stories, private messaging, voice rooms/calls, multiplayer and real currency
remain future milestones; their existing sections continue as labeled previews.
Custom profile photo uploads and video publishing are outside this update.

## Server configuration

Keep the existing database and hosting settings. Required hosted environment:

```text
NODE_ENV=production
DATABASE_URL=<existing PostgreSQL connection string>
TRUST_PROXY=1
```

Use TRUST_PROXY=1 only behind the trusted hosting reverse proxy. Optional web
clients need an explicit HTTPS CORS_ORIGINS allowlist; native apps do not.

Optional image configuration — set all four or leave all four unset:

```text
R2_ACCOUNT_ID=<Cloudflare account ID, 32 hexadecimal characters>
R2_BUCKET_NAME=<bucket name>
R2_ACCESS_KEY_ID=<bucket-scoped object read/write access key ID>
R2_SECRET_ACCESS_KEY=<secret access key>
```

R2_PUBLIC_BASE_URL is optional. Without it, published images use temporary
signed GET URLs valid for 24 hours; refresh the feed to obtain new URLs.
Never apply a bucket lifecycle rule that deletes the whole tomi/posts/ prefix,
because it includes attached images. The API tracks abandoned uploads itself.
Partial/invalid R2 settings fail startup instead of silently claiming uploads work.
The supplied server/.env.example is documentation: hosting env variables must
be configured in Northflank; Node is not configured to auto-load this file.

Local backend checks with Node 24:

```sh
cd server
npm ci --ignore-scripts --no-audit --no-fund
npm test
```

For local development set TOMI_SQLITE_FILE to an explicit writable file.
Production requires PostgreSQL and refuses temporary SQLite storage.
The GitHub workflow tests SQLite and an isolated PostgreSQL 17 service, then
runs Dart analysis and Flutter tests before building the debug APK.
Tests run sequentially to isolate the shared CI database.

## API additions

| Method | Path | Purpose |
| --- | --- | --- |
| GET | /v1/posts | all/following/mine, optional userId/cursor/limit |
| POST | /v1/posts | text, optional imageUploadId, requestId |
| GET/DELETE | /v1/posts/:id | read / owner deletion |
| PUT | /v1/posts/:id/like | explicit liked boolean |
| GET/POST | /v1/posts/:id/comments | paginated comments / idempotent creation |
| DELETE | /v1/comments/:id | author or post-owner deletion |
| GET | /v1/media/status | image capability and upload limits |
| POST | /v1/media/images | prepare a signed direct upload |

All additions require an authenticated account. /health now identifies 0.3.0.

Validation results are recorded in VALIDATION.md. Physical-phone gallery access,
live Northflank/R2 configuration and Android release signing require their
respective environments. No changes are deployed by extracting this ZIP.

Primary references: [R2 presigned URLs](https://developers.cloudflare.com/r2/api/s3/presigned-urls/),
[R2 S3 compatibility](https://developers.cloudflare.com/r2/api/s3/api/),
[R2 CORS](https://developers.cloudflare.com/r2/buckets/cors/),
[AWS SigV4 test vector](https://docs.aws.amazon.com/AmazonS3/latest/developerguide/sigv4-query-string-auth.html),
[Flutter image picker](https://pub.dev/packages/image_picker).
