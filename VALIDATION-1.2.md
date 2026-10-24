# TOMI 1.2 chat validation

Validated 24 October 2026. App `1.2.0-beta.1+17`; API `1.2.0-beta.1`.
Baseline: immutable source19, `TOMI-1.1-widget-fix.zip`, SHA256
`af765fde86264868597c59d10321db79b4a3597ade55fa80f6341505a6b98d01`.
The complete source and evidence are delivered in `TOMI-1.2-chats.zip`.

## Executed results

| Check | Result | Evidence in `validation/1.2-chat/` |
| --- | --- | --- |
| Flutter analyze | No issues | `flutter-analyze.log` |
| Complete Flutter suite | 183 passed, 8 HTTP cases conditionally skipped, 0 failures | `flutter-full.log` |
| All eight real Dart-to-Node HTTP contracts, explicitly enabled | 8 passed, 0 skipped, 0 failures | `flutter-http-contracts.log` |
| Node/SQLite complete suite | 145 passed, 0 skipped, 0 failures | `node-full.log` |
| Chat UI and persistence cases | 17 passed, included in the 183 above | `flutter-chat12-render.log` |
| Optional dark/light visual exports | 4 passed; all four images inspected | `flutter-chat12-render.log`, `previews/` |
| Official GitHub workflow parser | Parse and conversion: 0 errors | `workflow-parser.log` |
| All Dart source/test syntax | 91 files parsed | `dart-all-parse.log` |
| Bootstrap and Firebase optional setup | Passed | `check_bootstrap.log`, `check_firebase.log` |
| Native notification policy | 17 scenarios passed | `check_mobile_policy.log` |
| Android disk safeguards | 8 tests passed, isolated temporary fixtures | `check_android_ci.log` |
| Release tooling | 6 tests passed using disposable test signing material | `check_release_tools.log` |
| Source and dependency preservation | 132 previous lock entries unchanged; 12 additions; 53 protected files byte-identical | `source-preservation.json` |

There are **191 distinct executed Dart cases**: 183 ordinary cases plus the
8 separately enabled contracts. The focused chat runs and visual exports are
additional verification, not extra unique ordinary cases. The 9 new Node cases
are already included in the total of 145.

## Coverage of this change

The chat tests cover 320×640 and 800×420 layouts, text scales 1×/2×, a visible
keyboard, immediate inbox filters, emoji insertion, sticker sending, attachment
menus, group creation, and reopening cached history while a refresh is delayed.
They also verify account-scoped cache restoration, a document send whose reply
was lost followed by disk restart, a message queued behind a slow upload,
removal from a group while offline, reuse of a still-valid private media URL,
a saved group-create request after closing the page, and a late server response
after logout.

The new HTTP contract exercises the actual Dart controller against Node HTTP,
SQLite and a local R2-compatible byte-transfer fixture. It covers groups,
documents, stickers, read/reply/reaction/delete behavior, group routing through
the existing notification route and member revocation. The existing seven
contracts were also enabled and executed.

Node coverage includes membership and joined-history restrictions, stable
creation/message request IDs, owner transfer, mixed inbox pagination, verified
private uploads and checksums, unauthorized reads, replies/reactions/pins,
account erasure and media cleanup, WebSocket delivery and revocation, and group
notification deduplication/read/leave eligibility. Cloud delivery is stubbed
locally; these tests do not send notifications to real users.

Four visual exports show the real Flutter inbox/thread widgets in dark and
light themes. Only QA hosts load a locally available Arabic font and sample
initial avatars. Production widgets use the existing app typography/avatar
system. The voice progress bars are a visual playback/seek indicator, not an
acoustic waveform extracted from the recording.

## Reproduction

Flutter 3.47.7 / Dart 3.13.5, Node 24.19.0, Java 17 and Python 3 were used.
`flutter pub get --enforce-lockfile` restored the pinned cache after the runtime
changed. No prior package version or integrity checksum was upgraded.

```bash
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
```

Run the eight HTTP files listed in `.github/workflows/tomi-android.yml` with
`TOMI_CALL_INTEGRATION=1`, `TOMI_MESSAGING_INTEGRATION=1`,
`TOMI_IDENTITY_INTEGRATION=1`, `TOMI_MODERATION_INTEGRATION=1`,
`TOMI_PRIVACY_INTEGRATION=1`, `TOMI_HOME_INTEGRATION=1`, and
`TOMI_CHAT_INTEGRATION=1`. Run `npm test` from `server/`.

For this CI container, Flutter commands use `CI=true`,
`FLUTTER_SUPPRESS_ANALYTICS=true`, `DART_SUPPRESS_ANALYTICS=true` and, when
extracting SDK artifacts, `TAR_OPTIONS=--no-same-owner`. These prevent an
unnecessary cloud-environment metadata probe and preserve extraction behavior.
Release-tool verification used
`JAVA_TOOL_OPTIONS='-XX:ActiveProcessorCount=2 -Xmx256m'` for the constrained
local JVM; the test key was removed after verification.

## Delivery boundaries

No Android SDK build, APK/AAB signing, fresh PostgreSQL integration/restore run,
or physical-phone recording, camera, voice/video call, Bluetooth or FCM delivery
was executed here. GitHub Actions retains the PostgreSQL/restore tests and APK
build, including all eight Dart HTTP contracts. Use a new run on the uploaded
commit. Existing server migration statements are kept as an exact prefix, with
additive tables for the new chat features.

The source is complete and locally checked. Installation and real-device
acceptance follow the steps in `CHAT_1.2_AR.md`; API 1.2 must be deployed before
using the new groups/documents/stickers. No production deployment, external
message, real-user account deletion or user key change was performed.

The final ZIP receives a CRC check and a `SOURCE-FILES.sha256` manifest. Every
source19 path is retained. Home/profile/social, calls, voice rooms, identity,
games and native/tool sources remain byte-identical where protected by the
source-preservation check. Delivery receipts are kept in the standalone
progress log after saving; the delivered ZIP then remains immutable.
