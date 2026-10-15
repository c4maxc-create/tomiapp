# TOMI 0.7.0 validation

Date: 2026-10-15 (Baghdad). Baseline: accepted final 0.6.1 source
SHA256 07c4fe90789522041d7f6a7baa8f92a59e0085998db1628fa1f690b10a347e04.
The user confirmed that release worked on their devices and authorized 0.7.
Runtime: Node 24.19.0, Flutter 3.47.7, Dart 3.13.5.

## Checks actually run locally

- **58 backend tests passed** with real local SQLite: all 47 previous cases
  and 11 room cases. New coverage includes authenticated access, stable room
  creation/join retries, capacity races, session ownership, one room/call at
  a time, requests, approval, mic-only publishing, moderator/owner boundaries,
  kicks, stale connection leaves, revoked sessions, heartbeat expiry, ten-minute
  empty closure, durable SFU retries across restart and full token removal on
  room close. DeleteRoom does not discard pending participant revocations.
- **80 Flutter tests passed**, with `TOMI_CALL_INTEGRATION=1`: the previous 70
  tests plus nine room controller/widget cases and one room HTTP contract.
  Joins and seat approvals never capture audio; user actions enable the mic.
  Late permission results after demotion/background, stale snapshots, removal
  during join, kick cleanup, lazy tab loading and narrow Arabic UI are covered.
- The new contract runs two actual VoiceRoomsControllers against a real local
  Node HTTP/SQLite API. It creates/joins a room, requests/approves a mic, mutes,
  assigns a moderator, kicks and closes. **Both the SFU provider and client
  media engines are explicit fakes**. No real RTP was exchanged by this test.
- The real LiveKit server SDK signs join JWTs and the real verifier checks them
  in tests. Listeners cannot publish; speakers may publish only microphones.
  Tokens carry no client room-admin, camera, data or server API-secret grants.
- Existing real flutter_webrtc Dart/plugin-channel regression and direct-call
  HTTP tests still pass, including the accepted audio fix and video consent.
- `flutter analyze` completed without issues. Android/bootstrap preservation,
  optional Firebase/client setup and server-key rejection, accounts/preview
  HTTPS build configuration, workflow YAML, artifact/version agreement and ZIP
  integrity/exclusion checks passed.
- The schema retains the exact 0.6.1 prefix and appends room tables/indexes only.
  Roster profiles are fetched in one batch query, rather than one network round
  trip per room member. Earlier account/chat/media persistence checks pass.
- Inspected real Flutter-rendered member, moderator, landscape and 320px large
  Arabic text screens with shaped Arabic and Material icons. The control panel
  wraps and remains reachable; enlarged-text widget checks pass. Preview media
  and participants are fake, not screenshots from a deployed phone session.
  Temporary render harnesses and host font paths are excluded from delivery.

## What remains to verify on devices

No LiveKit Cloud project credentials were supplied or provisioned by the
assistant. Real LiveKit WebSocket access, SFU audio, microphone permission
prompts, audio routing/Bluetooth, network changes and moderation token revocation
must be checked on at least two phones after setting the three ROOM_LIVEKIT_*
values on Northflank. A configured flag alone does not verify connectivity.
Also repeat a direct audio call and consented video upgrade as a device regression.

There is no local Android SDK/emulator or iOS signing environment. **No APK or
store binary was compiled here.** GitHub Actions is configured to build
TOMI-0.7.0.apk. PostgreSQL 17 is configured in CI; local backend runs used SQLite.
The assistant did not deploy to GitHub/Northflank or change PostgreSQL, R2, TURN,
Firebase or Cloudflare. Keep those working settings.

## Supported scope and operational limits

LiveKit Cloud is required; self-hosted URLs are refused because this implementation
relies on Cloud token revocation. API keys stay on the server. Initial join tokens
last 60 seconds; the SDK/SFU manages the connected session. Memberships are tied
to TOMI sessions, and each new attendance gets an opaque SFU identity.

API synchronization is every two seconds, heartbeats every ten, API sync failure
and SFU reconnect grace 25 seconds, stale server attendance 45 seconds, and empty
room closure 600 seconds. Closed room metadata is purged after seven days, once
SFU cleanup has succeeded. Timers are opportunistic and may run slightly later.

Moderation uses persistent desired-permission/removal jobs. An unavailable SFU
can delay actual enforcement; pending status is shown rather than falsely
confirming the media change. Kicks deny new tokens, and all old identities are
revoked even if DeleteRoom already disconnected them. Cleanup retries after an
API restart. These guarantees still depend on the external provider being reachable.

Only foreground audio rooms, up to 30 participants and eight mic seats. Back or
backgrounding leaves. No room camera/screen share, recording, E2EE, background
service, OS call UI or room push invitations. Existing direct calls retain their
0.6.1 consent, timeout and foreground limitations. Deployment instructions and
the device acceptance sequence are in START_HERE_AR.md.
