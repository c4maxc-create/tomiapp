> Android C# game interface: see [CSHARP-GAMES-ANDROID-AR.md](CSHARP-GAMES-ANDROID-AR.md). Build bundled WebAssembly with `python3 tool/build_csharp_games.py` before Flutter tests/builds. The Android workflow includes this step.

> إضافة جاكارو والجمل المجنون: لعبتان فعليتان بقسم TOMI PLAY،برقم بناء26. القواعد والتحديث في [GAMES-JACKAROO-CAMEL-AR.md](GAMES-JACKAROO-CAMEL-AR.md). يلزم تحديث الخادم قبل بناء التطبيق الجديد؛ النتائج الحالية في VALIDATION-BOARD-GAMES.md.

# TOMI1.7.0-beta.1

التطبيق1.7.0-beta.1+25 والخادم1.7.0-beta.1. مساحة ألعاب فعلية:أونو والسلم والأفعى ضد الكمبيوتر أو الأصدقاء،والروليت من قسم الألعاب على نفس جولات الغرف. مستوى لعب مستقل عن كارزما الهدايا،وبطاقتا تقدم بالحساب،وأسطح موحدة وشريط لحظاتTOMIجديد دون سهم بجانب العلامة.

ابدأ بـ **UPDATE_1.7_AR.md** للرفع والاستخدام والقواعد. ارفع محتوياتTOMI-1.7.zipكاملة،وانشر الخادم الحالي أولًا وتحقق منhealth1.7.0-beta.1،ثمRunworkflowجديد لبناءAPKمنGitHub. القاعدة والمفاتيح والمالك الحاليون محفوظون،ولا تُحذف بيانات الإنتاج. الفحوص وحدودها فيVALIDATION-1.7.md،والاستكمال فيTOMI-PROGRESS.mdوTOMI-MD.

الأقسام الأقدم أدناه سجل تاريخي وليست نسخة التسليم الحالية.

---

# TOMI1.6.1-beta.1

التطبيق1.6.1-beta.1+24 والخادم1.6.1-beta.1. تحديث ثبات عجلة الروليت،أفضل3خاصين بالجولة لخمس ثوانٍ،أشرطة أوضح،توحيد أسلوب الواجهات،إزالة بانر الحساب،وتحسين المشاركة وقراءات الخادم. صُحح أيضًا codemagic.yaml الذي أوقف تشغيل48. المصدر الكامل TOMI-1.6.1.zip؛الدليل UPDATE_1.6.1_AR.md والتقرير VALIDATION-1.6.1.md والاستكمال TOMI-PROGRESS.md وTOMI-MD. يلزم Commitجديد ونشر الخادم وتشغيل GitHubجديد للتحقق منFlutter وبناءAPK. السجل السابق أدناه تاريخي.

---

# TOMI 1.6.0-beta.1

النسخة الحالية تضيف روليت مشتركة داخل الغرف، مشاركة منشورات داخلية مع طلبات للغرباء، وشارات كارزما دائمة، وتحذف بانر «على موجتك» من الرئيسية. الحزمة الكاملة TOMI-1.6.zip؛ دليل الاستخدام والرفع UPDATE_1.6_AR.md، والفحوص وحدودها VALIDATION-1.6.md، ونقطة الاستكمال TOMI-PROGRESS.md. بناء APK والتحقق من Flutter يتمان عبر GitHub Actions على Commit جديد. الأقسام التالية سجل المراحل السابقة.

---

# TOMI 1.5.0-beta.1

النسخة الحالية: هوية TOMI، تحسينات المحادثات، مستويات الغرف المتقدمة ومدار الحظ بصلاحيات المالك. دليل التحديث والاستخدام: **UPDATE_1.5_AR.md**. التحقق: **VALIDATION-1.5.md**. نقطة الاستكمال: **TOMI-PROGRESS.md**. الأقسام التالية سجل المراحل السابقة.

---

# TOMI 1.4 — APK downloads in Releases

Current source: **TOMI-1.4-releases-fix.zip**. The hosted APK built successfully but Artifact creation was denied by the account's storage quota. The workflow now uploads verified build files to a unique repository prerelease, pinned to the build commit, checks its draft/upload receipt, publishes it and puts a download link in the job summary. Existing repository read permissions govern access. Android alone requests contents:write with the built-in token.

Replace only **.github/workflows/tomi-android.yml**, commit on main and start a fresh accounts/debug run. Then download **TOMI-1.4.0-beta.1.apk** under **Releases → Assets**. **RELEASES_DOWNLOAD_FIX_AR.md** gives the steps. **VALIDATION-1.4-RELEASES-FIX.md** records 26 delivery scenarios, eight disk checks, YAML/Bash checks and preservation limits. Production/client/schema/tests/locks match source27; all API, restore, Flutter and signing gates remain. App/API versions stay 1.4.0-beta.1/+21.

The complete source preserves all 419 previous paths and all owner/admin features. No live publication was performed here. **TOMI-PROGRESS.md** records continuation. Earlier release instructions below are history.

---

# TOMI 1.4 — run 40 search-test timeout

Current full source: **TOMI-1.4-ci40-fix.zip**. Run 40 passed 172 of 173 tests; the search integration case exceeded its 60-second bound on GitHub. The two dense messaging scenarios now have explicit three-minute budgets, retain all 65/95 API sends and assertions, and add bounded pagination checks. The global 60-second test limit, PostgreSQL step (15 minutes), API job (40 minutes) and 173-test completeness gate remain unchanged.

For the already-uploaded source, replace only **server/test/messaging10.test.mjs**, commit on main and start a fresh accounts/debug workflow. **CI_FIX_RUN40_AR.md** has the upload steps. **VALIDATION-1.4-RUN40.md** records 13/13 SQLite and 13/13 native PostgreSQL checks with fsync enabled. No app/API runtime, client, schema, workflow or owner feature changed in this patch; versions remain 1.4.0-beta.1/+21. The complete ZIP preserves all 412 original paths. **TOMI-PROGRESS.md** contains the continuation record.

Earlier release documentation follows as history.

---

# TOMI1.4 — CI timeout, complete test reports and story retry repair

The full **TOMI-1.4-ci-fix.zip** source retains the1.4owner/admin features. PostgreSQL's Actions step now has15minutes and its API job40minutes. The Node test command preserves process isolation, serial execution and60-second per-test bounds, flushes report pipes and requires all173passes with no missing summary, failures, cancellations or skips before CI can continue.

Full checks exposed a separate story-publication race. A retry that first missed its receipt could see already-attached media after its twin committed and incorrectly return400. Receipt rechecks now return the accepted story, including a recheck inside the existing user-lock transaction. The same check now reconciles private media message retries. The existing MP4 and voice tests force both receipt/upload orderings rather than relying on chance.

Start with **CI_FIX_1.4_AR.md** and **VALIDATION-1.4-CI-FIX.md**. Upload the complete source and create a newmaincommit, update the existing API from it, and start a freshaccounts/debug workflow. App/API versions remain1.4.0-beta.1/+21. The schema, lockfiles, client and owner controls retain source25bytes; onlyhome.mjsandchat.mjschange in runtime API code. **OWNER_ADMIN_1.4_AR.md** documents activation of the owner account. Previous sections below are historical.

When adding/removing Node tests, maintain `server/tools/test-suite.json` so incomplete runs cannot silently report success. Targeted diagnostics can still use `node --test` directly.

---

# TOMI 1.4 — owner controls and scoped moderation

App **1.4.0-beta.1+21**, API **1.4.0-beta.1**. The platform owner can adjust app coins and received charisma, create and mark special accounts, suspend members and delegate seven independent moderator scopes. Audited mutations use stable request receipts, balance bounds and revision checks. Staff cannot modify balances, create accounts or grant staff access.

Start with **OWNER_ADMIN_1.4_AR.md**. Bind the existing owner account UUID through `TOMI_OWNER_USER_ID`; the app settings already include a copy-account-ID action. No default owner credentials or first-registration privilege is created. Publish the matching server and client source from this full package. **VALIDATION-1.4.md** records executed checks and deployment limits. Earlier1.3.2 notification/room setup still needs the user's Firebase/FCM/LiveKit values; the accounts APK keeps its required Firebase client guard.

All source24 paths and existing lock dependency versions are retained. The two new tables are additive, the gift ledger remains unchanged by manual charisma adjustments, and privacy erasure removes delegated permissions and special status. Previous releases below are historical reference.

---

# TOMI 1.3.2-beta.1 — notification and room-creation fixes

Complete Flutter source **1.3.2-beta.1+20**, API **1.3.2-beta.1**, extending canonical source23. The plus button opens the room form immediately while directory/balance reads run; wallet updates preserve input. Unavailable-service messages have readable contrast, and a definitive uncharged ROOMS_DISABLED response releases its saved creation intent. Existing paid-room consent, debit and lost-response safeguards remain.

Notification initialization can retry after failure and relies on actual native configuration. The settings page distinguishes client/server readiness, permits retry, and marks registration successful only after the API accepts the device. Accounts APK builds require a valid Firebase Android client via TOMI_GOOGLE_SERVICES_JSON or config/google-services.json. Server private credentials remain server-only. Complete standard LIVEKIT_* variables and FIREBASE_SERVICE_ACCOUNT_JSON are accepted as compatible alternatives to the existing names. Health exposes setup booleans without credentials.

Start with **FIX_NOTIFICATIONS_ROOMS_1.3.2_AR.md**. Phone notification configuration was absent from the supplied files; configure the user's Firebase project before building. This source package does not itself activate external services or contain an APK. All source23 paths, features and PostgreSQL1.3.1 fixes remain. Current checks are in **VALIDATION-1.3.2.md**; earlier documentation follows as history.

---

# TOMI 1.3.1-beta.1 — PostgreSQL CI and migration fix

Complete source, app **1.3.1-beta.1+19**, API **1.3.1-beta.1**. Preserves all 1.3 voice-room features. Corrects the support-event foreign key on new and existing PostgreSQL/SQLite databases without removing gift records, retry receipts, balances or cosmetics. Retired room-owner uniqueness is not recreated during startup. Failed schema initialization closes its database handle.

The serial Node test runner now limits individual tests and exits after completed tests while preserving failure status. CI has separate database and restore deadlines. Start with **PG_FIX_1.3.1_AR.md** and **VALIDATION-1.3.1.md**. Upload the complete source before starting a new GitHub Actions run; rerunning run35 reuses the old commit. The existing API URL remains https://tomiapp.onrender.com. This package is source; hosted APK creation and phone acceptance follow the upload.

Previous documentation follows.

---

# TOMI 1.3.0-beta.1 — voice rooms

Arabic Flutter app and Node24 API. Voice rooms now have free/advanced policies, atomic5799-coin purchases, a60-day owner inactivity limit, advanced-only public IDs, self/group support, top100 daily/Friday-weekly/lifetime rankings, temporary cosmetics, per-visit chat cursors and realtime updates.

Start with START_HERE_AR.md and VOICE_ROOMS_1.3_AR.md. Current validation is recorded in VALIDATION-1.3.md. The ZIP contains complete source; Android scaffolding is generated by tool/bootstrap_android.sh in CI. The default API for this user's build is https://tomiapp.onrender.com.

Previous documentation follows.

---

# TOMI 1.2 — PostgreSQL CI assertion fix

Current package: **TOMI-1.2-postgres-fix.zip**. Run32 stopped because one test
compared pg's COUNT string with a number. The existing assertion now normalizes
the count while retaining the exact one-group requirement. All production code,
workflow, schema, locks and app/API versions are identical to source20.

Start with **PG_FIX_1.2_AR.md** and **VALIDATION-1.2-PG-FIX.md**. Upload the corrected
`server/test/chat12.test.mjs`, commit on main and start a new workflow run.
The sections below describe the included 1.2 app features and previous checks.

---

# TOMI 1.2 — chats and groups

App **1.2.0-beta.1+17** / API **1.2.0-beta.1**. This update adds the supplied
WhatsApp-inspired chat layout, functional inbox menus and filters, a unified
media/document picker, emoji and built-in TOMI stickers, cached history shown
before the background refresh, and private groups with per-member notifications.

Start with **START_HERE_AR.md** and **CHAT_1.2_AR.md**. Upload the complete source,
update the existing API to 1.2, then start a new GitHub Actions run from that
commit. **VALIDATION-1.2.md** records successful local analysis, 191 distinct Dart
cases and 145 Node/SQLite tests. PostgreSQL/restore verification, APK creation
and physical-phone acceptance remain the next deployment checks. The workflow
keeps the existing CI safeguards and enables all eight HTTP contracts.

The existing 132 Flutter lock entries retain their versions and checksums; 12
packages were added for file selection and opening. The schema upgrade is
additive. All source19 paths are retained, including the prior home/profile,
stories, subscriptions placeholders, calls, voice rooms, identity and games.
**HOME_PROFILE_1.1_AR.md** documents those existing home/profile features.

The following sections document earlier features and remain reference material.


---

# TOMI 1.0 beta1 — privacy, account erasure and Android release preparation

Arabic Flutter social app with Node24/PostgreSQL API. Source version
**1.0.0-beta.1+14**, API **1.0.0-beta.1**, extending the exact final0.12 ZIP.
User authorized this phase on2026-10-17; delivery completed on2026-10-22 (Baghdad).
Latest timeout correction: accounts-api job budget raised10->30min after a
user screenshot showed cancellation at10m18s while PostgreSQL cases were passing.
Only this numeric workflow setting changed. Official parser returns zero errors;
all test/restore steps remain, hosted completion/APK remain pending.

Previous workflow correction: run27 rejected runner.environment at job-level env.
The value now lives only in the two cleanup step env maps. The official GitHub
workflow parser reproduces the prior line85 error and accepts the corrected
workflow with zero errors; see CI_BUILD_FIX_AR.md. Existing disk safeguards remain.

CI disk fix (2026-10-22): TOMI-1.0-beta1-ci-timeout-fix.zip adds hosted-runner cleanup,
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
