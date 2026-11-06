"""Configure generated iOS scaffolding; no signing identities or private keys."""
from pathlib import Path
import os, plistlib, re, shutil
ROOT=Path(__file__).resolve().parent.parent
BUNDLE='com.tomi.tomiapp'
def configure_ios(root=ROOT, firebase=None):
    ios=root/'ios';runner=ios/'Runner'
    if not runner.is_dir():raise ValueError('Generate the iOS project with bootstrap_ios.sh first.')
    for source in (root/'native/ios').glob('*.swift'):shutil.copyfile(source,runner/source.name)
    path=runner/'Info.plist';data=plistlib.loads(path.read_bytes())
    data.update({'CFBundleDisplayName':'TOMI','NSMicrophoneUsageDescription':'تومي يستخدم المايك عند تسجيل فويز أو فتحه في مكالمة أو غرفة.','NSCameraUsageDescription':'تومي يستخدم الكاميرا عند اختيار مكالمة فيديو أو تصوير محتوى.','NSPhotoLibraryUsageDescription':'اختر صوراً وفيديوهات تريد مشاركتها في تومي.','NSPhotoLibraryAddUsageDescription':'احفظ الصور والنتائج التي تختارها في الاستوديو.','UIBackgroundModes':['audio','remote-notification'],'ITSAppUsesNonExemptEncryption':False})
    ats=data.setdefault('NSAppTransportSecurity',{});ats['NSAllowsLocalNetworking']=True
    ats.pop('NSAllowsArbitraryLoads',None)
    data['CFBundleURLTypes']=[{'CFBundleURLName':'com.tomi.links','CFBundleURLSchemes':['tomi'],'CFBundleTypeRole':'Viewer'}]
    path.write_bytes(plistlib.dumps(data,sort_keys=False))
    project=ios/'Runner.xcodeproj/project.pbxproj';text=project.read_text();text=re.sub(r'PRODUCT_BUNDLE_IDENTIFIER = com\.tomi\.tomiApp',f'PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE}',text);text=re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;', 'IPHONEOS_DEPLOYMENT_TARGET = 16.4;', text);project.write_text(text)
    podfile=ios/'Podfile'
    if not podfile.exists():podfile.write_text("""platform :ios, '16.4'
ENV['COCOAPODS_DISABLE_STATS'] = 'true'
project 'Runner', {'Debug' => :debug, 'Profile' => :release, 'Release' => :release}
def flutter_root
  path = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  raise 'Run flutter pub get before pod install' unless File.exist?(path)
  File.foreach(path) { |line| return line.split('=').last.strip if line.start_with?('FLUTTER_ROOT=') }
  raise 'FLUTTER_ROOT missing'
end
require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)
flutter_ios_podfile_setup
target 'Runner' do
  use_frameworks!
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  target 'RunnerTests' do
    inherit! :search_paths
  end
end
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.4'
    end
  end
end
""")
    raw=os.environ.get('TOMI_IOS_GOOGLE_SERVICES_PLIST','') if firebase is None else firebase
    if not raw:return False
    if len(raw.encode())>131072:raise ValueError('iOS client configuration is too large')
    config=plistlib.loads(raw.encode())
    if config.get('BUNDLE_ID')!=BUNDLE or ':ios:' not in config.get('GOOGLE_APP_ID','') or any(k in config for k in ['private_key','PRIVATE_KEY','private_key_id']):raise ValueError('Use the Firebase iOS client plist for '+BUNDLE+', never an Admin SDK key.')
    (runner/'GoogleService-Info.plist').write_bytes(plistlib.dumps(config,sort_keys=False))
    text=project.read_text()
    if 'TOMI Firebase client' not in text:
        text=text.replace('/* Begin PBXBuildFile section */','/* Begin PBXBuildFile section */\n\t\tD20000000000000000000001 /* TOMI Firebase client in Resources */ = {isa = PBXBuildFile; fileRef = D20000000000000000000002 /* TOMI Firebase client */; };',1)
        text=text.replace('/* Begin PBXFileReference section */','/* Begin PBXFileReference section */\n\t\tD20000000000000000000002 /* TOMI Firebase client */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "GoogleService-Info.plist"; sourceTree = "<group>"; };',1)
        text=text.replace('74858FAE1ED2DC5600515810 /* AppDelegate.swift */,','74858FAE1ED2DC5600515810 /* AppDelegate.swift */,\n\t\t\t\tD20000000000000000000002 /* TOMI Firebase client */,',1)
        text=text.replace('97C146FC1CF9000F007C117D /* Main.storyboard in Resources */,','97C146FC1CF9000F007C117D /* Main.storyboard in Resources */,\n\t\t\t\tD20000000000000000000001 /* TOMI Firebase client in Resources */,',1)
        project.write_text(text)
    return True
if __name__=='__main__':
    present=configure_ios()
    print('Configured TOMI iOS scaffold; Firebase client present: '+str(present)+'. Signing and APNs capability require the Apple project setup.')
