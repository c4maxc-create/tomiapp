"""Apply the preview's app label and a vector launcher icon to Flutter output."""

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
    tree.write(manifest, encoding="utf-8", xml_declaration=True)
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
