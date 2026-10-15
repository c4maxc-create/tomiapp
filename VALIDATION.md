# TOMI 0.6.1 validation

Baseline: saved final TOMI 0.6.0 source. Date: 2026-10-15 (Baghdad).
Node 24.19.0; Flutter 3.47.7; Dart 3.13.5.

## Verified locally

- All 47 backend tests passed on real local SQLite: the 42 existing tests and
  five new media-change cases. They cover participant and session isolation,
  consent, both-camera readiness, requester-owned SDP rounds, restarts,
  duplicate requests, rejection/cancellation/expiry, denied cameras, returning
  to audio, requiring consent again, payload/revision bounds and end cleanup.
- All 70 Flutter tests passed with TOMI_CALL_INTEGRATION=1: 50 non-call tests,
  17 call controller/UI cases, two plugin-channel regression cases and one
  expanded real Node HTTP contract test. Coverage includes initial calling,
  buffered ICE, permissions, logout/background, stale responses, voice-note
  audio release, consent and refusal, camera denial, return to audio, and
  cancelled/superseded camera-permission results.
- The plugin regression uses the real flutter_webrtc Dart offer/answer path
  with a mocked platform channel. It proves that audio requests explicitly
  suppress the plugin's default video receive option and video requests retain
  it. It does not run a native WebRTC media engine.
- The HTTP contract uses two actual CallControllers and a real local Node API.
  It covers initial audio, callee-initiated video upgrade, consent, readiness,
  SDP role reversal, successful application, unchanged call duration, return to
  audio, a fresh upgrade prompt, refusal, hangup and history. Its media engines
  are fake; no microphone/camera packets are exchanged by this test.
- Flutter analyze completed with no issues. Android/bootstrap, optional Firebase
  client configuration and server-key rejection, HTTPS build configuration,
  workflow YAML, artifact names and version agreement checks passed.
- The database schema preserves the exact 0.6.0 prefix and appends only the
  media-change table. Existing accounts, chats, media and recovery checks pass.
- Inspected real Flutter-rendered voice, video, approval and landscape screens,
  including Arabic shaping and Material icons. Video fills the surface; the
  draggable preview remains above controls in portrait and landscape. The
  enlarged-text 320px widget check also verifies the preview's drag bounds.

## Device acceptance still required

The user reported working video and failing audio on 0.6.0. The verified code
cause was createOffer/createAnswer using the plugin default video receive
constraint during audio-only calls, conflicting with the API's audio-only SDP
validation. This release overrides those constraints explicitly and selects
Android's communication audio configuration.

No Android SDK/emulator or iOS signing environment was available; no APK or iOS
binary was compiled here. PostgreSQL 17 is configured in GitHub Actions, but
local tests above used SQLite. The hosted API, GitHub, database, R2, Firebase and
Cloudflare accounts were not modified by the assistant.

Deploy this API and install newly built 0.6.1 APKs on BOTH phones before testing.
Keep the existing database and TURN/FCM/R2 values. Follow START_HERE_AR.md for
bidirectional voice, earpiece/speaker, mute, camera switching, both initiators,
accept/refuse/cancel/no response, denied permission, repeat voice/video changes,
Wi-Fi/mobile data and TURN/FCM checks. Automated transport tests do not prove
native routing, RTP, permission dialogs, capture indicators or real TURN/FCM.

## Scope and limits

Foreground, one-to-one calls. Backgrounding ends media. Incoming FCM is a normal
alert opening the app for explicit acceptance, not CallKit, ConnectionService
or full-screen OS ringing. Permanent provider keys remain on the API; the Node
API stores state/history and temporary signaling, not call recordings. SDP/ICE
is bounded, not logged and deleted at call end.

Video upgrades require the other participant's approval and readiness from both
sessions. Approval expires after 30 seconds, camera readiness after 60 seconds,
and SDP negotiation after 30 seconds. A call allows at most 30 media changes.
Either participant can stop video and retain the audio peer; a future upgrade
requires approval again. Declines, cancellations and denied cameras retain audio.

Initial ringing/setup, heartbeats and two-hour call bounds remain unchanged.
Background calls, ICE restart after changing networks, voice rooms/SFU, groups,
screen sharing, recording, verified E2EE identity and store signing remain out of
scope. 0.7 voice rooms must wait for device acceptance of this fix.
