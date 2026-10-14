# TOMI 0.5 validation

Baseline: final TOMI 0.4 source. Validation date: 2026-10-14.
Node 24.19.0; Flutter 3.47.7; Dart 3.13.5.

## Passed

- All 33 backend integration/unit tests passed against real local SQLite:
  the 25 existing account/social/chat tests and eight new 0.5 cases.
- Voice persistence across service restart, concurrent nonce replay without
  duplication, private five-minute URLs, sender/thread binding, media exclusivity,
  checksum/length/type/container/duration rejection, blocking, deletion tombstones
  and cleanup in a separate private bucket.
- Avatar ownership and feature isolation, post and conversation display,
  replacement, replay that cannot revert a later photo, changed-request rejection,
  removal and delayed cleanup with a separate chat/feed configuration.
- Notification outbox persistence and replay isolation, session logout/expiry,
  read/deleted/blocked/opted-out suppression, token refresh and account transfer,
  per-device transient retry receipts, OAuth JWT signature and generic payloads,
  and FCM UNREGISTERED handling.
- All 50 Flutter tests passed: the 43 existing checks plus seven covering voice
  retry nonce/upload reuse, bounded draft bytes, compact enlarged-text voice UI,
  explicit push permission/opt-out, account-matched taps, late-token logout races
  and lost avatar-save replies with stable upload/nonce.
- Flutter analysis completed with no issues.
- Android bootstrap/source preservation, microphone/notification declarations,
  notification icon and disabled automatic FCM token initialization checks passed.
- Optional Firebase setup, matching client package, repeated plugin setup and
  rejection of a server private key/wrong package passed without real credentials.
- GitHub workflow YAML and 0.5 artifact/build-flag configuration passed.
- The entire original 0.4 schema remains an exact prefix of the new schema.
  The integration suite also retains its existing 0.3 migration test.
- Accounts build configuration accepted the current HTTPS API URL.
- Source packaging checks: ZIP integrity and byte match with working source,
  project-root layout, required workflow/docs/lockfile, and exclusion of generated
  dependencies/builds/local databases/client configs/server credentials.

## Environment-dependent checks

R2 tests use fake object stores with actual URL signing and media verification.
Audio fixture checks validate bounded container metadata; there is no server
codec decoding or guarantee about arbitrary audio bitstreams. Flutter tests use
fake transport/token providers and do not exercise a physical microphone/player.

Real R2 upload/streaming, phone recording/permissions/process recreation and
Firebase background delivery/taps need testing on the user's deployed service
and phone. No real R2/Firebase credentials or Northflank/database settings were
changed from this workspace. No deployment was performed.

GitHub Actions runs the full backend suite against PostgreSQL 17, analyzes/tests
Flutter and compiles a debug APK. That new remote workflow and APK installation
were not run here. This archive contains source, not an APK. iOS signing, native
Firebase/APNs setup and device validation are separate environment-dependent work.

Functional tests do not establish production load capacity. Immediate chat
WebSocket fanout remains local to one API instance. FCM notifications are subject
to network/OS conditions and may collapse pending alerts; server acceptance is
not proof of display on a phone. Previously queued OS alerts cannot be recalled.
End-to-end encryption, calls/rooms and release/store signing are outside 0.5.

## Continuation

Code and TOMI-PROGRESS.md were saved at multiple checkpoints while implementing
0.5. Resume from the latest saved source and status record. Temporary SDK/cache
files are reproducible and are not included. Any work after the last successful
checkpoint can still be lost to an abrupt session interruption.
