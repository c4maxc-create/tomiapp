#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tomi_ios_backup="$(mktemp -d)"
trap 'rm -rf "$tomi_ios_backup"' EXIT
for tomi_path in lib test pubspec.yaml pubspec.lock analysis_options.yaml README.md .gitignore; do
  if [ -e "$tomi_path" ]; then cp -R "$tomi_path" "$tomi_ios_backup/"; fi
done
flutter create --platforms=ios --project-name=tomi_app --org=com.tomi --no-pub --empty .
for tomi_path in lib test pubspec.yaml pubspec.lock analysis_options.yaml README.md .gitignore; do
  if [ -e "$tomi_ios_backup/$tomi_path" ]; then
    if [ -d "$tomi_ios_backup/$tomi_path" ]; then cp -R "$tomi_ios_backup/$tomi_path/." "$tomi_path/"; else cp "$tomi_ios_backup/$tomi_path" "$tomi_path"; fi
  fi
done
if [ ! -e "$tomi_ios_backup/test/widget_test.dart" ]; then rm -f test/widget_test.dart; fi
python3 tool/configure_ios.py

python3 tool/configure_identity_native.py ios
