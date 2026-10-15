# TOMI 0.7.0 — Native Flutter voice rooms

Arabic Android social app, Node 24 API and persistent PostgreSQL. The user accepted
0.6.1 on their devices before authorizing this release. Start with
[START_HERE_AR.md](START_HERE_AR.md) for the existing GitHub/Northflank deployment.
This ZIP contains source; it is not an APK or a deployed service.

## Included

- All 0.6.1 accounts/recovery, profiles, follows, posts, private chats, private
  images/voice notes, avatars, optional FCM, call history and voice/video calls.
- LiveKit Cloud audio rooms: named rooms, up to 30 members and 8 mic seats,
  listener joins, explicit mic enable, requests, approval/refusal, owner and
  moderator roles, administrative mute, speaker removal and participant kicks.
- Server-enforced microphone-only publishing, durable permission/removal jobs,
  session binding, opaque connection identities, short initial join tokens and
  one room/call at a time. No provider admin grants in the client.
- Bounded reconnection/heartbeat cleanup and removal of rooms left empty for
  ten minutes. Closing a room disconnects its participants via the SFU.

## Runtime setup

Flutter **3.47.7** / Dart **3.13.5**; app **0.7.0+8**. Dependencies are locked.
`livekit_client 2.13.1` shares the existing `flutter_webrtc 1.6.2+hotfix.4` version.
API `livekit-server-sdk 2.19.1`, Node **24**, PostgreSQL **17** in CI.

Keep existing DATABASE_URL, R2, TURN and Firebase configuration. Add only these
server environment values from one LiveKit Cloud project:

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

Use the same database. `schema.sql` keeps the exact accepted 0.6.1 schema prefix
and appends room tables and indexes. No reset or new database is required.

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
TOMI_CALL_INTEGRATION=1 flutter test test/call_api_integration_test.dart test/room_api_integration_test.dart
```

Run GitHub Actions **TOMI 0.7.0 Android** in `accounts` mode. The workflow also
checks PostgreSQL and produces **TOMI-0.7.0.apk**. The API health version is 0.7.0.
Local loopback contract tests use real Node HTTP/SQLite and explicit fake media
adapters; they do not prove real RTP or LiveKit connectivity. See
[VALIDATION.md](VALIDATION.md) for the checks actually run and their limits.

## Scope and recovery

Rooms and calls operate while the app is in the foreground. Leaving the app or
pressing back from a room ends participation. Room mic permission is requested
only when the user presses enable; granting a seat never captures audio.
Camera, screen share, recording, background audio, E2EE and push room invites
are outside this release. Existing direct-call video consent remains unchanged.

The client polls room state every two seconds, heartbeats every ten, closes
participation after 25 seconds without API sync and bounds SFU reconnects. The
API removes stale attendance after 45 seconds, closes empty rooms after 600
seconds and later purges closed metadata. Reconnecting SFU sessions may briefly
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
