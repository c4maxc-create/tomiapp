# TOMI 0.6 validation

Baseline: final TOMI 0.5 source. Date: 2026-10-14.
Node 24.19.0; Flutter 3.47.7; Dart 3.13.5.

## Verified locally

- 42 backend tests passed on real local SQLite: the 33 existing tests and nine
  call cases for isolation, concurrent start replay, busy slots, first-device
  accept, session-bound ICE/signaling, ordered offer/answer/candidates, retry
  hashes, cleanup, history, restart, timeouts, blocking, logout, media/payload
  bounds, disabled config, coturn HMAC, Cloudflare response validation and
  durable/suppressed incoming-call outbox dispatch with a fake sender.
- All 62 Flutter tests passed with TOMI_CALL_INTEGRATION=1: 50 existing tests,
  11 call controller/UI tests and one local Node HTTP contract test. Coverage
  includes late offers, buffered ICE, stable retries, permission denial, late
  responses after background, other-device accept, logout, controls, enlarged
  Arabic video UI at 320px and waiting for voice-note audio release.
- The contract test runs a real Node API and two actual CallControllers through
  offer/answer/ICE, connection status, hangup and history. Its media engine is
  fake; this is not a native RTP/microphone/camera test.
- The 0.6 schema preserves the exact 0.5 schema prefix. Existing migration,
  accounts, social, chat and media regression tests pass.

Flutter analysis completed with no issues. Android/bootstrap, optional Firebase,
HTTPS build configuration, workflow YAML and 0.6 artifact/version checks passed.
Final status is also recorded in TOMI-PROGRESS.md. GitHub Actions runs both database modes, Flutter analysis/tests,
the HTTP call contract and the Android APK build.

## Not exercised here

The hosted service, GitHub repository, PostgreSQL, R2, Firebase and Cloudflare
accounts were not changed. PostgreSQL 17 integration is configured in GitHub
Actions; local backend tests above used SQLite. A native PostgreSQL server was
not available. No Android SDK/emulator or iOS signing environment was present;
an APK or iOS binary was not compiled here.

Actual phones, microphones/cameras, speaker routing, permissions, TURN relay
across Wi-Fi/mobile data, real FCM delivery/taps, background/force-stop and
network changes need START_HERE_AR.md device checks. Fake transport tests do
not prove these properties.

## Scope

Foreground one-to-one calling. Leaving the foreground ends call media. Incoming
FCM is a normal alert opening the app for explicit acceptance, not CallKit,
ConnectionService or full-screen OS ringing. TURN setup enables calls; FCM is
additionally needed for out-of-app alerts. HTTP signaling has WebSocket
invalidation and polling fallback. Node stores state/history, not media.

Descriptions/candidates are removed on end and not logged. Permanent TURN/FCM
keys remain on the API. App-level verified E2EE identity, background calling,
screen sharing, groups, SFU/voice rooms and release/store signing are outside
this version. Limits: ringing 35 seconds, setup 45 seconds, stale heartbeat 40
seconds, media-disconnect grace 12 seconds, connected duration two hours,
history retention 90 days. An already queued OS alert cannot be recalled;
opening it checks current account/state and never auto-accepts.

Deployment and device acceptance are the next step. The previous saved 0.5
source remains a rollback point. The work checkpoint contains the current
source and progress, with no SDK, dependency caches or private configuration.
