# TOMI security activation and incident runbook

These are deployable components, not a claim that the production accounts have been configured. Run only on infrastructure you own. Do not paste keys into chat, source files or issue comments.

## 1. Authenticator and administrator protection

Set a new independent `TOMI_MFA_KEY` (32 random bytes, standard base64) in the server secret store. Generate locally with `node -e "process.stdout.write(require('crypto').randomBytes(32).toString('base64'))"`. Save it in a separate protected recovery vault: losing it prevents authenticator verification. Never use a public Firebase configuration or the backup key as this key.

Deploy the server and app. On every administrator account: Settings → Devices and account security → Two-step verification; enter the current password, add the displayed secret to an authenticator, confirm a code and store the ten one-time recovery codes offline. The secret is encrypted at rest with AES-256-GCM and user-bound associated data. Codes are SHA-256 hashed; accepted TOTP steps cannot be replayed. Setup expires in 10 minutes. Login and account recovery require MFA when enabled. Changing a password, revoking devices and deleting the account require recent verification; administrator API access expires 15 minutes after verification. Verify again on the security page. Existing non-MFA accounts continue to work during rollout.

After all staff have enrolled, set `TOMI_REQUIRE_ADMIN_MFA=1`. Do not enable it without a valid server key. Browser administration supports an authenticator/recovery code at login. Current accounts and messages are preserved. The app's regular account-recovery code does not bypass MFA. Keep MFA recovery codes separately.

For master-key rotation: stop every API worker, make and verify an encrypted backup, provide `TOMI_MFA_OLD_KEY`, `TOMI_MFA_NEW_KEY` and `DATABASE_URL` only through the protected process environment, then run `node server/tools/rotate_mfa_key.mjs --apply-offline`. It re-encrypts all secrets in a transaction and prints no secret. Replace the server's `TOMI_MFA_KEY` with the new key before restarting. Do not restart mixed-key workers. Restore both database and matching vault key if rolling back. This tool does not rotate Firebase or storage credentials.

## 2. WAF and origin isolation

Use a domain you own with Cloudflare proxying. Copy `ops/cloudflare/wrangler.toml.example` to an untracked local configuration; fill the route, zone and public hostname. Generate a separate 32-byte base64url `TOMI_EDGE_SECRET`, store it in Worker Secrets and the Render secret environment. `TOMI_ORIGIN` is the HTTPS Render origin; it must differ from the public hostname.

Deploy `worker.mjs`, test HTTP and WebSocket upgrades through the public domain, then enable the same origin secret on the API and change `TOMI_API_URL` in app builds to the public domain. The Worker overwrites client-supplied proxy headers, adds an authenticated client-IP header and injects the secret; HTTP and WebSocket origin bypass are denied. `/` and `/health` remain public read-only health checks. No other endpoint bypasses the secret. Do not embed this secret in the mobile app. Enable `TRUST_PROXY=1` only when the entire forwarding chain is controlled and tested.

Enable Cloudflare managed WAF rules where supported by your plan, the OWASP managed ruleset where available, DDoS protection and targeted rate limits on authentication. Start rule tuning with logging; avoid JavaScript/browser challenges on native API and WebSocket routes. Do not cache authenticated API, private media URLs, `/admin` or mutation responses. Managed features vary by account plan. Confirm a direct origin request to `/v1/me` is403 and a proxied unauthenticated request is401. Test authorized requests with your own test account. No live WAF was deployed from this workspace.

## 3. Media and malware

Images/audio/video retain their size, checksum, metadata/container checks. Documents now validate container signatures and text encoding and reject renamed executables. Private attachments use an isolated nonpublic bucket and five-minute signed read URLs with participant checks. Never enable a public domain on the private bucket.

Install a supported ClamAV executable and current signature database, enable the signature updater (`freshclam`) under a restricted service identity, and set `TOMI_CLAMSCAN_BINARY` to its absolute executable path. Every image/audio/video/document is scanned before attaching. Detected malware is rejected; scanner errors/timeouts fail closed. Scans run without shell execution or inherited API credentials, with private temporary files and bounded size, archive depth and timeout. Encrypted or over-limit archives are rejected when detected by ClamAV. Ensure the service identity can read signatures and write its private temporary directory. Monitor signature freshness, disk space, updates and rejected uploads. No active scanner is claimed when this setting is absent. Codec parsing should run on patched, isolated media workers; antivirus cannot guarantee safety against every new exploit.

## 4. Backups and restore drills

Existing `server/tools/backup.mjs` provides authenticated AES-256-GCM backups, non-overwriting output and a restore check restricted to an empty local `tomi_restore_check` database. CI runs an actual PostgreSQL dump/restore drill, not only a decryption test.

On a dedicated scheduler host, install Node24 and a PostgreSQL client compatible with your database. Create a restricted `tomi-backup` identity, `/var/lib/tomi-backups` mode0700 and `/etc/tomi/backup.env` mode0600 readable only by that identity. Put `TOMI_BACKUP_DATABASE_URL` (read-only dump role), a separate random `TOMI_BACKUP_KEY`, and `TOMI_BACKUP_DIRECTORY=/var/lib/tomi-backups` there. Install the supplied systemd service/timer and adjust `/opt/tomiapp` and Node paths. `scheduled_backup.mjs` encrypts a fresh dump and authenticates it after creation. A local schedule is not offsite disaster recovery: copy encrypted outputs and manifests to a separate restricted immutable storage account, monitor missed jobs and test restore monthly on an empty isolated database. Choose retention based on the published policy; this script does not silently delete backups or store encryption keys beside them. Production schedule/offsite access require your hosting setup.

## 5. Monitoring and response

The dashboard shows counts of401/403/429 and malformed requests for the last hour in this API process; thresholds display a warning. Per-account security events show logins, MFA changes, recovery and password changes, without message content, passwords, raw tokens or IP addresses. Event retention is90days. This is not a multi-server SIEM or offsite paging service. Connect your hosting metrics/log platform for durable external alerts; no email/chat service was authorized or configured here.

If a credential is exposed: revoke it at the issuer, generate a new least-privilege credential, update the server secret store, deploy/restart and verify the service. In particular, revoke the previously exposed Firebase service-account private key in Google Cloud IAM → Service Accounts → Keys. A new key alone does not revoke the old one. Preserve minimal incident evidence, end affected user sessions, rotate affected secrets and test recovery before reopening. Avoid copying private payloads into logs.

## 6. Dependency and authorization verification

Scheduled/PR security checks audit production npm and transitive .NET packages; Dependabot proposes npm, pub, NuGet and GitHub Actions updates. Review updates before merging. Existing tests cover cross-account message/file access, room roles, administration, gift replay/concurrency and revoked sessions. Wallet balances are nonnegative database values; clients cannot set gift prices or credit results. Keep trial currency separate from future payments. No real payment provider is activated by this security change.

Run `node server/tools/security_readiness.mjs` in the protected server environment to check required configuration presence without printing values. A successful configuration check is not proof of an active provider or successful disaster recovery. Arrange an independent penetration test on a staging environment with test accounts before wider release; no external auditor was commissioned here.

## 7. End-to-end encryption: pending implementation and review

Current chats are **not** end-to-end encrypted. HTTPS, private signed media URLs, secure device storage, and encrypted backups are separate protections. Do not advertise them as E2EE. This change intentionally does not replace current messages with a homegrown cipher or silently destroy history.

A production E2EE rollout must use a maintained audited messaging protocol/library (e.g. Signal protocol or MLS with supported native clients), device identity keys held only on-device, authenticated device enrollment, key-change warnings/safety verification, prekeys/ratchets and replay protection, encrypted attachments, user-held encrypted history recovery, device revocation and mixed-version migration. Notification previews, server search/moderation and exports must explicitly honor the encrypted boundary. Test Android/iOS multi-device, reinstall, lost-key recovery, offline/out-of-order delivery and deletion before enabling. This remains an outstanding requested feature; no encrypted chat mode is shipped in build41.
