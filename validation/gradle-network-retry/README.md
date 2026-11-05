Gradle artifact network failure handling

Reported run: 41998242149. Screenshot shows HTTP 504 fetching kotlin-compiler-embeddable-2.2.21.jar after all test steps passed.

Validation: six retry-classification/process-status tests, eight Android CI safeguards, and scaffold/bootstrap checks passed. Official Maven artifact successfully downloaded: 56,908,512 bytes, SHA-1 b13aed5cf8412f9ee9d1e4db21bdcfebcc24f606 matches the official .sha1. The download was tested from this workspace, not the failed GitHub runner.

Retry policy: three total attempts, waits 30/60 seconds, only transient HTTP/download failures. Deterministic compilation, credential and missing-artifact failures remain errors. Workflow caches Gradle modules and wrapper downloads, not app build products/signing material. No Kotlin version/repository substitution and no disabled checks. Android APK compilation remains unverified locally because Android SDK is unavailable.
