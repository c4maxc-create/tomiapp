# نتائج التصحيح الحالي — TOMI 1.3.2

راجع **VALIDATION-1.3.2.md** لنتائج إصلاح إشعارات الهاتف وزر إنشاء الغرف. ربط الخدمات الفعلي على هاتف المستخدم يحتاج ملف Firebase وإعدادات الخادم المذكورة في FIX_NOTIFICATIONS_ROOMS_1.3.2_AR.md. لم يُبنَ APK أو تُفعّل خدمات حساب المستخدم من هنا. تقارير1.3.1 وما قبلها أدناه أرشيف.

---

# نتائج الإصدار الحالي — TOMI 1.3.1

راجع **VALIDATION-1.3.1.md** لنتائج التصحيح الحالي:159 اختبار SQLite و159 اختبار PostgreSQL17 فعلي ناجحة، واستعادة مشفرة ناجحة. نتائج1.3 و1.0 أدناه أرشيف؛ لم يُبنَ APK هنا.

---

# TOMI 1.0 beta1 validation

Source: app1.0.0-beta.1+14, API1.0.0-beta.1. Authorized2026-10-17;
recovered and finalized2026-10-22, Asia/Baghdad. Exact0.12 source SHA256:
`5c87061e4fd14259ee4067c04373234e816db1db7d906908a38c55537934da8a`.
Earlier0.12 results remain in VALIDATION-0.12.md. This file distinguishes source
checks from device/provider/build evidence; source delivery is not public launch.

## API CI timeout correction — 2026-10-22

User screenshot/run39832689907 shows accounts-api cancelled at10m18s, PostgreSQL
step7m17s, visible successful cases followed by The operation was canceled; the
Android job was skipped. The follow-up summary screenshot confirms run28/commitd609686 and explicitly
states: The job has exceeded the maximum execution time of 10m0s. The timeout
is therefore confirmed; full test counts and hosted completion remain unknown.
Raised only jobs.accounts-api.timeout-minutes10->30; Android budget remains45.

Official @actions/workflow-parser0.3.61 validates the full updated workflow with
zero parse/conversion errors. Structural YAML comparison confirms a single numeric
value changed. All tests, PG restore, cleanup, signing gates and runtime/tool/lock
bytes remain unchanged. No full tests were repeated for this timeout-only change.
Hosted completion, actual disk cleanup and APK remain pending a NEW corrected run.
Evidence: validation/1.0-beta1-ci-timeout/workflow-parser.log. If cancellation
persists or an assertion fails, inspect complete logs rather than skip the checks.

## Workflow context correction — run27

User screenshot: run27, commit32328ed, GitHub rejects runner.environment at line85,
column27 before any jobs start. The previous disk correction placed that context
in jobs.android.env, where GitHub does not permit it. Moved the exact same value
into env on the two cleanup steps. No cleanup helper, app/API/native/dependency,
input, build command, test or signing gate changed.

Executed official @actions/workflow-parser0.3.61 from actions/languageservices
on Node24.19.0, using its unmodified schema. The published JSON schema module was
loaded as ESM data for the standalone Node harness; no validation logic changed.
Before: reproduced exactly one Unrecognized named-value: runner at85:27.
After: zero errors after parseWorkflow and convertWorkflowTemplate. YAML diff
and runtime preservation checks passed.8 existing disk-safety tests passed again.
Evidence: validation/1.0-beta1-ci-context/workflow-parser.log. Hosted build and
actual disk reclamation remain unverified until a NEW run from corrected main.

## CI disk correction — 2026-10-22

User run24/commit29b07b9 screenshots show the accounts/database job successful,
then APK Gradle compilation failed with No space left on device. The uploaded
log confirms both dependency downloads and native-library merging hit disk
exhaustion. Detailed earlier CI test counts/logs were not supplied; do not claim
a successful APK or assistant-executed PostgreSQL/Flutter run from these images.

The corrected workflow reclaims unused hosted-runner tools and NDKs, retains the
actual Flutter-required NDK and compile tools, bounds Gradle workers/cache and
checks20GiB before APK/10GiB before AAB. All application/native/API code and locks
are byte-identical to source14.8 new cleanup-boundary tests,6 release-tool tests
and Bootstrap/YAML/preservation checks passed locally. Actual disk reclamation
and APK/AAB build remain pending a NEW GitHub run. CI_BUILD_FIX_AR.md and
validation/1.0-beta1-ci-fix/ contain the details and evidence. The executed checks
below are the retained source14 evidence; unchanged application tests were not
repeated solely for this workflow correction.

## Executed checks

- **129 Node tests passed, zero failures/skips**, actual SQLite/HTTP on Node24.19.0.
  Re-executed after checkpoint recovery, duration152420ms. The116 existing cases
  plus13 privacy cases passed. After adding the report-target erasure gate,
  **all28 privacy/moderation cases passed again**, duration43481ms.
- **6 release-tool tests passed**, including a real isolated disposable JKS key,
  pinned certificate/private-key password checks, private permissions, cleanup,
  idempotent Gradle changes and negative release-readiness gates. No user signing
  key was generated, read or changed. These are not APK/AAB signature results.
- **11 JVM notification-policy scenarios passed**, JDK17. Bootstrap source
  preservation, optional Firebase configuration and HTTPS/accounts/preview
  configuration checks passed again in the recovered workspace.
- The privacy HTTP fixture was smoke-tested during this task with real local
  SQLite, self-erasure, signed-out receipt status and peer-side message removal.
  No production account, external media store or live SFU was used.
- The exact0.12 schema prefix and fixture are preserved. A real0.12 SQLite
  database upgrades without changing password hashes, staff roles, reports or XP.
- The archive verifier checks base paths retained, ZIP CRC, every source digest,
  workspace/archive byte equality, unchanged8 native files and Flutter lock,
  schema prefix and absence of private/generated/cache files. Manifest excludes
  itself. Test evidence is retained in validation/1.0-beta1/.

## Privacy cases exercised

| Area | Evidence |
| --- | --- |
| Erasure authority | Current password, exact Arabic confirmation, strict input fields, session requirement and private43-character proof; wrong/reused proof, lost ACK, concurrent replay, username reuse and rejection of new reports on erased targets. |
| Authored data | Posts/comments/follows/profile/identity/XP/wallet/session removal; authored chat bodies and attachments scrubbed while peer messages and opaque shared gift ledgers remain; restart does not backfill erased XP. |
| Media | Image/audio/video public/private stores independently routed; provider failure, durable retry after restart, second deletion after16-minute old-PUT expiry, unrelated files retained. |
| Races and roles | Delayed authenticated writes and target follows cannot recreate data; platform owner must transfer ownership; suspended member browser deletion; admin cannot restore/grant an erased account. New report snapshots share the target's PostgreSQL erasure gate and are re-read after it. |
| Retention | Report/audit content scrubbed,90-day expiry,30-day receipt expiry, current registration-policy version only, acceptance erased with account. |
| Public pages | Arabic documents available signed out, escaped operator markup, strict contact/retention configuration, CSP/nonce/frame protection, same-origin vs hostile-origin requests, inline JS syntax and explicit POST form fallback. |

## Flutter evidence and limits

During the earlier implementation session, Dart analysis of the new privacy
folder reported no issues. Full-lib raw Dart analysis had97 diagnostics with
missing packages; normalized diagnostics matched exact0.12 under the same partial
cache. That was **not** a successful full flutter analyze. The restored runtime
no longer has the Flutter SDK/cache, so this historical analysis was not repeated.

Eight new privacy unit/widget cases and one real HTTP contract are prepared,
bringing the intended suite to155 cases. They cover durable receipts before
HTTP, storage failure, lost ACK/controller restoration, logout while storage
waits, late acceptance vs newer account login, retry after local vault failure,
disk cleanup and compact Arabic UI. **These9 new Flutter cases have not run.**
The registration mock now handles the0.12 moderation-access metadata request.

Actions configures full Flutter analysis/tests and6 real HTTP contracts for
calls, rooms, messaging, identity, moderation and privacy. Calls/rooms still use
explicit fake media/providers. Do not report155 passing tests or a rendered UI
until the actual CI/device results exist. Flutter3.47.7 and locked dependencies
must resolve in Actions; a missing SDK/package/build is a blocking CI failure.

## Still required

- Actual PostgreSQL17 test suite and encrypted pg_dump/pg_restore drill in CI.
  The drill now preserves the erasure marker and pending cleanup rows present
  at backup time. It does not replay erasures made after that backup.
- Full Flutter analysis/tests, Gradle compilation, debug APK, optional signed
  APK+AAB and actual apksigner/jarsigner artifact verification.
- Two-phone acceptance: permissions, background audio/camera behavior, Bluetooth,
  network changes, voice/video upgrade consent, account deletion while connected,
  notifications, local drafts and upgrade with a compatible signing certificate.
- Live SFU/TURN/R2/FCM behavior, expired provider cache/URLs and production load.
  Local SQLite tests do not establish1000-user capacity or provider costs.
- Real operator/support/public-origin/backup-retention settings before signed
  distribution. Declared retention is not an automated backup schedule; database,
  R2 and secrets need scheduled backups, expiry and isolated restore acceptance.
- Before opening an old restored database, reapply newer erasures and verify
  cleanup. Do not roll back/mix old APIs against a database containing erasures.

## Reproduction

```bash
cd server
npm ci --ignore-scripts --no-audit --no-fund
npm test
cd ..
python3 tool/check_release_tools.py
python3 tool/check_mobile_policy.py
python3 tool/check_bootstrap.py
python3 tool/check_firebase.py
TOMI_API_URL=https://api.example.test python3 tool/check_build_config.py
bash tool/bootstrap_android.sh
flutter pub get
flutter analyze
flutter test --reporter expanded
TOMI_CALL_INTEGRATION=1 TOMI_MESSAGING_INTEGRATION=1 TOMI_IDENTITY_INTEGRATION=1 TOMI_MODERATION_INTEGRATION=1 TOMI_PRIVACY_INTEGRATION=1 flutter test --no-pub test/call_api_integration_test.dart test/room_api_integration_test.dart test/messaging_api_integration_test.dart test/identity_api_integration_test.dart test/moderation_api_integration_test.dart test/privacy_api_integration_test.dart --reporter expanded
```

No external repository push, hosted deployment, user deletion, production load,
store publishing, purchased service or real signing-key change was performed.
