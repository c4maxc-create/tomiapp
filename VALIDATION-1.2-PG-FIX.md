# TOMI 1.2 PostgreSQL assertion fix

24 October 2026. Base: source20 `TOMI-1.2-chats.zip`, SHA256
`6f693bd9f14bdbd02471bda327ab8cbcdd733f28aae552250531bbc38c118501`.
App/API versions and all production code remain unchanged.

## User-provided CI evidence

The three supplied screenshots show run32, commit0345dce, on main:
SQLite suite145/145 passed; PostgreSQL suite144 passed/1 failed at
`server/test/chat12.test.mjs:75`, actual string `'1'`, expected number `1`,
operator `strictEqual`. Android and the restore drill were skipped after the
failed prerequisite. Total duration13m9s; this was a test failure, not a timeout.

## Change

The existing group-history/revocation/owner-transfer case now compares
`Number(row.total)` with `1`. Node pg's default INT8 decoder returns COUNT values
as text; SQLite returns a number for this count. This follows the existing
cross-database assertions elsewhere in the repository. No production decoder
was changed, no test was disabled, and a count of0 or2 still fails.

The only changed executable file relative to source20 is
`server/test/chat12.test.mjs`. Every other source20 code, schema, native,
workflow, lock and configuration file is retained byte for byte. Documentation,
the checksum manifest and new verification logs are updated.

## Checks executed for this patch

- All7 cases in `test/chat12.test.mjs` passed against real SQLite after the fix.
- The installed `pg` INT8 type decoder produced the same string `'1'` shown in CI.
  The old assertion reproduced ERR_ASSERTION; the corrected strict assertion
  accepted both actual driver representations and rejected counts0/2.
- `node --check` passed for the changed test module.
- Archive CRC, every-file SHA256 manifest and source20 preservation were checked.

Evidence is in `validation/1.2-pg-fix/`. The full145-case SQLite result in run32
is observed from the supplied screenshots. The183 Flutter cases,8 HTTP contracts
and145 local Node cases recorded in `VALIDATION-1.2.md` belong to unchanged
source20 application code; they were not rerun or counted as new results here.

## Limits

A disposable PostgreSQL17 native runtime was obtained from the official PGDG
repository for reproduction. It could not be started under an unprivileged
user because this container maps only UID/GID0; chown to the test user failed.
Consequently no fresh native PostgreSQL suite, restore drill or APK build is
claimed locally. The direct check uses the real installed pg decoder, not a
replacement decoder. A new GitHub run from the corrected commit must complete
PostgreSQL, restore and Android build before phone acceptance.

No GitHub commit/push, hosted deployment, real-user message or key/database
change was performed. `PG_FIX_1.2_AR.md` gives the exact manual upload steps.
