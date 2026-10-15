# TOMI 0.9.0 validation

Date: 2026-10-16, Baghdad. Source 0.9.0+10; Node24.19.0, Flutter3.47.7,
Dart3.13.5. The user authorized this phase after the roadmap. The verified
0.8 source was restored from its saved final version, not reconstructed from
conversation snippets. Baseline SHA256:
d0b3b536ae3d3355e0fe2a4525398282fda9f4a0dec951a9548f33d19aad64b7.
0.7 phone acceptance was reported; 0.8 phone acceptance has not been reported.
Historical 0.8 checks remain in VALIDATION-0.8.md.

## Checks completed

- Node: 73 tests passed against real SQLite. Four new 0.9 cases cover device
  bindings, multiple-device cancellation across API restart, cancelled unsent
  calls, logout detachment, additive schema prefix and FCM HTTP-v1 payloads.
  The26 call/media/push cases were rerun after the final payload adjustment.
- Flutter: 101 tests passed with TOMI_CALL_INTEGRATION=1 and no skips, including
  all89 baseline cases and12 new cases: screen-off signaling, camera shutdown
  and no silent resume, unavailable service fallback, late start after logout,
  listener-only rooms, background moderation, late mic permission, notification
  account/session validation, expired rings, explicit answer, late video
  permission rollback and matching native-service loss cleanup.
- Static analysis: no issues. Loopback HTTP contract tests exercise two client
  controllers against the real Node API for calls and rooms. Media and SFU
  adapters in these contract tests remain explicit fakes.
- Native JVM policy: 11 scenarios passed for expiry bounds, cancellation before
  incoming delivery, account/session changes, disabled notifications, missing
  binding and forged action nonce.
- All7 production Java files compiled with JDK17 javac against real Android36,
  Flutter embedding at engine deb287481e, Firebase Messaging25.1.3 from the
  locked BoM34.19.0, AndroidX and actual FlutterFire16.7.0 superclass/token
  LiveData source. No compile errors; isolated compilation emitted Kotlin
  annotation metadata and deprecated API warnings. Only generated R.drawable
  was replaced by a numeric test R. Manifest/vector generation was checked
  separately. This is not a Gradle/dex/manifest-merge or APK build.
- Bootstrap source preservation, native source copying, removal of duplicate
  generated Kotlin MainActivity, service types/permissions, private receivers,
  FCM service priority, optional Firebase setup/package validation/server-key
  rejection, HTTPS build configuration and workflow outputs were checked.

## Resulting behavior

User-started Android calls and rooms retain the existing Flutter engine with a
microphone/media-playback foreground service and ongoing end/leave controls.
The service acknowledges successful startForeground; failure keeps the
foreground-only fallback. A renewable bounded CPU wake lock supports screen-off
heartbeats. Native controls and service loss release only the matching media
lease. Logout and late permission callbacks cannot revive old capture. Joins,
seat grants and invitations stay muted. Background administrative mic revocation
still applies. Listener-only service startup does not request microphone access.

Protocol2 incoming call pushes are data-only, session-bound and expire at the
server ring deadline. Native CallStyle displays audio/video type and answer/
decline. Answer opens a visible activity, restores/registers the session and
fetches the live call before accepting. Immutable intents use a private local
nonce. Answer/decline locally stop ringing immediately. Durable server
cancellation removes other receiving devices' ring cards; tombstones suppress
reordered incoming packets. Legacy clients retain their original notification
payload until they advertise protocol2. No full-screen-intent, default-dialer
role or fake self-managed-call permission exemption is requested. Existing
optional Firebase client/server credentials are reused.

Minimizing video stops capture tracks and preserves audio. Returning keeps the
camera off until a user tap. Late video permission rolls back to audio. Android
continuous ICE gathering, stable-nonce candidate backoff and20-second media
disconnect grace improve transient handoffs. Room API/SFU grace remains25s and
stale attendance cleanup45s. These do not prove every network handoff succeeds.
The exact verified0.8 schema prefix is retained; new tables are additive.

## Remaining device acceptance

No complete APK, emulator, real phone RTP/SFU, live FCM delivery or wired/
Bluetooth route was exercised. No remote GitHub, Northflank, database, LiveKit,
TURN or Firebase account was changed. Use the two-phone matrix in
MOBILE_CALLS_AR.md. GitHub Actions retains PostgreSQL17 verification and the
full APK build; those jobs must run in the user's repository.

Incoming background cards require configured FCM and granted notification
permission. OS force-stop, battery/network restrictions and revoked permissions
can prevent delivery or continued audio. Android6/7 uses a private alarm expiry
fallback; Android8+ uses system notification timeout. iOS remains foreground-only;
CallKit/PushKit, entitlements, signing and iOS device acceptance are separate work.
No room camera, recording, E2EE, paid wallet or push room invites are claimed.

The source ZIP excludes SDKs, caches, generated platforms, local credentials
and temporary verification scaffolds. The standalone TOMI-PROGRESS.md is the
authoritative saved continuation point.

## Primary references

- [Foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types)
- [Background start restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)
- [Android CallStyle](https://developer.android.com/develop/ui/compose/notifications/call-style)
- [FCM Android delivery](https://firebase.google.com/docs/cloud-messaging/android/receive-messages)
- [FCM Flutter prerequisites](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages)
- [FCM HTTP-v1 authorization](https://firebase.google.com/docs/cloud-messaging/send/v1-api)
