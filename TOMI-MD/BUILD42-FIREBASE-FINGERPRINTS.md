# Firebase fingerprints — existing Build42 debug APK

These public certificate fingerprints were extracted with Android apksigner after verifying the existing APK signature. No private signing key was accessed, generated or changed.

- Source APK: native compile run `42388082612`, artifact `TOMI-build42-native-debug` (`13580284951`).
- Verified certificate report: https://github.com/ToLo10/tomiapp/actions/runs/42415535630
- Firebase project: `tomi-218ba`; Android package: `com.tomi.tomi_app`.

## SHA-1

```text
CA:71:8C:A1:BB:0B:76:0E:BF:D9:89:B3:AC:4A:96:65:4A:10:A6:04
```

## SHA-256

```text
2F:0D:67:C3:8F:0E:42:D6:68:62:C2:8A:64:21:37:CD:64:97:42:A7:62:E5:BE:37:D8:43:6C:8C:7A:72:8F:9C
```

Add each through Firebase Project settings → General → this Android app → Add fingerprint. Then download the updated client `google-services.json`. This registers the certificate of this exact debug APK; it does not activate providers on Render or update client OAuth configuration automatically. New debug builds can have a different certificate; use a persistent release signing key for durable production Google login, as explained in `ops/IDENTITY-LOGIN-AR.md`.
