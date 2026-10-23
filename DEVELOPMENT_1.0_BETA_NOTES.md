# Latest correction — accounts/API CI timeout

Work: tomi_10_ci_timeout_fix_work. New user screenshot/run39832689907 shows
accounts-api cancellation at10m18s while PG7m17s cases shown are successful.
Follow-up run28/commitd609686 summary explicitly confirms exceeding10m0s;
timeout is confirmed, while complete test results remain unavailable. Only change: accounts-api timeout-minutes10->30. Android stays45.
All runtime/API/native/tool code, checks and signing gates unchanged. Full
workflow official parser0.3.61 returns0errors; structural diff only1numericvalue.
Standalone tomi-android.yml updated; canonical full source is
TOMI-1.0-beta1-ci-timeout-fix.zip. Upload the single workflow, commitmain, NEW
accounts/debug run. Do not claim hosted tests/restore/disk/APK complete. Use the
latest standalone progress/source receipt; older corrections below are history.

# Latest correction — invalid runner context, run27

Work: tomi_10_ci_context_fix_work. User screenshot shows line85:27 rejects
runner.environment in job env. Move value into the two cleanup step env maps.
Official @actions/workflow-parser0.3.61 reproduces previous failure and returns
zero corrected errors.8 cleanup tests passed; all runtime/tool code unchanged.
Standalone tomi-android.yml is the minimal replacement after source15 upload;
full current source is TOMI-1.0-beta1-workflow-fix.zip. Upload corrected workflow
into SAME .github/workflows on main, then start a NEW accounts/debug run.
Do not claim hosted execution, reclaimed disk or APK success. Continue from latest
standalone progress and source identity; source15/14 receipts below are historical.

# Current correction — CI disk exhaustion,2026-10-22

User uploaded screenshots/run24 and kjj.txt with No space left on device.
Work: tomi_10_ci_fix_work. Source14 baseline is unchanged runtime/API/native code.
Fix: guarded hosted-Linux/android-only toolchain cleanup, actual Flutter NDK
preservation/pruning,20GiB APK and10GiB AAB gates,2Gradle workers/no task-output
cache, disk diagnostics,8 safety cases. No external push or hosted APK build.
Deliver TOMI-1.0-beta1-build-fix.zip, upload contents to SAME main, start a NEW
workflow with accounts/debug. Old reruns use old source. CI_BUILD_FIX_AR.md is
entry point for this correction; latest standalone progress carries save receipt.

# TOMI1.0 beta1 — implementation and continuation

Authorized2026-10-17: «اكمل التطورات و التحديثات». Finalized2026-10-22 Baghdad.
App1.0.0-beta.1+14 / API1.0.0-beta.1, based on exact final0.12 source13 SHA256
5c87061e4fd14259ee4067c04373234e816db1db7d906908a38c55537934da8a.

Implemented: password-confirmed app/browser erasure, private durable receipt,
session/push/call/room revocation, account-specific local cleanup, durable media
erasure and expiry/retention, public Arabic policies, registration policy receipt,
optional supplied-key Android signing and beta acceptance gates. Current0.12
moderation/operations and previous app functionality remain included.

Workspace maintenance removed scratch after checkpoint74. Recovered checkpoint74
and authoritative progress76; retained controller/session-fence tests already
there. Reapplied final report-erasure rejection and target gate, explicit POST form
fallback with JS parsing check, registration metadata mock, and final guides.
Re-ran129 Node and28 targeted privacy/moderation cases,6 release tools,11 JVM and
configuration checks successfully. VALIDATION.md documents all remaining limits.

No current Flutter SDK/cache in the restored runtime. Earlier partial Dart analysis
is historical evidence only.155 intended Flutter cases and6 real HTTP contracts,
PG17/restore, APK/AAB and physical-device/live-provider acceptance remain pending.
Do not claim a ready APK, approved store app, production capacity or full compliance.

Delivery: TOMI-1.0-beta1.zip; README.md and START_HERE_AR.md are entry points.
PRIVACY_1.0_BETA_AR.md explains erasure/retention/operator configuration;
RELEASE_1.0_BETA_AR.md explains debug first and optional signature-compatible
APK/AAB. SOURCE-FILES.sha256 verifies contents, excluding itself.

Next: upload contents to the SAME ToLo10/tomiapp main, run debug Actions and all
checks, deploy matching API before installing, test two phones, then configure
actual operator/support/backup policy and optional existing-key signed beta.
Backups must include separate R2/secrets/expiry/replay of post-backup erasures.
No old/mixed API after erasure. No new projects, database reset, keys, payments,
production deletion/deployment or store upload from this assistant session.

Continue from the latest standalone TOMI-PROGRESS.md and current canonical source
identity libfile_ff8a76e8c2788191a55eafa9acc54e37. Save checkpoints after meaningful
parts/5–10min. Final ZIP stays immutable; append confirmed version/file id/SHA256
to standalone progress after saving. Do not restart the completed implementation.
