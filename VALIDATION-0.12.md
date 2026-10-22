# TOMI 0.12.0 validation

Completed source review: 2026-10-17, Asia/Baghdad. App0.12.0+13, API0.12.0,
Node24.19.0; local SDK Flutter3.47.7 / Dart3.13.5. User authorized0.12 with
«الان ابدا بالمرحلة التطوير القادمة» and requested continuation.
Exact final0.11 baseline SHA256:
6f6a11bb3acf1d259a4c63cc607002d836de5f8653e2225d497aa29c4037e763.
Earlier results are archived in VALIDATION-0.11.md through VALIDATION-0.8.md.

## Checks actually run

- **116 Node tests passed, 0 skipped, 0 failures**, against actual local SQLite:
  93 existing tests plus15 moderation and8 operations cases. A final focused
  rerun of all15 moderation cases also passed after strengthening the additive
  upgrade assertion. Expected injected5xx errors in metrics tests are deliberate.
- The real loopback moderation client fixture was separately smoke-tested with
  owner/moderator/member roles, ordinary-member403 and API health0.12.0.
- **New lib/src/moderation Dart analysis: no issues** using the local Dart SDK
  and available dependencies. Whole-lib offline analysis reports97 diagnostics
  caused by missing dependencies; normalized diagnostics match the exact0.11
  baseline under the same partial package cache, with no added diagnostics.
  This is not a successful full `flutter analyze` run. Targeted test-file analysis
  is also blocked by missing test API/matcher bindings; it is not a passing test run.
- Changed Dart files and the2 new Flutter test files are formatted.
- **11 JVM notification-policy cases passed** on JDK17. The7 native production
  Java files and policy test match final0.11 byte for byte. Bootstrap preservation,
  optional Firebase, public HTTPS/accounts and preview configuration checks passed.
- The0.12 schema preserves the exact0.11 prefix. A real0.11 SQLite database upgrades
  without losing credential hashes, identity selection or user gift progress.
- Backup tests actually restored a real encrypted SQLite database and compared
  credentials, gift request identity, identity selection, private report notes
  and audit records. This verifies encryption/record restoration locally; it is
  not a PostgreSQL pg_restore result.
- The bounded isolated local load sample completed60/60 reads with4 workers and
  no errors; p95=24.73ms in this environment. OPERATIONS_LOAD_SAMPLE.json records
  the sample. Its12 SQLite rooms and fake provider do not measure RTP, hosted
  database performance, production capacity or provider bills.
- Final delivery checks verify required source/tests/guides, CRC, every manifest
  digest, workspace-byte equality, unchanged native files and schema prefix;
  exclude credentials, backup files, SDKs, generated platforms and caches.
  SOURCE-FILES.sha256 excludes itself.

## Evidence exercised

| Area | Local cases |
| --- | --- |
| Reports | Reporter-only lists/details; separate public response/private notes; minimal evidence survives deletion; no self-report; strict reasons/lengths; duplicate active report and concurrent nonce replay; rate limits and changed-payload rejection. |
| Permissions | Explicit existing owner UUID; startup rejects absent/suspended owner; room moderator is not platform staff; ordinary users cannot grant themselves roles; protected owner/staff targets; live role revocation and owner-only suspension/grants. |
| Decisions | Expected-revision conflicts; linked-report target checks; safe report reopen; old receipt cannot undo later decision; replay after target deletion; denied input leaves audit/ledgers unchanged. |
| Posts | Hidden or suspended-author posts disappear from feeds, reads, likes and comments; retained rows allow restore; existing author deletion still works. |
| Suspension | Session/auth-version/push invalidation, call termination, owned-room closure, removal elsewhere, durable provider retries, recovery transaction rollback, restore permits only a new login. A request authenticated before ban cannot create a call after ban commits. |
| Lists/metrics | Report/audit keyset pagination with25 tied timestamps; staff authorization; aggregates, status/latency and injected5xx; URLs, queries, request bodies and credentials absent from metrics. |
| Backup tools | AES256GCM round trip/0600, tampering of header/IV/ciphertext/tag, wrong key, truncation, authenticated empty file, no-clobber output, passfile escaping/cleanup, child failure prevents publishing a partial dump, local empty-target guards. PostgreSQL child tests use explicit fake clients locally. |
| Local load | Loopback/read-only/redirect/request/concurrency/body/time bounds; actual isolated HTTP sample; no production requests. |

## Prepared checks that could not run here

The global Flutter package cache was lost between continuations. Only a partial
pinned cache remains; downloads of missing dependencies were denied. Full Flutter
analysis, widget tests and APK build could not run in this environment. No existing
source or dependency lock was reset to work around the missing cache.

- 8 new Flutter/controller/widget cases cover frozen retries, role revocation with
 a late privileged response, logout guards, reverse-order filters, report dialog
 retry, private own-report rendering and compact Arabic admin/settings layouts.
- 1 new real-HTTP Flutter contract covers report, staff review/public response,
 hide/restore, role revocation and banned-session rejection.
- The existing137 Flutter cases are historical0.11 results, not0.12 results.
 There are146 intended cases including the9 additions. None of the146 was claimed
 as passed for0.12. CI runs the normal suite and explicitly enables all5 HTTP
 contracts (calls, rooms, messaging, identity, moderation).
- Real PostgreSQL17 tests and an encrypted pg_dump/pg_restore drill are configured
 in Actions, using its ephemeral container and a newly created localhost database
 named tomi_restore_check. No PostgreSQL server/client is installed here, so the
 actual drill has not run. CI must pass before distributing the APK.

## Operational and device limits

This is source, not an APK or hosted deployment. No GitHub, Northflank, PostgreSQL,
R2, TURN, LiveKit or Firebase account was changed. No production data/backup/key
was obtained. No actual phones/emulator, RTP/SFU, background FCM, Bluetooth,
network handoff, native gallery/decoder or battery performance was exercised.
Previous device acceptance results have not been reported.

HTTP metrics are per process/last60 minutes; DB counts are cached10 seconds.
Media-size records are estimates, not actual object inventory or billing.
Suspension schedules durable SFU removal; revoking an API session alone does not
prove instant RTP disconnection. Previously downloaded content and old media URLs
are not globally erased by hiding a post. Pending actions are retried only with
their original nonce/body; after app restart review target state and audit first.

Database backups do not copy R2 objects or service secrets. Automatic scheduling,
retention, offsite storage and a live object/secret recovery drill remain operator
setup. A checksum alone is not an application recovery test. The local HTTP sample
cannot establish a safe production user count.

## Reproduce and rollout

```bash
cd server
npm ci --ignore-scripts --no-audit --no-fund
npm test
cd ..
bash tool/bootstrap_android.sh
python3 tool/configure_firebase.py
flutter pub get
flutter analyze
TOMI_CALL_INTEGRATION=1 TOMI_MESSAGING_INTEGRATION=1 TOMI_IDENTITY_INTEGRATION=1 TOMI_MODERATION_INTEGRATION=1 flutter test --concurrency=1 --reporter expanded
python3 tool/check_mobile_policy.py
python3 tool/check_bootstrap.py
python3 tool/check_firebase.py
```

Actions reruns Node tests with guarded localhost/tomi_test PostgreSQL17 and then
server/test/pg-restore-drill.mjs. Never use production as a test target.
Upload source to the same repository; deploy API0.12.0 before clients and retain
DATABASE_URL and existing service keys. Set optional TOMI_OWNER_USER_ID to an
existing account UUID after copying it from the profile. Do not run mixed API
versions while upgrading. Workflow/artifact: TOMI0.12.0 Android / TOMI-0.12.0.apk.
Follow START_HERE_AR.md, MODERATION_0.12_AR.md and OPERATIONS_0.12_AR.md; test
moderation plus prior call/message/room acceptance on phones before wider release.
