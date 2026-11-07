# Build 40 — comment threads and security

Comment replies now expand beneath their root comment, with reply counts, collapse, paginated replies and an @target for replies to another reply. Sending focuses the composer; cancelling clears the target. Deleting a comment with descendants asks for confirmation and removes its subtree. Legacy servers retain a limited flat-page grouping fallback; deploy the updated API for full thread pagination.

## Security changes

- Fixed follower-only story authorization for direct story IDs, author lists and view receipts. Nonfollowers receive no private story. This does not change the explicitly requested public-profile behavior of follower posts.
- Reject dangerous JSON object keys, excessive nesting, malformed UTF-8, false JSON MIME types, unsupported compression and oversized declared bodies. Limit header count. Add API anti-framing, HTTPS HSTS and permissions headers.
- Bound unauthenticated WebSocket slots and handshake attempts before database authentication; share validated client-IP handling with HTTP. Forwarded addresses are trusted only when configured behind a trusted proxy.
- Add a tracked-source credential-pattern check and high/critical production npm advisory gate to Android CI. Preserve and enforce the Flutter lockfile during platform bootstrap. These checks do not cover all credential formats, repository history or unknown vulnerabilities.
- SQLite queries now detect returned columns, allowing recursive SELECT queries to return rows correctly. Thread queries also run against PostgreSQL.

## Validation

See validation/security-threads40. Flutter: 325 passed, 11 optional integration skips; analyzer clean. Targeted SQLite and PostgreSQL: 8 passed each. npm production audit: zero known advisories at scan time. .NET transitive package audit reported no vulnerable packages. Bootstrap preservation and iOS configuration checks passed. Full backend: 303/303 passed, no skips or failures.

## Deployment and limits

Push source to main and build Android 40. Render requires Manual Deploy of the latest commit before server changes take effect; no production deployment was performed here. Physical-device behavior and infrastructure penetration testing are not covered. No claim of immunity to unknown attacks. Remaining older feature requests remain tracked in 0028.
