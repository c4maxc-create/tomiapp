"""Apply TOMI branding, networking permissions and secure-session settings."""

from pathlib import Path
import xml.etree.ElementTree as ET
import shutil

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
    for permission in ['android.permission.FOREGROUND_SERVICE','android.permission.FOREGROUND_SERVICE_MICROPHONE','android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK','android.permission.WAKE_LOCK','android.permission.RECORD_AUDIO','android.permission.POST_NOTIFICATIONS','android.permission.CAMERA','android.permission.ACCESS_NETWORK_STATE','android.permission.CHANGE_NETWORK_STATE','android.permission.MODIFY_AUDIO_SETTINGS','android.permission.BLUETOOTH_CONNECT']:
        if not any(item.get(f'{{{ANDROID_NS}}}name')==permission for item in tree.getroot().findall('uses-permission')):
            ET.SubElement(tree.getroot(),'uses-permission',{f'{{{ANDROID_NS}}}name':permission})
    for permission in ['android.permission.BLUETOOTH','android.permission.BLUETOOTH_ADMIN']:
        if not any(item.get(f'{{{ANDROID_NS}}}name')==permission for item in tree.getroot().findall('uses-permission')):
            ET.SubElement(tree.getroot(),'uses-permission',{f'{{{ANDROID_NS}}}name':permission,f'{{{ANDROID_NS}}}maxSdkVersion':'30'})
    if not any(item.get(f'{{{ANDROID_NS}}}name')=='android.hardware.camera.any' for item in tree.getroot().findall('uses-feature')):
        ET.SubElement(tree.getroot(),'uses-feature',{f'{{{ANDROID_NS}}}name':'android.hardware.camera.any',f'{{{ANDROID_NS}}}required':'false'})
    if not any(item.get(f'{{{ANDROID_NS}}}name')=='android.hardware.microphone' for item in tree.getroot().findall('uses-feature')):
        ET.SubElement(tree.getroot(),'uses-feature',{f'{{{ANDROID_NS}}}name':'android.hardware.microphone',f'{{{ANDROID_NS}}}required':'false'})
    for name,value in [('firebase_messaging_auto_init_enabled','false'),('com.google.firebase.messaging.default_notification_channel_id','tomi_updates'),('com.google.firebase.messaging.default_notification_icon','@drawable/tomi_notification')]:
        if not any(item.get(f'{{{ANDROID_NS}}}name')==name for item in application.findall('meta-data')):
            ET.SubElement(application,'meta-data',{f'{{{ANDROID_NS}}}name':name,f'{{{ANDROID_NS}}}'+('resource' if value.startswith('@') else 'value'):value})
    # Source lives outside generated android/ so bootstrap cannot overwrite it.
    native = root / 'native/mobile'
    java = root / 'android/app/src/main/java/com/tomi/tomi_app'
    java.mkdir(parents=True, exist_ok=True)
    for source in native.glob('*.java'):
        shutil.copyfile(source, java/source.name)
    # flutter create generates a Kotlin MainActivity: keep one implementation.
    kotlin = root/'android/app/src/main/kotlin/com/tomi/tomi_app/MainActivity.kt'
    kotlin.unlink(missing_ok=True)
    for name, service_type, priority in [
        ('.TomiAudioService', 'microphone|mediaPlayback', None),
        ('.TomiMessagingService', None, '10'),
    ]:
        service = next((e for e in application.findall('service') if e.get(f'{{{ANDROID_NS}}}name') == name), None)
        if service is None:
            service = ET.SubElement(application, 'service', {f'{{{ANDROID_NS}}}name':name,f'{{{ANDROID_NS}}}exported':'false'})
        if service_type: service.set(f'{{{ANDROID_NS}}}foregroundServiceType', service_type)
        if priority and service.find('intent-filter') is None:
            intent = ET.SubElement(service, 'intent-filter', {f'{{{ANDROID_NS}}}priority':priority})
            ET.SubElement(intent, 'action', {f'{{{ANDROID_NS}}}name':'com.google.firebase.MESSAGING_EVENT'})
    if not any(e.get(f'{{{ANDROID_NS}}}name')=='.TomiActionReceiver' for e in application.findall('receiver')):
        ET.SubElement(application,'receiver',{f'{{{ANDROID_NS}}}name':'.TomiActionReceiver',f'{{{ANDROID_NS}}}exported':'false'})
    if not any(e.get(f'{{{ANDROID_NS}}}name')=='.TomiRingExpiryReceiver' for e in application.findall('receiver')):
        ET.SubElement(application,'receiver',{f'{{{ANDROID_NS}}}name':'.TomiRingExpiryReceiver',f'{{{ANDROID_NS}}}exported':'false'})
    # Add the public FCM types used by our presentation service to the app
    # compile classpath. Match FlutterFire's pinned Firebase BoM exactly.
    # firebase_core 4.15.0 in pubspec.lock uses BoM 34.19.0. Bootstrap
    # runs before pub get, so read the pinned version without requiring cache.
    bom = '34.19.0'
    for filename in ['android/app/build.gradle.kts','android/app/build.gradle']:
        gradle = root/filename
        if gradle.exists():
            source = gradle.read_text()
            if 'com.google.firebase:firebase-messaging' not in source:
                # Keep the app and the locked FlutterFire SDK on one BoM.
                if filename.endswith('.kts'):
                    source += '\ndependencies { implementation(platform("com.google.firebase:firebase-bom:$bom")); implementation("com.google.firebase:firebase-messaging") }\n'.replace('$bom', bom)
                else:
                    source += '\ndependencies { implementation platform("com.google.firebase:firebase-bom:$bom"); implementation "com.google.firebase:firebase-messaging" }\n'.replace('$bom', bom)
                gradle.write_text(source)
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
