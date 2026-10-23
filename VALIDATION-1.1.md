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
