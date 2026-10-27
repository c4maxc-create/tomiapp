# TOMI 1.4 — executed validation and delivery scope

26October2026. App **1.4.0-beta.1+21**, API **1.4.0-beta.1**, extending canonical source24/TOMI-1.3.2-notifications-rooms-fix.zip (350paths, SHA256f2958b01e8e665073eeda348af3912c7e74c2eb3f3a5236c7da15892335b3e5e).

## Executed successfully

| Check | Result |
|---|---|
| Flutter3.47.7 / Dart3.13.5 analyzer | No issues |
| Full ordinary Flutter suite |202passed,8HTTP cases skipped by design |
| Final owner target / Arabic visual run |8/8passed;7overlap the full suite and1additional compact case, therefore203distinct ordinary cases |
| All explicitly enabled Flutter↔Node HTTP contracts |8/8passed, including extended owner/admin contract |
| Node24.22.1 / SQLite full suite |170/170passed, zero failure/cancellation/skip;1128.917s in this executor |
| Native PostgreSQL17.10 admin/moderation target |23/23passed (15existing moderation+8new owner cases), zero failure/cancellation/skip;169.673s |
| Encrypted PostgreSQL backup / authenticated restore |Passed with pg_dump/pg_restore17.11, including1.4staff permissions and special-profile revision |
| Firebase client configuration |Required/optional guard, persistent path, repeat configuration and private-key rejection passed |
| Android CI safeguards |8/8passed |
| Release key/readiness tools |6/6passed with disposable fixture key |
| Native notification policy |17scenarios passed |
| Accounts build configuration |Passed for the existing HTTPS app endpoint |
| Official GitHub workflow parser0.3.61 |Parse and template conversion:0errors |

Commands use`CI=true FLUTTER_SUPPRESS_ANALYTICS=true`. The ordinary command was`flutter test --no-pub --reporter expanded`; HTTP files ran with their existing explicit integration flags, and the final owner run used`TOMI_VISUAL_QA=1`. This report counts overlapping targeted tests once. No additional dependency was introduced; all144Flutter lock entries remain identical to source24.

## Coverage relevant to this change

- Owner-only coin and received-charisma adjustments, bounded exact integer arithmetic, insufficient-balance rollback, stale revisions, before/after audit, concurrent identical requests, request reuse after restart and different-payload rejection.
- Manual charisma adjustments preserve historical room gifts/support totals and sender XP; later self gifts accumulate on the adjusted account value.
- Independent report/account/ban/post/room/metrics/audit scopes, old moderators retaining their prior scopes without an automatic ban grant, live permission changes/revocation, protected owner/staff and rejected financial/role escalation.
- Special public badge persists/revokes without granting staff rights. Managed-account creation leaves the owner session intact; passwords and one-time recovery values never enter audit/receipts/device drafts. Retry never changes an existing password or repeats a recovery code.
- Posts-only moderation works without report access. Account erasure deletes special status and delegated scopes and rejects resurrection attempts.
- Accepted financial intent survives client-controller restart and reuses its nonce. Failed local intent storage prevents server mutation. New-account passwords remain memory-only.
- Arabic account tools, finance form, explicit permission dialog and restricted moderator page were reviewed at390×844; creation and finance controls at320×740 with text scale2 remain reachable by scrolling. Six reviewed screenshots are included. The newly exercised report-detail route exposed an existing notify-during-build error, fixed by scheduling its load after the first frame. Early visual fixture failures concerned lazy-list scrolling/animation timing; corrected tests passed without reducing assertions.

The PostgreSQL target executed the real server and real Node`pg`driver, and the restore drill checks original credentials/reports/erasure/moderation/identity,1.3support/batch receipts/wallet/charisma/cosmetics/room policy, and1.4permissions/special revision after reopening the restored database. The executor maps onlyUID0, so an isolated test-only first-geteuid interposer permitted the upstream root startup check; normal subsequent ownership checks and SQL were unchanged. Loopback TCP was used because Unix sockets are unavailable. The backup tool's restricted child environment was preserved; local client wrappers supplied only the downloaded client-library path. No production file was modified for either runtime adjustment. Runtime binaries, wrappers, database and interposer are excluded from the ZIP.

The first local restore attempt could not load the separately downloaded client's shared library through the backup tool's deliberately restricted environment. Test-only client wrappers fixed that runtime setup, and the final encrypted restore passed. The existing negative metrics fixture deliberately logs one generic`Request failed: Error`; both SQLite and PostgreSQL suites still finish with zero failures.

## Source and package preservation

All350prior source paths are retained. The old schema is an unchanged prefix plus`tomi_staff_permissions`and`tomi_admin_profiles`. Prior PostgreSQL migration/locking implementation files are byte-identical to source24. Root docs, version labels and matching workflow artifact names are updated; existing FCM/LiveKit/Firebase guards remain. `SOURCE-FILES.sha256`covers every other ZIP entry. Packaging checks CRC, all hashes, duplicate paths, preserved paths and exclusion of generated builds/caches/private configuration/keys/databases. `source-preservation.json`lists changed and added paths.

## Still requires the user's deployment environment

This is a full source release, not a built APK. The hosted workflow retains all170PostgreSQL tests and the extended encrypted restore drill before Android build; only the23admin/moderation PostgreSQL cases and restore were rerun locally in this iteration. Historical full PostgreSQL results in older folders retain their original scope.

No live server/repository/account setting was changed. The user's account UUID still must be assigned to`TOMI_OWNER_USER_ID`on the existing server. Actual Firebase Android config/FCM/LiveKit completion, hosted Actions, APK/AAB creation, signing/distribution and phone acceptance are not claimed. See **OWNER_ADMIN_1.4_AR.md** for activation and **FIX_NOTIFICATIONS_ROOMS_1.3.2_AR.md** for the outstanding service configuration.

Passed logs, machine-readable results and screenshots are in`validation/1.4-owner-admin`. Older validation folders remain historical evidence.
