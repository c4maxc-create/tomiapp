# TOMI 0.10.0 validation

2026-10-16, Baghdad. App0.10.0+11; Node24.19.0; Flutter3.47.7 / Dart3.13.5.
The user authorized continuation with «اكمل مراحل التطوير». The exact final0.9
source was restored from its saved version; baseline ZIP SHA256:
20f216dbc926d1fecd16653900ce7c3f63747ed20a640dfd53e2a69eb77c6aa3.
Historical checks remain in VALIDATION-0.9.md and VALIDATION-0.8.md.

## Checks run

- **119 Flutter tests passed, no skips**, with TOMI_CALL_INTEGRATION=1 and
  TOMI_MESSAGING_INTEGRATION=1, concurrency1. This includes101 baseline tests,
  17 new draft/video/compact-screen cases and one new real HTTP contract case.
- **81 Node tests passed** against actual local SQLite, including8 new0.10
  cases. These8 were rerun after final fixture/CI setup changes and passed.
  New fixtures honor the guarded TEST_DATABASE_URL for CI PostgreSQL runs;
  PostgreSQL was not available or executed locally in this turn.
- **Flutter analysis: no issues**. Source formatting, locked dependencies,
  bootstrap/source preservation, Android native-source copying, branding,
  optional Firebase setup and public HTTPS/preview build configuration passed.
- **11 JVM notification policy scenarios passed** using JDK17. The7 native
  Android production Java files are unchanged from the compiled/verified0.9
  baseline. No new Android native API was added in0.10.
- Source packaging checks CRC, required files, byte equality with workspace,
  absence of private configuration/generated build trees and the exact0.9
  schema prefix. The source file manifest excludes its own digest.

The initially restored Flutter test executable was truncated. Official engine
artifacts at deb287481e3ce9468f3434937ced4240a70539ca were downloaded, ZIP CRC
verified and restored before the successful test runs. This was a test-runtime
repair, not a change to the application.

## Evidence covered

| Area | Cases exercised |
| --- | --- |
| Local journal | Fresh FileDraftStore instance reads real files after controller restart; immutable media survives across scopes; another account cannot read it; missing/tampered media cannot replace a committed draft; revoked guards cannot commit; corrupt journals keep their blobs. |
| Private sends | Network starts only after persistence; lost accepted image ACK is reconciled with the original nonce without another PUT or message POST; same-session/new-login behavior; selected media, text and reply restore; total/voice queue limits. |
| Chat tools | Reply target must belong to the conversation and remain live; six reactions aggregate per user; pins persist and old unpin cannot clear a newer pin; stale revisions and deleted quoted text cannot regress; block/participant boundaries. |
| Search | Literal percent/underscore matching, bounded query/sequence cursor, stable older pages, deletion exclusion and member-only access. |
| Uploads/video | Parallel initialization returns the same upload; changed scope/body fails; expired physical upload can renew while logical send stays unique; SHA256 is verified against bytes; real generated H.264/AAC MP4 passes with chunk sizes1/7/13/1024; unsupported codec, truncation, size/dimension violations fail. |
| Storage scopes | Chat video has short private GET URLs and correct user/thread ownership; feed video uses post storage; deletion cleanup removes only matching bucket objects. R2 transport is substituted with deterministic in-memory objects; real signing remains covered. |
| Posts | Editable draft restoration; close/reopen UI; uncertain publish freezes its body/nonce; restart receipt lookup prevents a second publish; deleted-post tombstones prevent old nonce resurrection. |
| Rooms | Keyset history across95 events; active member/session authorization; own receipt can be checked after closure; stored gift needs an explicit retry; room-list verification never joins or spends; wallet/debit baseline atomicity retained. |
| Playback/UI | No autoplay; pause on background/call; interrupted pending play cannot resume later; selected video/reply controls fit320×400 with keyboard and enlarged text. Video platform is explicitly substituted; native playback still needs device acceptance. |
| Flutter/API contract | Real loopback Node HTTP/SQLite with disk journal and a deliberately dropped committed ACK; reconstructed Flutter controller checks receipt, then exercises replies, reactions, pin, search, post publish and deleted quote. Existing call/room contracts also passed with their explicit fake media adapters. |
| Upgrade | Current schema starts with the exact verified0.9 bytes. A real0.9 SQLite database opens without reset and retains a seeded old post, with a new idempotency receipt. Earlier account/session/room migrations remain in the baseline suite. |

The tiny video fixture is generated test content (blue320×180 frame and a440Hz
synthetic tone, one second); it contains no user recording.

## Delivery and device limits

This delivery is complete source, not an APK or a hosted update. No remote GitHub,
Northflank, PostgreSQL, R2, LiveKit, TURN or Firebase account was changed. GitHub
Actions retains real PostgreSQL17 and APK build steps; they have not been run
from this session. No emulator/phone, actual gallery picker, native video decoder,
RTP/SFU, background FCM delivery, or wired/Bluetooth route was exercised here.
Use MESSAGING_0.10_AR.md and MOBILE_CALLS_AR.md on two phones after deploying API0.10.0
and building the app in the existing repository. The user has not reported device
acceptance of0.8/0.9; retain those checks alongside0.10 acceptance.

Journals are local to the account/API/device and contain no Bearer token. They are
not a cloud backup, cross-device draft sync or E2EE claim. Uninstall/clear-data
removes local drafts. Web preview storage is memory-only. Text edit batching is
250ms; send/close/background flush explicitly. Process kill before a successful
local commit can lose those most recent uncommitted edits. Gifts/posts do not
publish automatically on restart; checking a saved receipt never sends a gift.
Cancelling retry does not undo an already accepted operation.

MP4 validation checks bounded container/codec metadata, duration, dimensions,
length and checksums; it is not full frame decoding or transcoding. Supported
video is H.264 with optional AAC, up to25 MB /3 minutes /1080p. Real device codec,
rotation, gallery and playback behavior still needs the acceptance matrix.

## Reproduce

```bash
cd server
npm ci --ignore-scripts --no-audit --no-fund
npm test
cd ..
flutter pub get
flutter analyze
TOMI_CALL_INTEGRATION=1 TOMI_MESSAGING_INTEGRATION=1 flutter test --concurrency=1 --reporter expanded
python3 tool/check_mobile_policy.py
python3 tool/check_bootstrap.py
python3 tool/check_firebase.py
```

PostgreSQL CI runs npm test with a localhost tomi_test TEST_DATABASE_URL. Never
point tests at production. Existing keys and the database are reused for rollout;
API schema additions run at startup. Deploy API before clients and avoid mixed
API versions during the migration. Workflow/artifact: TOMI0.10.0 Android /
TOMI-0.10.0.apk. Phone steps are in START_HERE_AR.md.
