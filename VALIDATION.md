# TOMI 0.3 validation

Source baseline: user-provided TOMI-0.2-fixed.zip.
Local tools: Node 24.19.0, Flutter 3.47.7, Dart 3.13.5.

## Passed

- Node backend integration: 14 tests passed.
  Includes the six existing account tests plus persisted posts/counts, retries and
  concurrent publication, unique likes, comments, ownership, pagination with equal
  timestamps, validation, verified image publication, rejected uploads and cleanup.
- Signature V4 matches the exact AWS published GET presigning test vector.
- Flutter tests: all 29 passed.
  Includes existing account/preview tests plus real post retry, scope races,
  likes/comments, direct upload without Bearer leakage, enlarged text and
  comment errors with keyboard in portrait and landscape layouts.
- Flutter analyze: no issues.
- PostgreSQL WASM smoke: additive schema and complete account → follow → post →
  like → comment → deletion flow passed against a PostgreSQL engine.
- Android bootstrap/source preservation and build configuration checks passed.

## Environment-dependent checks

The local PostgreSQL WASM smoke does not test pg TCP/TLS connectivity. The
included GitHub workflow runs the complete backend tests against PostgreSQL 17
before compiling the APK. No new hosted service, database or real R2 bucket was
modified or configured in this session. Real-phone gallery access, real R2
credentials and the final APK build still require deployment/build environments.

The archive is source code and setup instructions; it contains no compiled APK.
