# TOMI 1.4 — download delivery through Releases

Date: 2026-10-28, Baghdad. Baseline: canonical source 27, TOMI-1.4-ci40-fix.zip, SHA256 eed6791cbf502f6171cd14d96502a81a1346369296066207c130efa804852862, 419 files. App/API versions remain 1.4.0-beta.1+21 / 1.4.0-beta.1.

## Evidence and change

The user's screenshots show the API job passing and the APK output found, followed by CreateArtifact being denied for exhausted Artifact storage. The later debug log confirms HTTP403, code permission_denied and message insufficient usage to create artifact. This is the Artifact service's usage response; broadening Artifact permissions does not solve that quota.

The only changed executable/configuration source file is `.github/workflows/tomi-android.yml`. It replaces the Artifact upload step with repository Releases delivery. Root and API permissions remain contents:read. The Android job alone requests contents:write, as required to create Releases with the built-in GitHub token. No personal token, repository visibility, budget, account plan, external storage or backend setting is changed.

The delivery step selects only the expected APK; signed_beta also requires the AAB and existing signature evidence. Every selected build file must be regular, nonempty, non-symlink and below 2GiB. A SHA256SUMS.txt file accompanies the assets. It creates a unique per-run/attempt draft prerelease pinned to GITHUB_SHA, resolves the draft's numeric ID with gh release view, fetches its REST receipt by ID and validates tag, target, draft/prerelease state, exact asset names, sizes, upload state and server digests when present. Only then does it publish the prerelease, explicitly excluding it from Latest, and write its URL to the job summary. Resolving the draft avoids relying on the published-only REST by-tag endpoint. Failures remain failures and do not advertise a download. Older releases are not modified or removed.

## Executed verification

- **26/26 local delivery tests passed**, in 1.956 seconds. They execute the actual workflow Bash/Python body with a local gh double; no real Release is created. Coverage includes debug and signed_beta, hash evidence, ignoring unrelated files, missing/empty/symlink/oversized output, missing bundle or signing evidence, create/view/API/publish failures, invalid draft IDs, incomplete/duplicate assets, wrong size/digest/commit/tag, unfinished upload, state mismatches and an API response without optional digest fields.
- **8/8 existing Android disk safeguard tests passed**, in 0.007 seconds. Fixtures are disposable; the host is not cleaned.
- YAML parsed successfully with PyYAML; the extracted run body passed `bash -n`.
- Parsed comparison against source27 confirms the whole accounts-api job, inputs, root permissions, and every preceding test/build/signing/cleanup step remain identical. Only Android's scoped contents permission and the download-delivery step differ.
- Packaging validates the baseline's 419 paths, CRCs, every regenerated source hash, duplicate entries and byte equality for all original files outside workflow/documentation/manifest. The saved checkpoint is byte-identical to the source ZIP.

Reproduce the delivery checks with Python3 and PyYAML: `python3 validation/1.4-releases-fix/check_delivery.py`. This is a local regression harness; it does not run against GitHub or change the server test manifest. The output logs are retained beside it.

## Scope and limits

Production/client/schema/dependency/test-suite bytes match source27, including the two bounded 180-second messaging scenarios and every owner/admin feature. The full 173-test suite, database restore and Flutter build were not repeated locally for this delivery-only change. The screenshots already show the user's hosted build reaching upload; earlier complete checks remain historical evidence. This change retains the hosted workflow's full SQLite/PostgreSQL/completeness/restore/Flutter/signing gates.

No remote commit, Release publication, billing action, artifact deletion or hosted build was performed in this session. Real GitHub token/repository policy and upload acceptance remain for the user's fresh run after replacing the workflow. A passing mock does not prove live authentication. Existing Firebase requirements remain enforced; phone push delivery still needs physical-device acceptance and server FCM readiness.

## Official references

- https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases — Release asset limits and repository read access.
- https://cli.github.com/manual/gh_release_create — draft assets, exact commit target and prerelease options.
- https://cli.github.com/manual/gh_release_view — numeric draft ID lookup.
- https://cli.github.com/manual/gh_release_edit — publishing the verified draft.
- https://docs.github.com/en/rest/releases/releases — receipt fields and published-only by-tag semantics.
- https://docs.github.com/en/actions/tutorials/authenticate-with-github_token — built-in token and scoped permissions.
