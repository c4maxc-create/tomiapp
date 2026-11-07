# Build43 — Google login configuration repair

The read-only inspection run42418845100 verified that the installed Build42 APK has **no `default_web_client_id` resource**, while the owner's updated `TOMI_GOOGLE_SERVICES_JSON` contains a valid web OAuth client. This explains the immediate SDK failure before the Google account chooser. Updating the GitHub secret cannot modify an already installed APK.

Build43 packages the updated client JSON. Native compile now fails before compilation if a web OAuth client is absent, and after compilation if the packaged client resource is missing or differs from the configured client. Both checks distinguish Android OAuth clients (`client_type=1`) from the web client required by the SDK (`client_type=3`). Public reports contain presence/match flags and certificate hashes only; Firebase client JSON and credentials are not printed.

Google SDK failures now distinguish a missing client configuration, certificate/provider configuration, cancellation and interruption. SDK descriptions/details are not exposed to the user. Focused account/login UI tests8/8 and Flutter analyze pass. The Firebase configuration check also verifies the rejection of messaging-only JSON when Google login is required.

The new debug APK has its own certificate. Register its SHA-1 and SHA-256 from the build report; the old Build42 certificate does not authorize another signing key. A different certificate also prevents an in-place Android update. Do not remove the installed app without preserving any local drafts and exporting encrypted history the user needs. Server account credentials must remain available. For durable future updates use the owner's fixed signing key, not a newly generated debug key on each runner. No old signing key can be recovered from a public certificate.

Actual OAuth selection and linking must be verified on the user's device after the new certificate is registered. A successful compile is not proof of a completed real Google login.

Native Android run42419105981 succeeded, uploaded Build43 artifact13592624589, and verified the packaged Google web client matches the updated Firebase configuration. Public certificate fingerprints and installation/account-linking instructions are in BUILD43-FIREBASE-FINGERPRINTS.md. Device OAuth acceptance is still pending.
