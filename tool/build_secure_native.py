"""Build the pinned, first-party FFI adapter. Generated native binaries are not source assets."""
import argparse,os,platform,shutil,subprocess
from pathlib import Path
root=Path(__file__).resolve().parent.parent
native=root/'packages/tomi_secure/native'
parser=argparse.ArgumentParser();parser.add_argument('--platform',choices=['host','android','ios'],default='host');args=parser.parse_args()
rustup=shutil.which('rustup');cargo=shutil.which('cargo')
if not rustup or not cargo:raise SystemExit('Install Rust 1.89.0 with rustup before building secure chats.')
def run(cmd,env=None):subprocess.run(cmd,cwd=root,env=env,check=True)
run([rustup,'toolchain','install','1.89.0','--profile','minimal'])
base=[cargo,'+1.89.0','build','--locked','--release','--manifest-path',str(native/'Cargo.toml')]
if args.platform=='host':run(base)
elif args.platform=='android':
    ndk=next((Path(os.environ[k]) for k in ['ANDROID_NDK_HOME','ANDROID_NDK_ROOT'] if os.environ.get(k)),None)
    if ndk is not None and not ndk.is_dir():ndk=None
    if ndk is None:
        sdk=Path(os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT') or '/usr/local/lib/android/sdk')
        choices=sorted((sdk/'ndk').glob('*'),key=lambda p:[int(n) for n in p.name.split('.')])
        if not choices:
            from prepare_android_ci import flutter_ndk
            flutter=Path(os.environ.get('FLUTTER_ROOT') or str(Path(shutil.which('flutter') or '').resolve().parent.parent))
            version=flutter_ndk(flutter);manager=sdk/'cmdline-tools/latest/bin/sdkmanager'
            if not manager.is_file():raise SystemExit('Android SDK manager is required to install the Flutter NDK.')
            run([str(manager),'ndk;'+version]);choices=[sdk/'ndk'/version]
        ndk=choices[-1]
    host='darwin-x86_64' if platform.system()=='Darwin' else 'linux-x86_64'
    bin=ndk/'toolchains/llvm/prebuilt'/host/'bin'
    for target,abi,linker in [('aarch64-linux-android','arm64-v8a','aarch64-linux-android23-clang'),('armv7-linux-androideabi','armeabi-v7a','armv7a-linux-androideabi23-clang'),('x86_64-linux-android','x86_64','x86_64-linux-android23-clang')]:
        run([rustup,'target','add','--toolchain','1.89.0',target]);env=os.environ.copy();env['CARGO_TARGET_'+target.upper().replace('-','_')+'_LINKER']=str(bin/linker);env['CC_'+target.replace('-','_')]=str(bin/linker);env['AR_'+target.replace('-','_')]=str(bin/'llvm-ar');env['RUSTFLAGS']=(env.get('RUSTFLAGS','')+' -C link-arg=-Wl,-z,max-page-size=16384').strip()
        run(base+['--target',target],env)
        out=root/'packages/tomi_secure/android/src/main/jniLibs'/abi;out.mkdir(parents=True,exist_ok=True);shutil.copy2(native/'target'/target/'release/libtomi_secure.so',out/'libtomi_secure.so')
else:
    if platform.system()!='Darwin':raise SystemExit('iOS native builds require macOS/Xcode.')
    for target in ['aarch64-apple-ios','aarch64-apple-ios-sim','x86_64-apple-ios']:
        run([rustup,'target','add','--toolchain','1.89.0',target]);run(base+['--target',target])
    fat=native/'target/ios-universal/libtomi_secure.a';fat.parent.mkdir(parents=True,exist_ok=True)
    run(['lipo','-create',str(native/'target/aarch64-apple-ios-sim/release/libtomi_secure.a'),str(native/'target/x86_64-apple-ios/release/libtomi_secure.a'),'-output',str(fat)])
    output=root/'packages/tomi_secure/ios/Frameworks/TomiSecure.xcframework';shutil.rmtree(output,ignore_errors=True)
    headers=root/'packages/tomi_secure/ios/Classes'
    run(['xcodebuild','-create-xcframework','-library',str(native/'target/aarch64-apple-ios/release/libtomi_secure.a'),'-headers',str(headers),'-library',str(fat),'-headers',str(headers),'-output',str(output)])

    import plistlib
    info=plistlib.loads((output/'Info.plist').read_bytes())
    if any(Path(s['LibraryPath']).name != 'libtomi_secure.a' for s in info['AvailableLibraries']):raise SystemExit('All iOS slices must expose the same static library basename.')
