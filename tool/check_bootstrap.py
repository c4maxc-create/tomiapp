"""Check source preservation and app branding without claiming a Flutter build."""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

import yaml

ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    config = yaml.safe_load((ROOT / "codemagic.yaml").read_text())
    flow = config["workflows"]["tomi-android-preview"]
    assert flow["instance_type"] == "mac_mini_m2"
    assert flow["environment"]["flutter"] == "stable"
    assert len(flow["scripts"]) == 5
    assert flow["artifacts"] == ["output/TOMI-0.2.0.apk"]

    with tempfile.TemporaryDirectory(prefix="tomi-check-") as temp:
        temp = Path(temp)
        project = temp / "project"
        shutil.copytree(ROOT, project, ignore=shutil.ignore_patterns("__pycache__", "build", ".dart_tool", "node_modules"))
        original = {path.relative_to(project): path.read_bytes()
                    for path in project.rglob("*") if path.is_file()}
        bin_dir = temp / "bin"
        bin_dir.mkdir()
        fake_flutter = bin_dir / "flutter"
        fake_flutter.write_text('''#!/usr/bin/env python3
from pathlib import Path
Path("android/app/src/main").mkdir(parents=True, exist_ok=True)
Path("android/app/src/main/AndroidManifest.xml").write_text(
 '<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="tomi_app" android:icon="@mipmap/ic_launcher"/></manifest>')
Path("lib/main.dart").write_text("template main")
Path("test/widget_test.dart").write_text("template test")
Path("pubspec.yaml").write_text("template pubspec")
Path("analysis_options.yaml").write_text("template lints")
Path("README.md").write_text("template readme")
''')
        fake_flutter.chmod(0o755)
        env = os.environ.copy()
        env["PATH"] = str(bin_dir) + os.pathsep + env["PATH"]
        subprocess.run(["bash", "tool/bootstrap_android.sh"], cwd=project, env=env, check=True)
        for relative, contents in original.items():
            assert (project / relative).read_bytes() == contents, f"Source overwritten: {relative}"
        assert not (project / "test/widget_test.dart").exists()
        manifest = ET.parse(project / "android/app/src/main/AndroidManifest.xml")
        app = manifest.getroot().find("application")
        ns = "{http://schemas.android.com/apk/res/android}"
        assert app is not None and app.get(ns + "label") == "TOMI"
        assert app.get(ns + "icon") == "@drawable/tomi_launcher"
        assert app.get(ns + "allowBackup") == "false"
        assert app.get(ns + "usesCleartextTraffic") == "false"
        assert any(item.get(ns + "name") == "android.permission.INTERNET"
                   for item in manifest.getroot().findall("uses-permission"))
        ET.parse(project / "android/app/src/main/res/drawable/tomi_launcher.xml")
    print("PASS: YAML, original source preservation, template-test removal, Android label and vector icon.")
    print("Flutter analyze, widget tests, PostgreSQL integration and APK compilation run in GitHub Actions.")


if __name__ == "__main__":
    main()
