# TOMI 0.2 — accounts, profiles and people search

Flutter Arabic RTL app plus a Node 24 accounts API. The established dark design,
five tabs and the small-screen fixes from 0.1 are retained.

This package contains **source code**. It does not contain a compiled 0.2 APK or
a deployed server. Follow [START_HERE_AR.md](START_HERE_AR.md) using a browser.

## Implemented accounts milestone

- Username/password registration, login, logout and secure session restoration.
- Unique, case-insensitive usernames (3–20 ASCII letters, digits or underscore).
- Passphrases of 15–128 Unicode code points; no email or phone requirement.
- Single-use recovery code, with a replacement after recovery/password changes.
- Persisted display name, username, bio and a selectable built-in avatar.
- Authenticated people search, public profiles, follow/unfollow and real counts.
- Immutable user IDs, server-side validation and per-user access enforcement.
- PostgreSQL persistence, salted scrypt password hashes, hashed session tokens,
  bounded hashing concurrency and database-backed request limits.
- Password changes/recovery revoke prior sessions on every device.

Media uploads (including custom profile photos), messaging between accounts,
posts/stories, live calls/rooms, multiplayer, XP, charisma, coins and payments are
later milestones. Existing sample interactions remain explicitly marked as
previews and do not affect stored account counts or real balances.

## Hosting and APK build

1. Upload the complete contents of this package to the existing GitHub project.
2. Create a persistent PostgreSQL database, e.g. a Neon Free project.
3. Deploy `server/` as a Node Web Service on Render. `render.yaml` also provides
   an optional Blueprint. Supply the database connection in server environment
   variable `DATABASE_URL`; never add it to Flutter, GitHub variables or source.
4. Set the **public HTTPS app server URL** in GitHub variable `TOMI_API_URL`.
5. Run **TOMI 0.2 Android**, mode **accounts**, on **main**.

GitHub first tests the backend with SQLite and an isolated PostgreSQL 17 service.
It then bootstraps Android, installs dependencies, runs `flutter analyze` and
all Flutter tests, and compiles **TOMI-0.2.0.apk** only if the checks pass.
The default mode **preview** builds the design without a live server; it cannot create real
accounts. Accounts builds refuse missing, non-HTTPS or credential-bearing URLs.

This repaired package scrolls the compact recovery screen before looking for
its code, checks successful registration/session persistence before checking the
screen, and keeps the recovery acknowledgement and five-tab checks enabled.
The workflow prints its checked-out source revision to make future runs traceable.

The APK is a debug test build. App-store release signing is not configured.
The scaffold helper enables Internet access, disables cleartext connections and
Android backup, and uses at least the SDK level required by secure storage.

## Server

Required hosted environment:

```text
NODE_ENV=production
NODE_VERSION=24
DATABASE_URL=<PostgreSQL connection string>
TRUST_PROXY=1
```

`TRUST_PROXY=1` is for the trusted Render reverse proxy. Disable it when serving
direct HTTP traffic. Native apps do not need CORS; web clients require an explicit
comma-separated HTTPS `CORS_ORIGINS` allowlist. The server binds Render's `PORT`.
Hosted mode refuses an ephemeral SQLite fallback. Schema creation is additive
and uses `tomi_` table names. Health check: `GET /health`.

Local server development/test (Node 24):

```sh
cd server
npm ci --ignore-scripts
npm test
```

For a local API process, explicitly set `TOMI_SQLITE_FILE` to a writable file.
Local integration tests use temporary files and loopback HTTP. The separate CI
PostgreSQL run accepts only a local database named `tomi_test`.

## Validation at delivery

- Six backend integration tests passed locally, covering persistence after
  restart, second-device login, authorization, uniqueness, follows, recovery,
  revocation, expiry, body limits and persisted request limits.
- A PostgreSQL WASM engine independently passed the schema/SQL and account-flow
  smoke check; this does not validate the live `pg` TCP/TLS connection adapter.
- Android scaffold/source-preservation and branding/network settings passed.
- New Dart files received a structural grammar/import/icon review. This is not
  Dart analysis or Flutter compilation.
- Flutter tests/analyze, the full PostgreSQL service test and APK compilation
  still require the included GitHub workflow. Local Flutter execution was blocked
  by automatic approval review because its setup attempted a metadata endpoint.
- The latest user-supplied GitHub run passed Dart analysis and 21 of 22 Flutter
  tests using the older registration test. The corrected registration test and
  updated workflow still need a fresh GitHub run; this ZIP contains source only.
- No hosted database, server deployment or cross-phone acceptance test has been
  completed in this authoring session.

References: [Flutter architecture](https://docs.flutter.dev/app-architecture/guide),
[secure storage](https://pub.dev/packages/flutter_secure_storage),
[OWASP password storage](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html),
[Render Free](https://render.com/docs/free), [Neon plans](https://neon.com/pricing).
