# TOMI 1.4 — run 40 dense integration-test timeout

Date: 2026-10-27. App remains 1.4.0-beta.1+21; API remains 1.4.0-beta.1.

## Observed failure

The user's run 40 log (`gg(1).txt`) executes the existing `tools/test_runner.mjs` and reports 173 tests: 172 passed, 0 failed and 1 cancelled. The search case at `test/messaging10.test.mjs:55:1` was cancelled after the inherited 60000 ms timeout (reported duration 63561.454053 ms). Total suite duration was 647731.441912 ms, within the existing 15-minute PostgreSQL step. The room-history case took 47933 ms in that run. No failed assertion is shown. Hosted slowness is visible; its underlying resource cause was not profiled or reproduced here.

## Change

Only `server/test/messaging10.test.mjs` changes among executable source files relative to canonical source 26 (`TOMI-1.4-ci-fix.zip`, SHA256 `3f80d3831f43bc022ff66a4d5b9fb7181a3d4a67be692059f66ae1d490a4c73f`).

- The search and room-history cases each receive an explicit 180000 ms budget. They still create 65 and 95 messages through real API requests.
- Search retains 64 unique matches, literal `%_` matching, access checks, receipt ownership and deletion checks. It now also requires exactly three pages and a decreasing cursor.
- Room history retains 95 unique messages, participant/session boundaries and post-close gift receipt checks. A ten-page safety cap and a decreasing cursor guard prevent unbounded paging.
- Diagnostic counters identify fixture and search-page progress in the completed test report.
- The default 60000 ms limit, serial process isolation, forced exit, complete-report gate and expected 173-test manifest are unchanged. No tests are skipped or removed.
- PostgreSQL's 15-minute step and API job's 40-minute budget are unchanged. All runtime API, client, schema, dependency locks, owner controls and workflow bytes match source 26.

## Executed checks

Both engine runs used the existing synchronous report preload, concurrency 1, default timeout 60000 ms and forced exit:

```sh
node --import=./test/sync_stdio.mjs --test --test-concurrency=1 \
  --test-timeout=60000 --test-force-exit --test-reporter=spec \
  test/messaging10.test.mjs test/runner13.test.mjs
```

| Check | Result | Duration |
| --- | --- | --- |
| SQLite: eight messaging cases and five runner guards | 13 passed, 0 failed/cancelled/skipped | 12467.028676 ms |
| Native PostgreSQL 17.10, `fsync=on`, isolated local `tomi_test` | 13 passed, 0 failed/cancelled/skipped | 16192.848187 ms |
| Node syntax check of the edited file | Passed | — |
| Test-specific timeout semantics, negative control | Explicit 500 ms case survives default 50 ms; ordinary case cancels at 50 ms as expected | — |

The timeout probe is deliberately an exit-1 negative control, outside the server test suite: one pass and one expected cancellation. Its failure is the evidence that the default bound still applies to ordinary cases. See `validation/1.4-run40/timeout-scope-probe.mjs` and its log.

Both integration runs completed all 65-message search setup, three search pages and 95-message room setup. PostgreSQL used its real local engine with fsync enabled; storage and room-provider services remained fixture doubles as in the existing integration tests. No real user database or external account was touched.

Closed logs and the PostgreSQL result summary are in `validation/1.4-run40/`. The previous source's full 173/173 runs on each engine, restore checks and client results remain historical evidence in `VALIDATION-1.4-CI-FIX.md`; they were not rerun or relabelled as current checks. No runtime, schema, workflow or client change requires a new full run for this scoped timeout patch. Hosted CI still executes the entire suite and enforces completeness before building APK.

## Delivery and limits

The full ZIP retains all 412 original file paths, adds this guide/report and current targeted evidence, and regenerates `SOURCE-FILES.sha256`. Packaging checks every file hash, ZIP CRCs, duplicate entries, baseline path retention and byte equality for every original file outside the edited test/documentation/manifest set. The checkpoint ZIP is byte-identical to the source ZIP. Local dependencies, test databases and downloaded PostgreSQL tooling are excluded.

The recommended GitHub change is a single replacement of `server/test/messaging10.test.mjs`, followed by a new commit and a fresh main/accounts/debug run. No remote commit, deployment, hosted workflow, APK build or phone acceptance was performed here. Existing Firebase build requirements remain enforced.
