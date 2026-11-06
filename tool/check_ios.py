"""Local source/idempotence check; actual Swift/plugin compilation runs on macOS."""
from pathlib import Path
import plistlib,shutil,tempfile
from configure_ios import configure_ios,BUNDLE
ROOT=Path(__file__).resolve().parent.parent

def main():
    with tempfile.TemporaryDirectory() as tmp:
        root=Path(tmp);(root/'native/ios').mkdir(parents=True)
        for p in (ROOT/'native/ios').glob('*.swift'):shutil.copyfile(p,root/'native/ios'/p.name)
        runner=root/'ios/Runner';runner.mkdir(parents=True)
        (runner/'Info.plist').write_bytes(plistlib.dumps({'CFBundleDisplayName':'template','NSAppTransportSecurity':{'NSAllowsArbitraryLoads':True}}))
        project=root/'ios/Runner.xcodeproj/project.pbxproj';project.parent.mkdir()
        project.write_text('/* Begin PBXBuildFile section */\n/* Begin PBXFileReference section */\n74858FAE1ED2DC5600515810 /* AppDelegate.swift */,\n97C146FC1CF9000F007C117D /* Main.storyboard in Resources */,\nPRODUCT_BUNDLE_IDENTIFIER = com.tomi.tomiApp;\n')
        assert configure_ios(root,firebase='') is False
        data=plistlib.loads((runner/'Info.plist').read_bytes());assert 'NSAllowsArbitraryLoads' not in data['NSAppTransportSecurity'];assert data['NSAppTransportSecurity']['NSAllowsLocalNetworking'];assert data['CFBundleURLTypes'][0]['CFBundleURLSchemes']==['tomi'];assert BUNDLE in project.read_text()
        config=plistlib.dumps({'BUNDLE_ID':BUNDLE,'GOOGLE_APP_ID':'1:123456789:ios:fixture'}).decode()
        assert configure_ios(root,firebase=config)
        before={str(p.relative_to(root)):p.read_bytes() for p in (root/'ios').rglob('*') if p.is_file()}
        assert configure_ios(root,firebase=config)
        assert before=={str(p.relative_to(root)):p.read_bytes() for p in (root/'ios').rglob('*') if p.is_file()}
        for invalid in [plistlib.dumps({'BUNDLE_ID':'wrong','GOOGLE_APP_ID':'1:123:ios:fixture'}).decode(),plistlib.dumps({'BUNDLE_ID':BUNDLE,'GOOGLE_APP_ID':'1:123:ios:fixture','private_key':'forbidden'}).decode()]:
            try:configure_ios(root,firebase=invalid)
            except ValueError:pass
            else:raise AssertionError('Accepted incorrect/private client configuration')
        assert 'GeneratedPluginRegistrant.register' in (runner/'AppDelegate.swift').read_text()
        assert 'takeDeepLink' in (runner/'AppDelegate.swift').read_text()
        print('PASS: iOS client scaffold, privacy, deep links, Firebase validation and repeatability; Swift compilation requires macOS.')
if __name__=='__main__':main()
