# TOMI 1.1 — run30 corrective validation, 23 October 2026

App **1.1.0-beta.1+16**, API **1.1.0-beta.1**. Base: source18,
TOMI-1.1-home-profile.zip,
SHA256 9f7e499dbced5dd196669dd58ef9f95e1b3918e9e94a87729bcfd91da9ec4d94.

## Executed on this correction

Official Flutter **3.47.7**, framework abaf9c523780a608bd46686fd5e53740a07077f8,
engine deb287481e3ce9468f3434937ced4240a70539ca, Dart **3.13.5**.
The SDK was obtained for this correction. The earlier source18 record below
remains historical; Flutter execution is now available locally.

- `flutter pub get --enforce-lockfile`: passed. pubspec.lock is byte-identical
  to source18. No dependency upgrades were made.
- `flutter analyze --no-pub`: **No issues found**,18.1 seconds.
- Focused accounts/social/home tests: **29 passed,0 failed/0 skipped**.
  This is a subset of the complete suite, not29 additional unique tests.
- Complete `flutter test --no-pub --reporter expanded`: **166 passed,7 skipped,
  0 failed**,14 seconds. The7 are the existing opt-in real HTTP contracts.
- Then all7 HTTP contracts were enabled with their existing CI environment
  flags: **7 passed,0 failed/0 skipped**,4 seconds, against temporary local Node
  APIs and data. This covers calls, rooms, messaging, identity, moderation,
  privacy and the new home/story contract. **173 distinct Dart tests executed**.
-8 new regressions cover320x640 and800x420 at1.0/1.5/2.0 text scaling, with
  bold accessibility text at2.0, plus manual refresh without polling and live
  polling stopping on logout. Existing test assertions remain enabled.
- All87 Dart source/test files parsed with both the actual Dart SDK formatter
  and dart_style WASM. The6 changed Dart files pass the SDK format check.
- Official GitHub workflow parser: **0 errors** after parse and conversion.
- Backend, schema, native sources, tools, workflow and dependency lock are
  byte-identical to source18. The user's run30 screenshots show the backend
  job succeeded; its test counts are not inferred from that screenshot. The
  earlier Node evidence below is retained and was not rerun for unchanged code.

Evidence: **validation/1.1-widget-fix/**, including the complete logs, SDK
version, and results.json. CI mode prevents Flutter's cloud-instance metadata
probe; analytics are disabled. TAR_OPTIONS=--no-same-owner was used only for
SDK extraction in this root-mapped container. These local settings do not
change the project's GitHub workflow.

## Remaining acceptance

Android SDK/build/signing and physical-phone FCM/camera/audio acceptance were
not performed here. Run a new GitHub workflow from the corrected commit to
produce the APK, then follow WIDGET_FIX_1.1_AR.md and the two-phone checks.
Production was not deployed or modified by the assistant. Subscription prices
and purchasing remain deferred as requested.

---

## Historical source18 feature validation (before this correction)

# TOMI 1.1 — validation record, 23 October 2026

Base: source17, TOMI-1.0-beta1-ci-timeout-fix.zip,
SHA256 d1ec21a8ed9b9b63939a81db16ae6364c8a219992f3b21a29fd135f3769c1842.

## Executed locally

- Full Node/SQLite API suite: **133 passed,0 failed/0 skipped**,151856.885588ms.
  Includes the129 prior cases and4 new home scenarios.
  Evidence: validation/1.1-home/node-full.log.
- Final home API suite: **7 passed,0 failed/0 skipped**,7906.220042ms. It repeats
  those4 and adds3 new cases; **136 distinct Node tests** have passed across the
  full and focused runs. Evidence: validation/1.1-home/home-api-final.log.
- New behaviors exercise actual HTTP and SQLite:24h visibility, restart,
  following-only story strip, profile/post rings, idempotent viewing and private
  viewer list, ownership, safe cleanup, missing/foreign/reused image rejection,
  concurrent publish retry, account erasure, follower pagination, read activity
  isolation, push deduplication, saved posts, real H264/AAC MP4 metadata and60s
  rejection, and generic FCM payload/channel/account routing with stub transport.
-17 JDK native notification policy scenarios passed, including disabled,
  wrong-account, forged route and existing call consent paths.
- Android bootstrap/source preservation and Firebase setup checks passed.
  The generated manifest's default channel and copied native source are checked.
-8 Android disk safety tests and6 release/signing safeguard tests passed.
  Disposable test signing material was generated and removed by the tests.
- Official GitHub @actions/workflow-parser0.3.61 parsed and converted the current
  workflow with no errors. Both cleanup step environments,30/45minute limits,
  signing cleanup and every prior test remain. The7th real HTTP Flutter contract
  is enabled through TOMI_HOME_INTEGRATION.
- Dart source/tests were parsed with the dart_style WASM formatter; see
  dart-all-parse.log. Changed application files are formatted. Import paths and
  source packaging are checked. This is **syntax parsing**, not a type-analysis
  or widget execution claim.

## Prepared for GitHub/device execution

Flutter/Dart SDK and Android SDK are absent locally. No Flutter analyze, widget
suite, Android compilation, APK/AAB signing, real PostgreSQL, or physical-phone
FCM/camera/audio delivery result is claimed in this session. Attempts to obtain
an SDK from the external archive were unavailable. The existing pinned SDK and
CI dependency lock were retained.

9 new Flutter unit/widget scenarios cover session fencing, ring state, push
recipient routing, avatar destination, hold/tap story navigation, settings and
subscriptions, follower navigation and authenticated saving. A new real HTTP
Dart-to-Node home contract is enabled alongside the6 prior contracts.

Run the complete GitHub workflow from the new commit, update the API, and perform
HOME_PROFILE_1.1_AR.md's two-phone acceptance. The subscriptions catalog has no
prices or active purchase path because those service details are deferred.
