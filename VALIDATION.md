# TOMI 0.8.0 validation

Date: 2026-10-15 (Baghdad). User accepted0.7 on their devices and authorized0.8
using their96-second voice-room video. Baseline ZIP SHA256:
26d9c654f7cec63fc4e12870cf69e125f163e28966b11d7cf8ff4c8e1cdec253.
Source version0.8.0+9; Node24.19.0, Flutter3.47.7, Dart3.13.5.

## Local verification

- Backend:69 tests using real SQLite, including all47 pre-room account, chat,
  media and call cases and22 room cases. The full suite passed; the22 room
  cases were rerun successfully after the final occupied-seat/moderator fix.
- Flutter:89 tests with TOMI_CALL_INTEGRATION=1, covering the previous80 tests
  and9 additional gift/settings/lifecycle/widget cases. No tests are skipped
  in that run. The9 new feature cases were rerun after the final UI fix.
  Static analysis has no issues.
- Real HTTP/SQLite contract:two AccountControllers/VoiceRoomsControllers create
  and join a room, request/approve/mute a mic, set room options, fetch catalog
  and wallet, send a gift, observe exact XP/level and a recipient event, send
  room chat, read contribution ranking, promote/kick/close. The API and database
  are real. Client audio engines and SFU provider are explicit fakes.
- Real LiveKit Node SDK signs/verifies mic-only JWTs. Tokens never grant camera,
  screen share, admin, metadata editing or data publishing. Existing durable
  SFU moderation/revocation tests still pass, including retaining removal jobs
  after DeleteRoom and replay after API restart.
- Owner reservation holds while absent, including reserved capacity; reentry
  always returns the owner to seat-1. Legacy seat0..7 cannot collide. Migration
  of an active owner preserves identity. A real0.7 SQLite database upgrades
  without changing its account, session or room. The exact0.7 schema is retained
  as a prefix and a test fixture.
- Gift receipt insertion, conditional debit, XP increment and feed events are
  atomic. Concurrent sends cannot overspend. Stable request IDs replay the same
  receipt; changed retries and reuse of a message ID fail. Missing recipients,
  self-gifts, forged prices, invalid quantities, nonmembers and blocks are denied.
  Every level boundary1–10 is checked, including exact thresholds and the cap.
- Room options, hashed passwords, read access to admin data, locked/muted seats,
  invitations/consent, occupied-seat unmute, protection of fellow moderators,
  offline moderator removal, blacklist reversal and audit
  records are covered. Cover/chat image tests check ownership, scope, attachment
  replay, the image switch and cleanup on cover replacement. Existing R2 image
  checksum/format and private-chat media tests remain in the complete suite.
- Client tests check stable IDs after uncertain gift sends, late replies after
  leaving, gift loading across leave/rejoin, invitation acceptance without
  capture, and gallery handoff muting without automatic unmute. Normal background
  still leaves and releases the room.
- Native Flutter UI was rendered and visually inspected for the main room, gift
  picker and white settings page. Arabic DejaVu Sans and real Material icon fonts
  were loaded for local previews; production uses the app's existing fonts.
  Narrow320px, double text, landscape, recipient/gift selection, request controls
  and setting toggles are covered. The temporary screenshot harness is excluded
  from the delivered source. Preview profiles, balances and messages are test data.
- Android bootstrap/source-preservation, Firebase optional configuration,
  accounts/preview HTTPS configuration, workflow YAML and version/artifact
  consistency checks pass. Dependencies remain pinned to the accepted0.7 versions.

## Runtime and deliberate scope

Owner seat-1 is permanent, companion-2 is optional, and regular seats0..7 retain
the existing database CHECKs. Up to30 members include the owner's reserved place.
An already-full legacy room removes its latest guest to make room for an owner
returning during the upgrade; subsequent admissions reserve capacity up front.

1000 trial coins are granted once per account,500 can be claimed every24 hours,
and all prices/thresholds live in server/src/room_catalog.mjs. Coins have no cash
value, purchasing, withdrawal or link to the earlier web economy. A recipient gets
a durable gift entry, not spendable credit. Levels belong to the room and range
from1 at0XP to10 at25000XP, with no level11. XP persists when the room empties.

Rooms now stay in the lobby until the owner explicitly closes them. Empty SFU
media rooms can expire naturally and are recreated by ensure(). Room settings,
gifts, XP and closed-room records remain in PostgreSQL. Snapshots expose the
latest40 room events, admin history the latest50, and top contributors the top10.
The UI exposes supported room functions; the reference app's separate games,
paid shop, music player and cash envelopes are outside this release.

Client API poll2s, heartbeat10s, API/SFU reconnect grace25s and stale attendance45s
are retained. Joins, invitations and approvals never capture audio. A short
system gallery handoff mutes first and never automatically resumes the mic;
background without that handoff leaves. High quality96kbps vs speech24kbps applies
on the next room connection. No new service, payment or credentials are required.

Desired SFU permissions/removals persist. Pending enforcement is visibly marked;
a database update does not prove a remote participant has already disconnected.
Existing direct-call audio/video consent, foreground and timeout behavior remains.

## Limits

No Android SDK/emulator, APK build, signed mobile build or actual device RTP/SFU
session was run here. Local PostgreSQL and user LiveKit/R2/Northflank services were
not contacted. GitHub Actions includes a real PostgreSQL17 test job and Android
build; those jobs must run in the user's repository. LiveKit publishing, native
microphone permissions/routes, Bluetooth, gallery lifecycle and network handoffs
still need device acceptance after installing0.8. The user previously accepted0.7
on devices; that acceptance does not substitute for trying this new release.

No remote repository, cloud service, subscription or account was changed by the
assistant. Room chat uses authenticated HTTP and existing image storage; provider
keys stay server-only. No recording, room video, background service or E2EE is
claimed. An uncertain send is kept in client memory with a stable ID; after app
restart, inspect balance/feed before intentionally sending a similar gift again.

Upgrade and device steps:START_HERE_AR.md. Durable continuation:TOMI-PROGRESS.md.
