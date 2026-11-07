# Build43 Google login — verified APK and public certificate

- Successful native compile: https://github.com/ToLo10/tomiapp/actions/runs/42419105981
- APK artifact: https://github.com/ToLo10/tomiapp/actions/runs/42419105981/artifacts/13592624589
- Artifact name: `TOMI-build43-native-debug`.
- Verified APK package: `com.tomi.tomi_app`.
- Post-build Google check: packaged web OAuth client present, updated Firebase client present, and exact match — all true.
- Focused local account/login tests8/8 and Flutter analyze pass. A real Google login still requires the owner to register this certificate and test on-device.

## Certificate SHA-1

```text
98:7A:0F:12:75:4D:A2:AC:8F:B0:F1:C6:6A:CB:16:AA:37:FB:E8:F6
```

## Certificate SHA-256

```text
4B:0B:2C:97:55:D2:1E:21:2E:E8:7A:59:87:27:34:C3:19:B4:B1:E1:37:C9:D2:6A:B8:C3:0C:C2:9B:94:73:0B
```

Add both under Firebase `tomi-218ba` → Android `com.tomi.tomi_app` → Add fingerprint. These are public certificate digests, not an APK file checksum or private key.

The certificate differs from Build42, so ordinary Android cannot install this APK over Build42. The owner confirmed no local drafts or encrypted history to preserve. Confirm existing TOMI credentials are available before removing the old *application*; do not delete the server account. Install Build43 and sign in with the existing TOMI username/password, then link Google from Settings → devices/security → login methods. Signing into Google directly before linking can create a separate TOMI account.

This is a debug testing certificate, not a persistent production signing setup. Keep the fixed-release-key instructions in `ops/IDENTITY-LOGIN-AR.md` for future durable updates.
