# TOMI 1.0 beta1 — privacy, account erasure and Android release preparation

Arabic Flutter social app with Node24/PostgreSQL API. Source version
**1.0.0-beta.1+14**, API **1.0.0-beta.1**, extending the exact final0.12 ZIP.
User authorized this phase on2026-10-17; delivery completed on2026-10-22 (Baghdad).
CI disk fix (2026-10-22): TOMI-1.0-beta1-build-fix.zip adds hosted-runner cleanup,
required-NDK preservation and free-space gates. See CI_BUILD_FIX_AR.md. Runtime code
and app/API versions are unchanged. The new hosted build remains pending.

Start with START_HERE_AR.md, PRIVACY_1.0_BETA_AR.md and RELEASE_1.0_BETA_AR.md.

This is a source delivery. Full Flutter checks, PostgreSQL restore, APK/AAB builds
and physical-device acceptance remain required through Actions and test phones.
VALIDATION.md separates executed checks from those still pending. Earlier0.12
moderation/operations and prior room/call/messaging features remain included.

## Included

- Password-confirmed account erasure in the app and public browser page, immediate
  session/push revocation and call/room shutdown, private receipt recovery after
  a lost response, and account-specific device draft/session cleanup.
- Durable media cleanup across restarts, independent public/private stores, a
  second deletion after old upload URLs expire, and bounded security retention.
- Public Arabic privacy/terms/community/deletion resources, recorded registration
  policy version, and explicit operator/support/retention configuration.
- Optional supplied-key Android APK+AAB signing, pinned certificate verification,
  matching deployed policy/API and device-acceptance gates. Default is debug.
  No production deployment, account erasure or store upload was performed.

- Private account/post/room reports, tracked statuses, separate staff/public notes,
  immutable minimal evidence and stable report request receipts.
- Server-configured platform owner and live moderator permissions, independent of
  room roles. Hide/restore posts, close rooms, owner-only account suspension and
  role grants; revision guards, idempotent actions and private durable audit.
- Suspension revokes sessions and push bindings, ends calls and schedules durable
  SFU removal/owned-room closure. Protected staff/owner targets cannot be bypassed.
- Per-process bounded HTTP/latency/error/memory monitoring and database/media-size
  estimates. No claim of provider billing totals or global multi-instance telemetry.
- AES256GCM encrypted database backups, authenticated no-clobber files, private
  PostgreSQL passfiles, guarded empty-local restore and a PostgreSQL17 CI drill.
- Bounded local-only HTTP load tool and measured isolated sample; no real RTP or
  production load was performed. R2 object backups and scheduling need separate setup.

- Private per-account room favorites and follows, versioned selections and keyset filtered lists.
- Daily, Monday-based weekly and all-time top20 contributor rankings using Asia/Baghdad calendar boundaries.
- Separate server-owned user XP/levels1–10, four earned badges and level-unlocked frames, animated preset portraits and entry styles.
- Three-second gift/entry effects with bounded queues, no historical replay and reduced-motion support.
  New photo selection restores the photo without removing the frame or entrance. No additional native permissions.
- Exact0.10 additive schema upgrade, one-time historical gift backfill and existing call/message behavior retained.

- App-private per-account drafts for chat text/replies/selected files, pending
  messages, posts and room message/gift requests. Atomic checksummed journals
  reference immutable media blobs; all sends persist before HTTP begins.
- Stable request identifiers, upload initialization replay, file SHA256 verification,
  receipt lookup after uncertain commits and bounded foreground chat retries.
  Restored room gifts require explicit user retry; checking a receipt never spends coins.
- Chat replies, six reactions, a shared pin, literal text search with older pages,
  and member/session-authorized older room events. Deleted quoted text stays hidden.
- MP4/H.264 video with optional AAC in chats and posts:25 MB,3 minutes,1080p maximum.
  Playback is opened and started by the user; minimizing or entering a call pauses it.

- Android incoming call cards with answer/decline, session-bound FCM delivery,
  deadline expiry and durable cancellation on all receiving devices.
- User-started Android microphone/media playback foreground service, retained
  Flutter engine, ongoing end/leave controls, and screen-off heartbeats. Video
  capture stops on minimizing and requires a user tap to resume.
- Continuous ICE gathering and bounded candidate retries for network handoffs.
- All 0.8 room gifts/levels/settings and 0.7 accounts/recovery, profiles, follows, posts, private chats, private
  images/voice notes, avatars, optional FCM, call history and voice/video calls.
- LiveKit Cloud audio rooms: named rooms, up to 30 members, a permanently reserved owner seat, an optional companion seat and 8 regular mic seats,
  listener joins, explicit mic enable, requests, approval/refusal, owner and
  moderator roles, administrative mute, speaker removal and participant kicks.
- Server-enforced microphone-only publishing, durable permission/removal jobs,
  session binding, opaque connection identities, short initial join tokens and
  one room/call at a time. No provider admin grants in the client.
- The video-reference room layout, room chat/images, gift picker with recipients,
  quantities and animations, persistent room XP/levels1–10 and contribution ranking.
- Virtual trial coins only:1000 once,500 per24 hours, fixed server-priced gifts,
  atomic conditional debit and idempotent receipts. No real payments or cash value.
- Real owner settings, room image, announcement, category, background/theme,
  seat locks/mute/invitations, password, moderators, blacklist and operation history.
- Empty rooms keep their identity, settings and XP. Only explicit owner closure
  closes a room; ledgers are retained. Closing disconnects participants via SFU.

## Runtime setup

Flutter **3.47.7** / Dart **3.13.5**; app **1.0.0-beta.1+14**. Dependencies are locked.
`livekit_client 2.13.1` shares the existing `flutter_webrtc 1.6.2+hotfix.4` version.
API `livekit-server-sdk 2.19.1`, Node **24**, PostgreSQL **17** in CI.

Keep existing DATABASE_URL, R2, TURN, Firebase and LiveKit configuration.
Set optional server-only TOMI_OWNER_USER_ID to an existing active account UUID
to enable its owner dashboard. Never use a username/token or grant the first registrant.
The existing server-only LiveKit names remain:

```
ROOM_LIVEKIT_URL=wss://your-project.livekit.cloud
ROOM_LIVEKIT_API_KEY=<project API key>
ROOM_LIVEKIT_API_SECRET=<matching API secret>
```

The placeholders are not working credentials. These values belong on the API,
not in Flutter, GitHub or Firebase client JSON. With all three absent, room
features are disabled and existing features remain available. Partial settings
fail startup. Cloud-only validation is deliberate: this release relies on
Cloud token revocation to enforce moderation against stale join tokens.
`server/.env.example` documents names and is not loaded automatically.

Use the same database. `schema.sql` keeps the exact final0.12 schema prefix
and appends account-erasure receipts, cleanup jobs and policy acceptance tables. No reset is required.

## Build and check

```bash
cd server
npm ci --ignore-scripts --no-audit --no-fund
npm test
cd ..
bash tool/bootstrap_android.sh
python3 tool/configure_firebase.py
flutter pub get
flutter analyze
flutter test
TOMI_CALL_INTEGRATION=1 TOMI_MESSAGING_INTEGRATION=1 TOMI_IDENTITY_INTEGRATION=1 TOMI_MODERATION_INTEGRATION=1 TOMI_PRIVACY_INTEGRATION=1 flutter test --concurrency=1
```

Run GitHub Actions **TOMI 1.0.0-beta.1 Android** in `accounts` mode. The workflow also
checks PostgreSQL and builds **TOMI-1.0.0-beta.1.apk**. The API health version is1.0.0-beta.1.
Local loopback contract tests use real Node HTTP/SQLite and explicit fake media
adapters; they do not prove real RTP or LiveKit connectivity. See
[VALIDATION.md](VALIDATION.md) for the checks actually run and their limits.

## Scope and recovery

On Android, an established call or room continues while minimized or locked
when the user-started foreground service succeeds. Its ongoing notification has
an end/leave control that does not need to open the UI. Back from a room still
leaves it. Joins, seat approvals and invitations never start a microphone.
Only a visible, explicit start/answer/mic action can acquire capture. Native
Bluetooth permission is requested once during that action; refusal keeps normal
phone audio available. Speaker preference respects connected headsets.
Minimizing a video call stops video tracks while preserving audio; returning
keeps the camera off until the user enables it. Gallery selection mutes the
room microphone and never automatically unmutes it.

Incoming Android call notifications require the existing optional Firebase
client/server configuration and granted notification permission. An immutable
notification answer opens the app, waits for restored session registration,
fetches the current call, and only then accepts. Decline also checks the server.
Native code stores presentation identifiers/bindings, never account credentials.
Force-stop, revoked permissions, unavailable FCM or a disconnected network can
prevent delivery. iOS remains foreground-only in this source; CallKit/PushKit,
iOS background audio entitlements, signing and device validation need a separate
implementation. See [MOBILE_CALLS_AR.md](MOBILE_CALLS_AR.md).

Room video, recording, E2EE and push room invites remain outside this release.

The client polls room state every two seconds, heartbeats every ten, closes
participation after 25 seconds without API sync and bounds SFU reconnects. The
API removes stale attendance after45 seconds. Room metadata, gift receipts and XP
remain after everyone leaves, and remain after explicit closure for record keeping. Reconnecting SFU sessions may briefly
interrupt audio; test network changes on devices.

Desired SFU permission/removal commands persist in PostgreSQL. If enforcement
is delayed, the room shows a pending status; do not treat a moderation operation
as confirmed until the SFU acknowledges it. Closing/cleanup also retries after
API restarts. LiveKit project availability and quotas remain external dependencies.

[TOMI-PROGRESS.md](TOMI-PROGRESS.md) records the last saved development checkpoint
and the next step. Use it and the latest source to continue without resetting.

Official integration references:
- https://docs.livekit.io/intro/basics/connect/
- https://docs.livekit.io/frontends/reference/tokens-grants/
- https://docs.livekit.io/reference/other/roomservice-api/
- https://pub.dev/packages/livekit_client/versions/2.13.1


## Gift and level policy

`server/src/room_catalog.mjs` is the server source for prices, grants and XP thresholds.
Level starts1 at0 and reaches10 at25000 points. One trial coin spent on a gift adds
one room point; the recipient gets a recorded gift, not spendable credit. Ledger
inserts, wallet debit, room XP and feed events commit together under a room lock.
Changed retry bodies fail; a stable request ID returns the original receipt.
The client durably stores the original request before sending. After restart,
review and retry the saved gift explicitly; the server returns its existing receipt
without another debit. Requests from closed rooms can be checked from the room list.

Room state carries the most recent40 events; active members can page older history. Gift receipts/rankings and room state
are durable. Room admin/history responses are bounded. Photo uploads reuse the
existing verified media pipeline; replacements mark previous covers for cleanup.
Owner seat -1 and companion -2 avoid collisions with every legacy0.7 seat0..7.
Owner placement migrates lazily without changing an active SFU identity. Owner
capacity is reserved too; an already-full legacy room makes space by removing the
most recent guest on the owner's return. The 0.8 room ledger and moderation policy remain in place.

## Draft and video limits

Pending private chats allow20 requests,100 MB total and18 MB of queued voice notes.
App-private stored media also has a100 MB per-account disk cap across scopes.
Individual images remain10 MB, voice6 MB/5 minutes and video25 MB/3 minutes.
Drafts stay on their original device/account/API origin; uninstalling or clearing app
storage removes them. Web previews use memory storage. Text edits debounce250 ms;
closing a composer, backgrounding chat and sending explicitly flush the journal.
Chat auto retry runs in the foreground for the restored same session, up to5 attempts;
a fresh login requires manual retry. Posts and room gifts never publish automatically
after restart. Cancelling retry does not undo a server-accepted operation.

Video checks stream length, MD5, optional SHA256 and bounded MP4 metadata. The server
does not transcode or decode all frames. Unsupported codecs,4K,oversize and long
clips are rejected; choose compatible MP4 on the phone. Private video GET links last
5 minutes and refresh when opened. Feed videos use existing post storage policies.

- https://pub.dev/packages/video_player/versions/2.14.1
- https://developer.apple.com/documentation/quicktime-file-format/video_sample_description
