# TOMI0.12 source completion and continuation notes

2026-10-17 Asia/Baghdad. Built on exact final0.11 SHA256
6f6a11bb3acf1d259a4c63cc607002d836de5f8653e2225d497aa29c4037e763.
No AGENTS found. User authorized0.12 and continued; do not spawn agents.

## Implemented

- Private account/post/room reports and reporter tracking; immutable minimal
  evidence, independent private/public notes, stable request receipts and status revisions.
- Explicit server owner UUID / live DB moderators independent from room roles.
  Owner-only account suspension/restoration and staff grants, protected targets,
  hidden/restored posts, closed rooms and durable audit/action receipts.
- Suspension revokes sessions and push devices, ends calls, removes presence and
  closes owned rooms with durable SFU jobs. Fresh transaction/session checks stop
  a late call request authenticated before a ban. Recovery does not bypass bans.
- Flutter report entry points, own reports, admin review/users/rooms/staff/audit/
  metrics, confirmation reasons, frozen uncertain retries, session/list/detail/
  access epochs. A late privileged response cannot refill a revoked view.
- Bounded per-instance metrics and DB/media estimates. AES256GCM database backup,
  private passfile/TLS, no-clobber authenticated files, empty-local-only restore,
  CI PostgreSQL17 restoration drill and bounded loopback read-load tool.
- Versions, guides, CI and source preservation updated to0.12.0+13.

## Actual validation and pending gates

116 Node tests pass; all15 moderation tests also pass on a final targeted rerun.
11 JVM policy cases and configuration/bootstrap checks pass.8 native Java files
match0.11. New moderation Dart folder analyzes cleanly; whole-lib offline97
missing-dependency diagnostics equal the baseline. Full Flutter/146 intended
cases and APK cannot run with the evicted partial dependency cache.9 new cases
and all5 HTTP contracts are prepared for CI; do not describe them as passed.
Encrypted real SQLite restoration and60 isolated HTTP reads pass. Actual PostgreSQL
restore, R2 object/secret restoration, SFU/RTP and device acceptance remain pending.
No production service, keys, repository or real data was changed. No APK exists here.

## Continue from this source

TOMI-PROGRESS.md is the newest checkpoint/identity authority. Final source is
TOMI-0.12-moderation.zip. The standalone log is saved again after the final ZIP
hash/identity are known; do not mutate that finalized ZIP to embed its own hash.
Do not repeat migrations manually, recreate services/keys or reset the project.

Current user steps: same GitHub source, API0.12.0, Actions with PostgreSQL/restore/
Flutter checks, APK0.12.0+13, copy own UUID/set TOMI_OWNER_USER_ID, device acceptance.
Resolve any failed CI/device gate before wider release. Then1.0 beta work covers
account deletion/privacy/terms, signed release and a small test cohort. No real
payments or public launch is included in0.12.

Save each meaningful part or5–10min; saving does not run work while disconnected.
Never include API credentials, backup keys/archives, SDKs, caches or node_modules.
