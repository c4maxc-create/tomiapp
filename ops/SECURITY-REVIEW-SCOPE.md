# Independent security review handoff — build42

This file scopes a future independent review. It is not an assessment report, certification, or evidence that a third party reviewed TOMI.

## Data boundaries

- Firebase proof → `server/src/firebase_identity.mjs`: pinned Google certificate origin, RS256, exact issuer/project audience, recent authentication, provider allowlist. No provider access token accepted directly by TOMI.
- Firebase subject → `server/src/federated_auth.mjs`: project+subject identity, explicit credential-confirmed linking, no email merge; retain TOMI MFA, restrictions and session lifecycle.
- TOMI session → encrypted device: password or recent linked provider proof, step-up if required, signed challenge, immutable public keys, per-session binding and device limits.
- Encrypted direct message → authenticated thread: prekey claims, signed packets, exact retry, roster pinning, no plaintext fallback. Rust `vodozemac` handles Olm; first-party FFI, persistence and metadata binding require review.
- Device secrets → local OS key storage and encrypted atomic state. Backup contains cached history, not reusable identity/ratchet snapshots. Restoration is an explicit user action.
- Attachment → private opaque R2 object, size/hash/prefix checks, encrypted file key only inside the message; server antivirus cannot inspect E2EE plaintext.
- Public Worker → origin secret: workers.dev proxy and rate bindings; not full zone managed WAF. Keep origin open until the migrated client is verified.

## Priority review scenarios

1. Wrong issuer/audience/kid, algorithm confusion, certificate rotation and unavailable key endpoint; provider login cancellation and interrupted account linking.
2. Same-email different subjects, simultaneous linking from different TOMI accounts, provider unlink/revocation outside TOMI and TOMI account erasure/recreation.
3. Existing MFA on both local-password and provider-only accounts; recovery codes and reauthentication freshness; suspension and stale-session operations.
4. Prekey exhaustion, concurrent claims, replay, out-of-order/duplicate packets, tampered box/context, roster additions/revocations and a malicious server substituting first-use keys.
5. Crash at each local fsync/network/ACK boundary; backup imported onto a new device without rolling back ratchets; lost OS vault key and full local storage.
6. Cross-thread object access, replaced ciphertext, upload expiration, resource budgets, deletion and interrupted streaming.
7. Actual Android/iPhone lifecycle, keyboard/accessibility, OS backup policy, native FFI/allocator behavior, 16KB Android pages and iOS export compliance.

## Reproducible local checks

Use only disposable development databases/accounts. Never point test fixtures at production.

```sh
npm --prefix server ci --ignore-scripts
npm --prefix server test
node --test --test-concurrency=1 server/test/federated42.test.mjs server/test/e2ee42.test.mjs server/test/security41.test.mjs
python3 tool/check_identity_native.py
python3 tool/check_source_secrets.py
cargo +1.89.0 test --locked --manifest-path packages/tomi_secure/native/Cargo.toml
cargo audit --file packages/tomi_secure/native/Cargo.lock --deny warnings
python3 tool/build_secure_native.py --platform host
flutter analyze
flutter test
```

The native Flutter test uses real Olm over a loopback API and a test-injected vault location. It does not emulate the security guarantees of Android Keystore or iOS Keychain. JWT unit tests use generated RSA keys and a synthetic certificate endpoint; real provider/device acceptance must be run separately after owner configuration.

## Outside this session

A separate reviewer, written authorization for a defined staging endpoint, findings with reproducible evidence, remediation and retest are still required. This session has no Firebase IAM, Meta, Apple or Cloudflare account authority. Firebase Admin key rotation, provider activation, Worker deployment and production service health have not been verified from this workspace.
