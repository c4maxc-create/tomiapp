"""Reserve Android build space on TOMI's disposable GitHub-hosted Linux job.

Never run destructive cleanup on a developer machine or a self-hosted runner.
Keep the actual Flutter NDK and all Android compile tools and supported ABIs.
"""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
SDK = Path('/usr/local/lib/android/sdk')
UNUSED_TOOLCHAINS = tuple(map(Path, [
    '/usr/share/dotnet', '/usr/share/swift', '/opt/ghc',
    '/usr/local/.ghcup', '/opt/hostedtoolcache/CodeQL',
]))
VERSION = r'\d+\.\d+\.\d+'


def require_hosted_android(env):
    if (env.get('GITHUB_ACTIONS') != 'true'
            or env.get('TOMI_CI_RUNNER_ENV') != 'github-hosted'
            or env.get('RUNNER_OS') != 'Linux'
            or env.get('GITHUB_JOB') != 'android'):
        raise ValueError('Cleanup is restricted to the disposable GitHub-hosted Linux android job.')


def flutter_ndk(flutter_root):
    tools = Path(flutter_root) / 'packages/flutter_tools'
    versions = set()
    for relative in ['gradle/src/main/kotlin/FlutterExtension.kt',
                     'gradle/src/main/groovy/flutter.groovy',
                     'lib/src/android/gradle_utils.dart']:
        source = tools / relative
        if source.is_file():
            versions.update(re.findall(
                r'\bndkVersion\s*(?::\s*String)?\s*=\s*[\'\"](' + VERSION + r')[\'\"]',
                source.read_text()))
    if len(versions) != 1:
        raise ValueError('Cannot determine one consistent Flutter NDK; no SDK files were removed.')
    return versions.pop()


def check_app_ndk(project, version):
    for relative in ['android/app/build.gradle.kts', 'android/app/build.gradle']:
        path = Path(project) / relative
        if path.is_file():
            source = path.read_text()
            value = re.search(r'\bndkVersion\s*(?:=\s*)?(flutter\.ndkVersion|[\'\"]' + VERSION + r'[\'\"])', source)
            if value and (value[1] == 'flutter.ndkVersion' or value[1].strip('\'\"') == version):
                return
    raise ValueError('The app overrides/misses the Flutter NDK; no SDK files were removed.')


def sdk_cleanup_plan(sdk, keep):
    sdk = Path(sdk)
    if not re.fullmatch(VERSION, keep):
        raise ValueError('Invalid required NDK version.')
    # Reject symlink escapes before returning any deletion plan.
    if sdk.is_symlink() or sdk.resolve() != sdk.absolute():
        raise ValueError('Unexpected SDK symlink.')
    paths = [sdk / 'emulator', sdk / 'system-images', sdk / 'ndk-bundle']
    ndks = sdk / 'ndk'
    if ndks.is_symlink():
        raise ValueError('Unexpected NDK directory symlink.')
    if ndks.exists():
        paths += [p for p in sorted(ndks.iterdir())
                  if re.fullmatch(VERSION, p.name) and p.name != keep]
    for path in paths:
        if path.is_symlink() or path.resolve() != path.absolute():
            raise ValueError('Unexpected SDK component symlink; no cleanup was started.')
    return [p for p in paths if p.exists()]


def remove_unused(paths):
    for path in paths:
        if path.is_symlink():
            print('Skipped optional toolchain symlink: ' + str(path), flush=True)
        elif path.exists():
            print('Removing unused CI component: ' + str(path), flush=True)
            subprocess.run(['sudo', '-n', 'rm', '-rf', '--', str(path)], check=True, timeout=180)


def configure_gradle(project):
    path = Path(project) / 'android/gradle.properties'
    if not path.parent.is_dir():
        raise ValueError('Generate Android scaffold before preparing Gradle.')
    source = path.read_text() if path.exists() else ''
    values = {'org.gradle.parallel': 'false', 'org.gradle.workers.max': '2',
              'org.gradle.caching': 'false'}
    lines = [line for line in source.splitlines()
             if not any(re.match(r'\s*' + re.escape(key) + r'\s*[:=]', line) for key in values)]
    lines += [key + '=' + value for key, value in values.items()]
    path.write_text('\n'.join(lines) + '\n')


def space_paths(env):
    paths = [Path('/'), ROOT, SDK, Path(env.get('RUNNER_TEMP', '/tmp'))]
    return [p for p in paths if p.is_dir()]


def check_space(paths, minimum, usage=shutil.disk_usage):
    if minimum < 0 or minimum > 200:
        raise ValueError('Invalid free-space threshold.')
    low = []
    for path in paths:
        free = usage(path).free / 1024**3
        print(f'Disk available at {path}: {free:.1f} GiB (minimum {minimum:g} GiB)', flush=True)
        if free < minimum:
            low.append(str(path))
    if low:
        raise ValueError(f'Android build needs at least {minimum:g} GiB free at: ' + ', '.join(low)
                         + '. Stop before Gradle fills the runner; inspect the cleanup log.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=['early', 'android', 'check', 'report'])
    parser.add_argument('--minimum-gib', type=int, default=20)
    args = parser.parse_args()
    env = os.environ
    if args.phase in ['early', 'android']:
        require_hosted_android(env)
        check_space(space_paths(env), 0)
        if args.phase == 'early':
            remove_unused(UNUSED_TOOLCHAINS)
        else:
            declared_sdk = Path(env.get('ANDROID_HOME') or env.get('ANDROID_SDK_ROOT') or str(SDK))
            if declared_sdk != SDK or not SDK.is_dir():
                raise ValueError('Expected the GitHub Ubuntu SDK path; no SDK cleanup was started.')
            flutter_root = env.get('FLUTTER_ROOT')
            if not flutter_root:
                binary = shutil.which('flutter')
                if not binary:
                    raise ValueError('Set up Flutter before SDK cleanup.')
                flutter_root = str(Path(binary).resolve().parent.parent)
            version = flutter_ndk(flutter_root)
            check_app_ndk(ROOT, version)
            plan = sdk_cleanup_plan(SDK, version)
            print('Keeping Flutter-required NDK ' + version + '; Gradle installs it if absent.', flush=True)
            remove_unused(plan)
            configure_gradle(ROOT)
        check_space(space_paths(env), 0 if args.phase == 'early' else args.minimum_gib)
    else:
        check_space(space_paths(env), 0 if args.phase == 'report' else args.minimum_gib)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit('Android CI disk preparation failed: ' + str(error)) from None
