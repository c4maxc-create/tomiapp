"""Check source preservation and app branding without claiming a Flutter build."""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

import yaml
from configure_android import configure_android

ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    config = yaml.safe_load((ROOT / "codemagic.yaml").read_text())
    flow = config["workflows"]["tomi-android-preview"]
    assert flow["instance_type"] == "mac_mini_m2"
    assert flow["environment"]["flutter"] == "stable"
    assert len(flow["scripts"]) == 6
    version = yaml.safe_load((ROOT / "pubspec.yaml").read_text())["version"].split("+")[0]
    assert flow["artifacts"] == [f"output/TOMI-{version}.apk"]

    with tempfile.TemporaryDirectory(prefix="tomi-check-") as temp:
        temp = Path(temp)
        project = temp / "project"
        shutil.copytree(ROOT, project, ignore=shutil.ignore_patterns("__pycache__", "build", ".dart_tool", "node_modules", "target", "Frameworks", "jniLibs"))
        original = {path.relative_to(project): path.read_bytes()
                    for path in project.rglob("*") if path.is_file() and "android" not in path.relative_to(project).parts}
        bin_dir = temp / "bin"
        bin_dir.mkdir()
        fake_flutter = bin_dir / "flutter"
        fake_flutter.write_text('''#!/usr/bin/env python3
from pathlib import Path
Path("android/app/src/main").mkdir(parents=True, exist_ok=True)
Path("android/app/src/main/AndroidManifest.xml").write_text(
 '<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="tomi_app" android:icon="@mipmap/ic_launcher"/></manifest>')
Path("android/app/build.gradle.kts").write_text("plugins {}")
Path("android/app/src/main/kotlin/com/tomi/tomi_app").mkdir(parents=True,exist_ok=True)
Path("android/app/src/main/kotlin/com/tomi/tomi_app/MainActivity.kt").write_text("template activity")
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
        configure_android(project)
        assert not (project/'android/app/src/main/kotlin/com/tomi/tomi_app/MainActivity.kt').exists()
        assert (project/'android/app/src/main/kotlin/com/tomi/tomi_app/TomiVoiceAudio.kt').exists()
        assert (project/'android/app/src/main/kotlin/com/tomi/tomi_app/TomiDeviceTools.kt').exists()
        assert (project/'android/app/src/main/kotlin/com/tomi/tomi_app/TomiLinks.kt').exists()
        assert (project/'android/app/src/main/res/xml/tomi_share_paths.xml').read_text().count('path="qr/"')==1
        generated_gradle=(project/'android/app/build.gradle.kts').read_text()
        assert generated_gradle.count('org.jetbrains.kotlin.android')==1
        assert generated_gradle.count('// TOMI Kotlin JVM target')==1
        assert generated_gradle.count('com.google.firebase:firebase-messaging')==1
        assert generated_gradle.count('com.google.zxing:core:3.5.3')==1
        assert generated_gradle.count('firebase-bom:34.19.0')==1
        manifest = ET.parse(project / "android/app/src/main/AndroidManifest.xml")
        app = manifest.getroot().find("application")
        ns = "{http://schemas.android.com/apk/res/android}"
        assert app is not None and app.get(ns + "label") == "TOMI"
        assert app.get(ns + "icon") == "@drawable/tomi_launcher"
        assert app.get(ns + "allowBackup") == "false"
        assert app.get(ns + "usesCleartextTraffic") == "false"
        assert app.get(ns + "networkSecurityConfig") == "@xml/tomi_network_security"
        network=ET.parse(project/'android/app/src/main/res/xml/tomi_network_security.xml').getroot()
        assert network.find('base-config').get('cleartextTrafficPermitted') == 'false'
        assert [d.text for d in network.findall('domain-config/domain')] == ['127.0.0.1']
        assert network.find('domain-config/domain').get('includeSubdomains') == 'false'
        assert any(item.get(ns + "name") == "android.permission.INTERNET"
                   for item in manifest.getroot().findall("uses-permission"))
        for permission in ['android.permission.RECORD_AUDIO','android.permission.POST_NOTIFICATIONS','android.permission.CAMERA','android.permission.MODIFY_AUDIO_SETTINGS','android.permission.ACCESS_NETWORK_STATE']:
            assert any(item.get(ns+'name')==permission for item in manifest.getroot().findall('uses-permission'))
        assert any(item.get(ns+'name')=='firebase_messaging_auto_init_enabled' and item.get(ns+'value')=='false' for item in app.findall('meta-data'))
        channels=[e for e in app.findall('meta-data') if e.get(ns+'name')=='com.google.firebase.messaging.default_notification_channel_id']
        assert len(channels)==1 and channels[0].get(ns+'value')=='tomi_updates'
        services={e.get(ns+'name'):e for e in app.findall('service')}
        assert services['.TomiAudioService'].get(ns+'foregroundServiceType') == 'microphone|mediaPlayback'
        assert services['.TomiMessagingService'].find('intent-filter').get(ns+'priority') == '10'
        assert services['.TomiMessagingService'].get(ns+'exported') == 'false'
        for receiver in ['.TomiActionReceiver','.TomiRingExpiryReceiver']:
            assert any(e.get(ns+'name')==receiver and e.get(ns+'exported')=='false' for e in app.findall('receiver'))
        for permission in ['FOREGROUND_SERVICE','FOREGROUND_SERVICE_MICROPHONE','FOREGROUND_SERVICE_MEDIA_PLAYBACK','WAKE_LOCK']:
            assert any(e.get(ns+'name')=='android.permission.'+permission for e in manifest.getroot().findall('uses-permission'))
        for source in (ROOT/'native/mobile').glob('*.java'):
            assert (project/'android/app/src/main/java/com/tomi/tomi_app'/source.name).read_bytes()==source.read_bytes()
        ET.parse(project / "android/app/src/main/res/drawable/tomi_launcher.xml")
        ET.parse(project / "android/app/src/main/res/drawable/tomi_notification.xml")
    print("PASS: YAML, original source preservation, template-test removal, Android label and vector icon.")
    print("Flutter analyze, widget tests, PostgreSQL integration and APK compilation run in GitHub Actions.")


if __name__ == "__main__":
    main()
