"""Validate public app configuration without printing any secret input."""
import os
from urllib.parse import urlsplit

mode = os.environ.get("TOMI_BUILD_MODE", "accounts")
api_url = os.environ.get("TOMI_API_URL", "").strip().rstrip("/")
if mode not in {"accounts", "preview"}:
    raise SystemExit("Choose accounts or preview build mode.")
if mode == "accounts":
    parsed = urlsplit(api_url)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or
            parsed.password or parsed.query or parsed.fragment or "\n" in api_url or "\r" in api_url):
        raise SystemExit("Accounts builds need the HTTPS app server URL in api_url or repository variable TOMI_API_URL. Do not use the database URL.")
else:
    api_url = ""
values = {"TOMI_API_URL": api_url, "TOMI_PREVIEW_MODE": str(mode == "preview").lower()}
if os.environ.get("GITHUB_ENV"):
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as handle:
        for key, value in values.items():
            handle.write(f"{key}={value}\n")
print(f"Validated TOMI 1.7.0-beta.1 {mode} build configuration.")
