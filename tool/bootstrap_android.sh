#!/usr/bin/env bash
set -euo pipefail

# The Flutter SDK installed by Codemagic creates a compatible Android/Gradle
# scaffold. The original application files are preserved, including user edits.
cd "$(dirname "$0")/.."
tomi_backup_dir="$(mktemp -d)"
trap 'rm -rf "$tomi_backup_dir"' EXIT

for tomi_path in lib test pubspec.yaml pubspec.lock analysis_options.yaml README.md .gitignore; do
  if [ -e "$tomi_path" ]; then
    cp -R "$tomi_path" "$tomi_backup_dir/"
  fi
done

flutter create --platforms=android --project-name=tomi_app \
  --org=com.tomi --no-pub --empty .

for tomi_path in lib test pubspec.yaml pubspec.lock analysis_options.yaml README.md .gitignore; do
  if [ -e "$tomi_backup_dir/$tomi_path" ]; then
    if [ -d "$tomi_backup_dir/$tomi_path" ]; then
      cp -R "$tomi_backup_dir/$tomi_path/." "$tomi_path/"
    else
      cp "$tomi_backup_dir/$tomi_path" "$tomi_path"
    fi
  fi
done

# Remove only the template test if it was not part of the user's source.
if [ ! -e "$tomi_backup_dir/test/widget_test.dart" ]; then
  rm -f test/widget_test.dart
fi

python3 tool/configure_android.py
python3 tool/configure_identity_native.py android
