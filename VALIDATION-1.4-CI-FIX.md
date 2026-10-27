# TOMI 1.4 — CI38 and media retry validation

27 October 2026 (Baghdad). Full source package **TOMI-1.4-ci-fix.zip** extends source25, **TOMI-1.4-owner-admin.zip**, SHA256`28d9e4f5eccfec0c2ee6d82513a94087163e3d6b14d6cbefbde52a40b2cce28b`. App **1.4.0-beta.1+21**, API **1.4.0-beta.1**.

## Observed problem and scope

The user's three screenshots of hosted run38 show the PostgreSQL step terminated after its8-minute limit and APK build skipped. The visible owner tests passed. The last visible privacy-test name does not establish a failure in that test. The original source's complete PostgreSQL suite passed locally170/170in241.848seconds, its privacy suite13/13passed, and its encrypted restore passed. The exact hosted timeout was not reproduced locally and no private GitHub session or remote logs were accessed.

The fix gives the PostgreSQL step15minutes and API job40minutes, retains all60-second individual test bounds, serial process-isolated execution and all database/restore gates, and adds a complete-report check. The runner requires exactly173passes, zero failure/cancellation/skip/TODO, and a final duration. It rejects missing or partial output even if Node exits0. The count manifest is maintained in`server/tools/test-suite.json`when tests are added or removed. Report pipes use a test-only synchronous-write preload. This is preventive hardening for the report-loss class discussed in the official[Node issue64833](https://github.com/nodejs/node/issues/64833); it is not proof that this issue caused run38.

## Runtime races found and repaired

A complete PostgreSQL run exposed a real story retry race: one accepted201response and one400UPLOAD_INVALIDfor the same intent. A barrier in the existing MP4 test now pauses the empty receipt read until its twin commits, reliably reproducing the unpatched failure on SQLite. The fix rechecks the matching receipt when upload state changed and again inside the user-lock transaction before limits or attachment writes. Changed payloads and expired/deleted stories retain their rejection behavior.

The next complete run exposed the equivalent private-voice race. The existing voice test now forces its receipt/upload ordering and explicitly checks both success statuses. Chat preflight reconciles only UPLOAD_INVALIDagainst the same actor/nonce/payload hash; the existing thread/session transaction still validates access and returns the original message. This covers private image/audio/video/document preflight without hiding other errors, reattaching media, or duplicating a message.

A further run caught a1msstory-duration error: creation and expiry read the clock separately. Expiry now derives from one creation timestamp plus86,400,000ms. The exact24-hour assertion remains unchanged.

All three failures were corrected in code; no assertion was weakened and no test was removed. The existing MP4 and voice tests were strengthened without adding to their count. Three runner/report regression cases bring170original cases to173.

## Final executed results after every correction

| Check | Result |
|---|---|
| Node24.22.1 / SQLite complete suite |173/173passed;263.336s |
| Node24.22.1 / native PostgreSQL17.10 complete suite |173/173passed;267.872s |
| Completeness gate |Passed on both complete runs; no failure, cancellation, skip or TODO |
| Encrypted pg_dump / authenticated pg_restore17.11 |Passed, including reopening and1.4staff/special/account state |
| Focused test runner regressions |5/5passed: retained failure/timeout cleanup, report pressure and incomplete-output rejection |
| Home/stories focused cases |7/7passed after receipt correction; final full runs cover the single-clock correction |
| Voice/media/push focused cases |10/10passed after chat correction |
| Android CI safeguards |8/8passed |
| Official GitHub workflow parser0.3.61 |Parse and template conversion:0errors |

The complete Node commands ran after all production edits and the results carry`story_race_fix`, `media_race_fix`and`expiry_clock_fix`markers. Earlier runs are historical and are not counted as current passes. Logs were checked after closing them in the same execution context; a preliminary live copy that appeared partial is not treated as independent evidence of a Node failure. The expected generic error from the negative metrics fixture does not indicate a failed test.

The native test runtime, isolated UID0startup workaround, loopback-only test databases and client-library wrappers follow the1.4test setup recorded in`validation/1.4-owner-admin/postgres-runtime.json`. No production file was changed for runtime setup. Binaries, databases, keys and wrappers remain outside the package.

## Preservation and remaining deployment checks

All387source25paths remain. All client files, assets, dependency locks, schema, migration implementation, owner/economy/moderation controls and service configuration are byte-identical to source25. Runtime API changes are limited to`server/src/home.mjs`and`server/src/chat.mjs`; test infrastructure, tests, workflow budgets and current documentation also change. `source-preservation.json`lists the precise delta. The package manifest verifies every file and CRC, with caches/builds/private configuration excluded.

No Flutter/UI file changed. The prior203distinct ordinary Dart cases and8HTTP contracts are retained as historical source25results, not newly executed here. The workflow keeps fresh Flutter analysis, tests and all8contracts before APK creation. Node's final complete runs exercise actual HTTP requests for the changed API behavior.

No live Render service, repository or account setting was changed here; no APK/AAB was built. The user must upload the complete source, create a newmaincommit, deploy the existing API from that commit and start a freshaccounts/debug workflow. Hosted completion, required real Firebase client configuration and physical-device acceptance remain deployment checks. See **CI_FIX_1.4_AR.md**. Older validation folders retain their original dates and scopes.
