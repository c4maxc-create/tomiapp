"""Exercise cleanup boundaries on disposable fixtures; never clean the host."""
from collections import namedtuple
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
import shutil
import tempfile
import unittest
from prepare_android_ci import (require_hosted_android, flutter_ndk, check_app_ndk,
                                sdk_cleanup_plan, configure_gradle, check_space)


class AndroidDiskTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='tomi-ci-disk-test-')
        self.root = Path(self.temp.name).resolve()

    def tearDown(self):
        self.temp.cleanup()

    def test_cleanup_denies_local_self_hosted_and_database_jobs(self):
        good = dict(GITHUB_ACTIONS='true', TOMI_CI_RUNNER_ENV='github-hosted',
                    RUNNER_OS='Linux', GITHUB_JOB='android')
        require_hosted_android(good)
        for env in [{}, dict(good, TOMI_CI_RUNNER_ENV='self-hosted'),
                    dict(good, GITHUB_JOB='accounts-api'), dict(good, RUNNER_OS='Windows')]:
            with self.assertRaises(ValueError):
                require_hosted_android(env)

    def test_actual_cleanup_preserves_required_ndk_compile_tools_and_other_files(self):
        sdk = self.root / 'sdk'
        paths = ['ndk/28.2.13676358', 'ndk/27.3.13750724', 'ndk/30.0.16248370',
                 'ndk/notes', 'emulator', 'system-images', 'platforms/android-36',
                 'build-tools/36.0.0', 'platform-tools', 'cmdline-tools/latest', 'licenses', 'cmake/3.22.1']
        for item in paths:
            p = sdk / item; p.mkdir(parents=True); (p / 'keep-or-delete').write_text(item)
        other = self.root / 'project'; other.mkdir(); (other / 'source').write_text('untouched')
        plan = sdk_cleanup_plan(sdk, '28.2.13676358')
        for path in plan:
            shutil.rmtree(path)
        for item in ['ndk/28.2.13676358', 'ndk/notes', 'platforms/android-36',
                     'build-tools/36.0.0', 'platform-tools', 'cmdline-tools/latest', 'licenses', 'cmake/3.22.1']:
            self.assertTrue((sdk / item / 'keep-or-delete').is_file(), item)
        self.assertFalse((sdk / 'ndk/27.3.13750724').exists())
        self.assertFalse((sdk / 'emulator').exists())
        self.assertEqual((other / 'source').read_text(), 'untouched')
        self.assertEqual(sdk_cleanup_plan(sdk, '28.2.13676358'), [])

    def test_missing_required_ndk_is_not_replaced_by_newer_preinstalled_one(self):
        sdk = self.root / 'sdk'; (sdk / 'ndk/30.0.16248370').mkdir(parents=True)
        self.assertEqual(sdk_cleanup_plan(sdk, '28.2.13676358'), [sdk / 'ndk/30.0.16248370'])
        with self.assertRaises(ValueError):
            sdk_cleanup_plan(sdk, '../bad')

    def test_sdk_symlink_escape_is_rejected_before_any_deletion(self):
        sdk = self.root / 'sdk'; sdk.mkdir(); outside = self.root / 'outside'; outside.mkdir()
        (outside / 'secret').write_text('preserve')
        (sdk / 'system-images').symlink_to(outside)
        with self.assertRaises(ValueError):
            sdk_cleanup_plan(sdk, '28.2.13676358')
        self.assertEqual((outside / 'secret').read_text(), 'preserve')

    def test_flutter_kotlin_and_dart_defaults_must_agree_and_match_app(self):
        kotlin = self.root / 'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt'
        kotlin.parent.mkdir(parents=True); kotlin.write_text('val ndkVersion: String = "28.2.13676358"')
        dart = self.root / 'packages/flutter_tools/lib/src/android/gradle_utils.dart'
        dart.parent.mkdir(parents=True); dart.write_text("const String ndkVersion = '28.2.13676358';")
        self.assertEqual(flutter_ndk(self.root), '28.2.13676358')
        app = self.root / 'android/app/build.gradle.kts'; app.parent.mkdir(parents=True)
        app.write_text('android { ndkVersion = flutter.ndkVersion }')
        check_app_ndk(self.root, '28.2.13676358')
        app.write_text('android { ndkVersion = "30.0.16248370" }')
        with self.assertRaises(ValueError):
            check_app_ndk(self.root, '28.2.13676358')
        dart.write_text("const String ndkVersion = '30.0.16248370';")
        with self.assertRaises(ValueError):
            flutter_ndk(self.root)

    def test_unknown_flutter_default_does_not_guess(self):
        with self.assertRaises(ValueError):
            flutter_ndk(self.root)

    def test_ci_gradle_settings_preserve_existing_jvm_and_android_settings(self):
        path = self.root / 'android/gradle.properties'; path.parent.mkdir()
        original = 'org.gradle.jvmargs=-Xmx4G\nandroid.useAndroidX=true\n# Keep this comment\n'
        path.write_text(original + 'org.gradle.parallel=true\norg.gradle.workers.max=8\norg.gradle.caching=true\n')
        configure_gradle(self.root); first = path.read_text(); configure_gradle(self.root)
        self.assertEqual(path.read_text(), first)
        self.assertTrue(first.startswith(original))
        self.assertIn('org.gradle.workers.max=2\n', first)
        self.assertNotIn('org.gradle.caching=true', first)

    def test_low_disk_fails_before_build_including_different_sdk_filesystem(self):
        usage = namedtuple('usage', 'total used free')
        def disk(path):
            return usage(100 * 1024**3, 0, (19 if path.name == 'sdk' else 40) * 1024**3)
        with redirect_stdout(StringIO()):
            check_space([self.root], 20, disk)
            with self.assertRaisesRegex(ValueError, 'at least 20 GiB'):
                check_space([self.root, self.root / 'sdk'], 20, disk)


if __name__ == '__main__':
    unittest.main(verbosity=2)
