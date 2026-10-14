# TOMI 0.5 — voice notes, avatars and optional push

Native Flutter Arabic RTL app and Node 24 API, upgraded from the final 0.4 source.
Keep the existing PostgreSQL DATABASE_URL and hosting service. The schema adds
tables while preserving accounts, recovery, follows, posts and private chats.
This archive contains source, not an APK. Follow START_HERE_AR.md to update
Northflank and build TOMI-0.5.0.apk in GitHub Actions.

## Added features

- Voice notes: AAC/M4A, mono, requested 160 kbps and 44.1 kHz. Record, stop,
  review, record again and explicitly send. Play/pause/seek, one active note per
  chat page. Maximum five minutes and 6 MiB. Recording and playback stop when
  leaving the foreground. Devices may adjust requested encoding settings.
- Voice uploads use the private R2 chat bucket. Verification checks checksum,
  type, length, bounded M4A box structure, sound-track metadata and duration;
  it does not decode or transcode audio. Owner/thread binding is rechecked in the
  message transaction. Stable nonces and upload IDs prevent duplicate retry saves.
- Audio links last five minutes and renew before playback. Sender deletion leaves
  a tombstone and queues cleanup after at least 20 minutes. Abandoned uploads
  expire after a day. The client bounds all pending media to 20 MiB and 20 drafts
  per signed-in session. Unsent drafts are not persisted across app shutdown.
- Profile photos: gallery, preview, save, replace and remove. They appear in
  profiles, search, conversation peers, posts and comments. Interrupted Android
  selection returns to the correct editor/account/API for explicit confirmation.
- Optional FCM HTTP v1 background notifications and account notification settings.
  Permission is requested by an explicit enable action. Notifications contain
  generic text without message content or media URLs. Taps match the signed-in
  account and fetch participant-authorized conversation metadata.
- Device registration binds to valid sessions. Token refresh replaces the
  session device; logout/password/recovery revoke registrations. Switching
  accounts transfers the device and prevents old-account dispatch.
- A transactional persistent outbox has leases, bounded retries and per-device
  receipts. Read/deleted/blocked/opted-out messages are suppressed before
  dispatch. Invalid FCM tokens are removed. Delivery depends on FCM and OS/network
  settings; already queued system notifications cannot be recalled.

Profile photos are visible to other signed-in users, using feed storage and
immutable keys; they are not private chat attachments. Saved messages persist in
PostgreSQL. The account notification preference applies across linked devices.

## Configuration

Retain Node 24, production mode, PostgreSQL, the current PORT and trusted proxy.
The existing four R2 variables serve posts and avatars. A private bucket may
also serve chat images/audio. Disable public r2.dev and public custom domains.
If R2_PUBLIC_BASE_URL is configured, chats need all four R2_CHAT_ACCOUNT_ID,
R2_CHAT_BUCKET_NAME, R2_CHAT_ACCESS_KEY_ID and R2_CHAT_SECRET_ACCESS_KEY settings
for a separate private bucket. Partial configs fail startup. The API cannot
inspect dashboard access policies. Signed URLs do not privatize a public bucket.
Retain the chosen bucket; existing object data is not migrated between buckets.

Push is optional. Northflank FCM_SERVICE_ACCOUNT_JSON is the full server-side
service-account JSON. GitHub TOMI_GOOGLE_SERVICES_JSON is Android client
google-services.json for com.tomi.tomi_app from that same Firebase project.
Never embed the service-account private key in an APK or client-config secret.
The setup script rejects server keys/wrong package names and sets the build flag.
Missing Firebase config disables push while other features continue to work.

The delivery workflow builds Android. Native Android R2 uploads do not need
browser CORS. iOS additionally needs an iOS scaffold, NSMicrophoneUsageDescription,
its Firebase configuration, push capabilities and APNs credentials. A web client
needs browser CORS and a separate recorder implementation.

Use one API instance for immediate chat WebSocket fanout. Multiple replicas
need an event broker for instant cross-instance updates. Functional checks do
not establish production capacity. Calls, rooms, stories, games, currency,
end-to-end encryption and release/store signing remain outside this update.

## New authenticated API

| Method | Route | Purpose |
| --- | --- | --- |
| POST | /v1/chats/:id/audio | Prepare a scoped voice upload |
| POST | /v1/chats/:id/messages | Optional audioUploadId, exclusive with imageUploadId |
| POST | /v1/me/avatar/uploads | Prepare an owned profile photo |
| PUT | /v1/me/avatar | Save/remove via imageUploadId and requestId |
| GET / PUT | /v1/push/settings | Account preference and server config status |
| PUT / DELETE | /v1/push/device | Register/retire this session device |

Health reports 0.5.0. Existing routes remain compatible. See VALIDATION.md.
GitHub runs backend tests against SQLite/PostgreSQL 17, Flutter analysis/tests,
configuration checks, and debug APK compilation.

## Development and continuation

TOMI-PROGRESS.md records completed work, checks, source identities and the next
step. Save it and working source after material steps and before long operations.
Resume from the latest saved working archive without redoing completed stages.
An interruption can still lose work since the last checkpoint; no background
execution is promised when the session ends.

Checks: npm ci --ignore-scripts --no-audit --no-fund and npm test in server;
flutter pub get, flutter analyze, flutter test, python3 tool/check_bootstrap.py
and python3 tool/check_firebase.py from the project root.

Primary references: [record](https://pub.dev/packages/record),
[just_audio](https://pub.dev/packages/just_audio),
[Firebase setup](https://firebase.google.com/docs/flutter/setup),
[FCM Flutter](https://firebase.google.com/docs/cloud-messaging/flutter/get-started),
[notification handling](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages),
[Google services plugin](https://firebase.google.com/docs/android/google-services-plugin-and-file),
[FCM HTTP v1](https://firebase.google.com/docs/cloud-messaging/send/v1-api),
[R2 settings](https://developers.cloudflare.com/r2/buckets/public-buckets/).
