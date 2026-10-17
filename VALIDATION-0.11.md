# TOMI 0.11.0 validation

2026-10-16, Asia/Baghdad. App0.11.0+12, Flutter3.47.7 / Dart3.13.5, Node24.
Authorized continuation: «الان اكمر مراحل التطوير الباقية».
Exact delivered0.10 ZIP baseline SHA256:
ee348a55716778ad66999f62d3fafb622ab18827e51ce18f4eb6793723b815ae.
Earlier results remain in VALIDATION-0.10.md, VALIDATION-0.9.md and VALIDATION-0.8.md.

## Checks run

- **137 Flutter tests passed, no skips**, concurrency1, with all4 HTTP contracts enabled:
  TOMI_CALL_INTEGRATION=1, TOMI_MESSAGING_INTEGRATION=1 and TOMI_IDENTITY_INTEGRATION=1.
  Includes119 baseline cases and18 new identity/controller/UI/HTTP cases.
  After resuming, only the gift-overlay test fixture was aligned to the actual
  nested recipient JSON and an assertion for the recipient name was added. That
  targeted rerun was blocked after the external package cache was cleared and
  dependency downloads were denied. All production code matches the successful
  full-run checkpoint; CI should rerun this final test fixture with dependencies.
- **93 Node tests passed, no skips**, on actual local SQLite. New fixtures honor the
  guarded local tomi_test PostgreSQL URL. PostgreSQL was not run locally.
- **Flutter analysis: no issues**. Changed Dart source is formatted. App, API,
  workflow and artifact versions agree; dependencies are unchanged from0.10.
- **11 JVM notification policy cases passed** on JDK17. All7 production Java files
  and the policy test match the delivered0.10 bytes. No native API or permission
  was added; a full APK was not built here.
- Bootstrap/source preservation, optional Firebase configuration and public
  HTTPS/accounts/preview build-configuration checks passed.
- Delivery checks require the new source/tests/guides, verify ZIP CRC, every file
  digest and workspace byte equality, and exclude credentials, generated builds,
  SDKs, caches and node_modules. SOURCE-FILES.sha256 excludes itself.
  The exact0.10 schema prefix is preserved.

## Evidence covered

| Area | Cases exercised |
| --- | --- |
| User XP | Every threshold, level10 cap, independent user/room levels, exact committed gift value, concurrent replay granting once, changed nonce rejection, insufficient coins and XP-limit transaction rollback. Recipient gets statistics and badges without spendable coins. |
| Identity permissions | Authenticated catalog, unknown styles and supplied XP/user IDs rejected, locked styles denied, revision conflicts, API-restart persistence, propagation through profiles/posts/conversations/rooms. |
| Photos | Bio edit preserves animated portrait. A different preset, committed upload or removal restores the photo/preset, increments identity revision and preserves frame/entry. Replaying an old photo request does not erase a later style. |
| Badges/upgrade | Host creation replay counts once; recipient gift-count badge; user statistics backfill from legacy gifts once. A real exact0.10 SQLite database opens without reset, preserves identity choice and does not duplicate points on reopening. Earlier migrations remain green. |
| Preferences | Private per-viewer selections, unchanged-write idempotence, expectedRevision conflicts, account isolation, restart persistence, blocked/closed add/remove rules and25 saved rooms with tied timestamps/keyset pages. |
| Preference races | Slow list cannot undo a saved selection or resurrect an unfavorited filtered row; changing scope discards old results; double tap sends once; leave clears busy state; logout clears cache. |
| Rankings | Baghdad midnight/Monday/month/leap boundaries, actual gift timestamps, all/daily/weekly paths, blocked-user exclusion, member/session authorization for room ranking. Query defines deterministic sender-ID ties. |
| Identity races | Locked save keeps confirmed selection; conflict reloads state and handles offline refresh; late post-logout response cannot restore an account. Room data advances the level while old XP/style and another account's snapshot cannot regress it. |
| Entry effects | Genuine fresh attendance only, repeated join/reconnect and90-second cooldown suppression, client cannot inject an entry style through room messages. |
| Animation/UI | Initial history/duplicate snapshots do not replay; bounded queue, old events expire, background clears queue; reduced motion and disabled routes pause animation; overlay does not intercept mic input; compact Arabic studio/ranking/badges/favorites with enlarged text. |
| Flutter/API | Real loopback Node HTTP/SQLite create/join, private favorites/follows, gift-derived immediate user level, style unlock/save, daily room and weekly global ranking, fresh entry and restored client preferences/identity. Explicit fake SFU/audio adapters; existing call/room/durable-messaging contracts passed too. |

Four phone-sized Flutter screens were rendered and inspected: studio, daily
ranking, favorites and gift overlay. A local Arabic font was injected only for QA.
The test engine lacks phone emoji fallback, so captures check Arabic layout,
clipping and controls rather than native emoji rendering. Captures are not app assets.

## Behavior and device limits

User XP thresholds:0,50,200,500,1200,2500,5000,10000,20000,40000.
Room thresholds remain0,100,300,700,1500,3000,6000,10000,16000,25000.
The server validates unlocks. Favorite/follow does not grant membership or subscribe
to automatic calls/push. No real money, purchases, withdrawals or reward payouts.

Rankings return at most20 contributors; Asia/Baghdad day and Monday-based week.
Entry cooldown is90 seconds per user/room. Overlays last3 seconds, have at most4
waiting effects beside one active effect, ignore seen sequences and old history.
Initial snapshots seed the boundary; current listeners see fresh entry events.
Reduced motion uses a static announcement card.

This is source, not an APK or hosted deployment. No GitHub, Northflank, PostgreSQL,
R2, TURN, LiveKit or Firebase account was changed. PostgreSQL17 CI and APK steps
remain configured; neither ran remotely in this session. SQLite success is not a
substitute for the PostgreSQL CI run. No live SFU/RTP, phone/emulator, gallery,
native emoji/decoder, background FCM or Bluetooth route was exercised here.

Previous mobile-device acceptance has not been reported. After deploying API0.11.0
and building0.11.0+12, use IDENTITY_0.11_AR.md, MESSAGING_0.10_AR.md and
MOBILE_CALLS_AR.md on two phones. Actual frame rate, battery, foreground audio,
incoming calls and network handoffs need those checks. No load capacity or backup
restoration guarantee is claimed; administration/reports/monitoring/backups/load
checks are planned for0.12.

## Reproduce

```bash
cd server
npm ci --ignore-scripts --no-audit --no-fund
npm test
cd ..
bash tool/bootstrap_android.sh
python3 tool/configure_firebase.py
flutter pub get
flutter analyze
TOMI_CALL_INTEGRATION=1 TOMI_MESSAGING_INTEGRATION=1 TOMI_IDENTITY_INTEGRATION=1 flutter test --concurrency=1 --reporter expanded
python3 tool/check_mobile_policy.py
python3 tool/check_bootstrap.py
python3 tool/check_firebase.py
```

CI reruns npm test with a guarded localhost tomi_test TEST_DATABASE_URL. Never use
production as a test target. Deploy API before clients, reuse the database/keys,
and avoid mixed API versions while upgrading. Workflow/artifact:
TOMI0.11.0 Android / TOMI-0.11.0.apk. Rollout: START_HERE_AR.md.
