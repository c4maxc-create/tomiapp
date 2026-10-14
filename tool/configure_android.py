"""Apply TOMI branding, networking permissions and secure-session settings."""

from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
ANDROID_NS = "http://schemas.android.com/apk/res/android"
MANIFEST = ROOT / "android/app/src/main/AndroidManifest.xml"
ICON = ROOT / "android/app/src/main/res/drawable/tomi_launcher.xml"


def configure_android(root: Path = ROOT) -> None:
    manifest = root / "android/app/src/main/AndroidManifest.xml"
    if not manifest.exists():
        raise FileNotFoundError("Android scaffold missing: run bootstrap_android.sh first.")
    ET.register_namespace("android", ANDROID_NS)
    tree = ET.parse(manifest)
    application = tree.getroot().find("application")
    if application is None:
        raise ValueError("Android manifest has no application element.")
    application.set(f"{{{ANDROID_NS}}}label", "TOMI")
    application.set(f"{{{ANDROID_NS}}}icon", "@drawable/tomi_launcher")
    application.set(f"{{{ANDROID_NS}}}allowBackup", "false")
    application.set(f"{{{ANDROID_NS}}}usesCleartextTraffic", "false")
    if not any(item.get(f"{{{ANDROID_NS}}}name") == "android.permission.INTERNET"
               for item in tree.getroot().findall("uses-permission")):
        ET.SubElement(tree.getroot(), "uses-permission", {f"{{{ANDROID_NS}}}name": "android.permission.INTERNET"})
    for permission in ['android.permission.RECORD_AUDIO','android.permission.POST_NOTIFICATIONS']:
        if not any(item.get(f'{{{ANDROID_NS}}}name')==permission for item in tree.getroot().findall('uses-permission')):
            ET.SubElement(tree.getroot(),'uses-permission',{f'{{{ANDROID_NS}}}name':permission})
    if not any(item.get(f'{{{ANDROID_NS}}}name')=='android.hardware.microphone' for item in tree.getroot().findall('uses-feature')):
        ET.SubElement(tree.getroot(),'uses-feature',{f'{{{ANDROID_NS}}}name':'android.hardware.microphone',f'{{{ANDROID_NS}}}required':'false'})
    for name,value in [('firebase_messaging_auto_init_enabled','false'),('com.google.firebase.messaging.default_notification_icon','@drawable/tomi_notification')]:
        if not any(item.get(f'{{{ANDROID_NS}}}name')==name for item in application.findall('meta-data')):
            ET.SubElement(application,'meta-data',{f'{{{ANDROID_NS}}}name':name,f'{{{ANDROID_NS}}}'+('resource' if value.startswith('@') else 'value'):value})
    notification=root/'android/app/src/main/res/drawable/tomi_notification.xml'
    notification.parent.mkdir(parents=True,exist_ok=True)
    notification.write_text('<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24"><path android:fillColor="#FFFFFFFF" android:pathData="M3,4H21V8H14V21H10V8H3Z"/></vector>')
    tree.write(manifest, encoding="utf-8", xml_declaration=True)
    # Secure storage requires Android 6.0+; Flutter's generated default varies.
    for filename in ["android/app/build.gradle.kts", "android/app/build.gradle"]:
        gradle = root / filename
        if gradle.exists():
            import re
            source = gradle.read_text(encoding="utf-8")
            replacement = "minSdk = maxOf(flutter.minSdkVersion, 23)" if filename.endswith(".kts") else "minSdkVersion Math.max(flutter.minSdkVersion, 23)"
            source = re.sub(r"\bminSdk(?:Version)?\s*(?:=\s*)?(?:flutter\.minSdkVersion|\d+)", replacement, source)
            gradle.write_text(source, encoding="utf-8")
    icon = root / "android/app/src/main/res/drawable/tomi_launcher.xml"
    icon.parent.mkdir(parents=True, exist_ok=True)
    icon.write_text('''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#151A2A" android:pathData="M0,0H108V108H0Z"/>
    <path android:fillColor="#B197FF" android:pathData="M24,27H84V42H62V83H46V42H24Z"/>
    <path android:fillColor="#F292BC" android:pathData="M79,70H87V78H79Z"/>
</vector>
''', encoding="utf-8")


if __name__ == "__main__":
    configure_android()
