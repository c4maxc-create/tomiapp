"""Verify public OAuth configuration and idempotence without contacting providers."""
from pathlib import Path
import tempfile,plistlib,xml.etree.ElementTree as ET
from configure_identity_native import android,ios,facebook,A
with tempfile.TemporaryDirectory(prefix='tomi-identity-') as temp:
    root=Path(temp);manifest=root/'android/app/src/main/AndroidManifest.xml';manifest.parent.mkdir(parents=True)
    manifest.write_text('<manifest xmlns:android="'+A+'"><application/></manifest>')
    android(root,{})
    tree=ET.parse(manifest);assert all(x.get('{'+A+'}value')=='false' for x in tree.findall('application/meta-data'))
    assert not (manifest.parent/'res/values/tomi_facebook.xml').exists()
    env={'TOMI_FACEBOOK_APP_ID':'123456789','TOMI_FACEBOOK_CLIENT_TOKEN':'test_client_token_not_a_secret'}
    android(root,env);first=manifest.read_bytes();android(root,env);assert manifest.read_bytes()==first
    assert len(ET.parse(manifest).findall('application/activity'))==1
    runner=root/'ios/Runner';runner.mkdir(parents=True);(runner/'Info.plist').write_bytes(plistlib.dumps({'ITSAppUsesNonExemptEncryption':False}))
    (runner/'GoogleService-Info.plist').write_bytes(plistlib.dumps({'REVERSED_CLIENT_ID':'com.googleusercontent.apps.123-test','CLIENT_ID':'123-test.apps.googleusercontent.com'}))
    project=root/'ios/Runner.xcodeproj/project.pbxproj';project.parent.mkdir();project.write_text('PRODUCT_BUNDLE_IDENTIFIER = com.tomi.tomiapp;')
    ios(root,env);first=(runner/'Info.plist').read_bytes();ios(root,env);assert (runner/'Info.plist').read_bytes()==first
    data=plistlib.loads(first);assert len(data['CFBundleURLTypes'])==2;assert data['GIDClientID'].endswith('.com');assert 'ITSAppUsesNonExemptEncryption' not in data
    assert plistlib.loads((runner/'Runner.entitlements').read_bytes())['com.apple.developer.applesignin']==['Default']
    assert project.read_text().count('CODE_SIGN_ENTITLEMENTS')==1
    for env in [{'TOMI_FACEBOOK_APP_ID':'12345'},{'TOMI_FACEBOOK_APP_ID':'bad','TOMI_FACEBOOK_CLIENT_TOKEN':'valid_token_42'}]:
        try:facebook(env)
        except ValueError:pass
        else:raise AssertionError('Invalid public configuration was accepted')
print('PASS: public OAuth configuration, deferred Facebook setup, tracking defaults, Apple entitlement and repeatability.')
