# TOMI 0.4 validation

Baseline: TOMI-0.3-posts-r2.zip. Tools: Node 24.19.0, Flutter 3.47.7,
Dart 3.13.5. These results apply to the final source archive.

## Passed

- Backend integration: all 25 tests passed, including the 14 existing account
  and social tests and 11 chat/storage/migration tests. Covered persistence
  across restart, concurrent pair creation, stable nonce retries, cross-recipient
  nonce conflicts, sequence pagination, participant permissions, bounded and
  monotonic reads, blocking, authenticated WebSocket isolation, typing rejection,
  logout socket closure, tombstone deletion and cleanup.
- A SQLite database created with the exact 0.3 schema snapshot upgraded while
  retaining an existing account, session and post.
- Image tests use a fake object store with the actual signing/verification code.
  Covered sender/thread/feature scoping, checksums and signatures, five-minute
  chat GET URLs, private bucket configuration and separate feed/chat cleanup.
- Flutter tests: all 43 passed, including the 29 existing account, preview and
  social tests and 14 new chat tests. Covered lost replies, stable image retries,
  visibility-based reads, concurrent unseen arrival, stale deletion/block data,
  logout response races and paging to the oldest of 600 messages with a bounded
  500-message client cache.
- Chat widget tests passed with a visible keyboard on a compact screen, failed
  send/retry controls, deletion, long history with enlarged text, and an attached
  photo plus multiline text in landscape with the keyboard visible.
- Flutter/Dart analysis: no issues.
- PostgreSQL WASM engine smoke passed: additive schema, accounts, private chat,
  nonce replay, unread/read markers, blocking and deletion.
- Android bootstrap checks passed: source preservation, workflow YAML,
  generated-template test removal, launcher label and vector icon.
- Build configuration accepted accounts/preview and rejected database URLs,
  insecure HTTP URLs and URLs containing credentials.

## Environment-dependent checks

The PostgreSQL smoke uses a PostgreSQL engine but does not test pg TCP/TLS or
multiple independent database connections. GitHub Actions runs the full backend
suite against PostgreSQL 17 before compiling the APK. That remote workflow has
not been run from this workspace.

No live Northflank deployment, real R2 bucket, credentials or hosted database
was modified. Physical Android gallery/process recreation, real R2 policies,
hosted WebSocket proxy behavior and APK installation need their own environment.

Realtime fanout is local to one API instance. Multi-replica event distribution,
push notifications, end-to-end encryption, store signing and production load
capacity are outside this version's validation.

This archive contains source and instructions, with no compiled APK.
