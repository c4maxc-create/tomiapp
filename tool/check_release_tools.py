"""Local release safeguards with an isolated disposable test key, never an APK."""
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from configure_release import configure_release, cleanup
from check_release_readiness import check


class ReleaseToolsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='tomi-release-test-')
        cls.root = Path(cls.temp.name)
        cls.key = cls.root / 'fixture.jks'
        cls.env = dict(os.environ, TOMI_TEST_KEYPASS='test-only-fixture-password')
        subprocess.run(['keytool', '-genkeypair', '-alias', 'fixture', '-keystore', str(cls.key),
                        '-storetype', 'JKS', '-storepass:env', 'TOMI_TEST_KEYPASS',
                        '-keypass:env', 'TOMI_TEST_KEYPASS', '-keyalg', 'RSA', '-keysize', '2048',
                        '-validity', '1', '-dname', 'CN=TOMI disposable test only', '-noprompt'],
                       env=cls.env, capture_output=True, check=True, timeout=30)
        cert = subprocess.run(['keytool', '-exportcert', '-alias', 'fixture', '-keystore', str(cls.key),
                               '-storepass:env', 'TOMI_TEST_KEYPASS'], env=cls.env,
                              capture_output=True, check=True, timeout=15).stdout
        cls.fingerprint = hashlib.sha256(cert).hexdigest().upper()

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def setUp(self):
        self.case = tempfile.TemporaryDirectory(dir=self.root)
        self.project = Path(self.case.name) / 'project'
        self.gradle = self.project / 'android/app/build.gradle.kts'
        self.gradle.parent.mkdir(parents=True)
        self.original = 'plugins {}\nandroid { buildTypes { release {\n signingConfig = signingConfigs.getByName("debug")\n} } }\n'
        self.gradle.write_text(self.original)
        self.signenv = dict(self.env, TOMI_RELEASE_BUILD='1',
                            TOMI_ANDROID_KEYSTORE_BASE64=base64.b64encode(self.key.read_bytes()).decode(),
                            TOMI_ANDROID_STORE_PASSWORD='test-only-fixture-password',
                            TOMI_ANDROID_KEY_PASSWORD='test-only-fixture-password',
                            TOMI_ANDROID_KEY_ALIAS='fixture', TOMI_SIGNING_CERT_SHA256=self.fingerprint,
                            RUNNER_TEMP=self.case.name, GITHUB_ENV=str(Path(self.case.name) / 'environment'))

    def tearDown(self):
        self.case.cleanup()

    def test_debug_does_not_touch_signing_or_require_secrets(self):
        self.assertEqual(configure_release(self.project, {}), {'configured': False})
        self.assertEqual(self.gradle.read_text(), self.original)

    def test_missing_or_invalid_release_inputs_fail_closed(self):
        with self.assertRaises(ValueError):
            configure_release(self.project, {'TOMI_RELEASE_BUILD': '1'})
        for changes in [{'TOMI_ANDROID_KEYSTORE_BASE64': 'not base64'}, {'TOMI_ANDROID_KEY_ALIAS': '../bad'}, {'TOMI_SIGNING_CERT_SHA256': 'bad'}]:
            with self.assertRaises(ValueError):
                configure_release(self.project, dict(self.signenv, **changes))
        self.assertEqual(self.gradle.read_text(), self.original)

    def test_real_test_key_is_verified_private_idempotent_and_removed(self):
        first = configure_release(self.project, self.signenv)
        path = Path(first['keyfile'])
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        text = self.gradle.read_text()
        self.assertNotIn('getByName("debug")', text)
        self.assertIn('isDebuggable = false', text)
        self.assertNotIn(self.signenv['TOMI_ANDROID_STORE_PASSWORD'], text)
        self.assertNotIn(self.signenv['TOMI_ANDROID_KEYSTORE_BASE64'], text)
        second = configure_release(self.project, self.signenv)
        self.assertEqual(text, self.gradle.read_text())
        self.assertEqual(text.count('// TOMI_SIGNING_START'), 1)
        self.assertNotIn('PASSWORD', Path(self.signenv['GITHUB_ENV']).read_text())
        for record in [first, second]:
            cleanup(dict(self.signenv, TOMI_SIGNING_FILE=record['keyfile']))
            self.assertFalse(Path(record['keyfile']).exists())

    def test_wrong_certificate_cleans_private_material_before_gradle_change(self):
        with self.assertRaises(ValueError):
            configure_release(self.project, dict(self.signenv, TOMI_SIGNING_CERT_SHA256='0' * 64))
        self.assertEqual(self.gradle.read_text(), self.original)
        self.assertEqual(list(Path(self.case.name).glob('tomi-sign-*')), [])

    def test_wrong_private_key_password_fails_without_fallback(self):
        with self.assertRaises(ValueError):
            configure_release(self.project, dict(self.signenv, TOMI_ANDROID_KEY_PASSWORD='wrong-test-password'))
        self.assertEqual(self.gradle.read_text(), self.original)
        with self.assertRaises(ValueError):
            cleanup({'TOMI_SIGNING_FILE': str(self.key), 'RUNNER_TEMP': self.case.name})

    def test_release_readiness_requires_matching_deployment_contact_and_device_gate(self):
        version = next(x.split(':', 1)[1].strip().split('+')[0] for x in
                       (Path(__file__).resolve().parent.parent / 'pubspec.yaml').read_text().splitlines() if x.startswith('version:'))
        data = {'publicationReady': True, 'operatorName': 'Test operator', 'supportEmail': 'test@example.test',
                'documents': [{'id': x} for x in ['privacy', 'terms', 'community', 'deletion']]}
        health = {'status': 'ok', 'version': version}
        def fetch(url):
            if url.endswith('/health'):
                return json.dumps(health).encode()
            if url.endswith('/v1/privacy/documents'):
                return json.dumps(data).encode()
            return b'<html>TOMI</html>'
        env = {'TOMI_API_URL': 'https://api.example.test', 'TOMI_BETA_DEVICE_ACCEPTED': '1'}
        self.assertEqual(check(env, fetch), version)
        for bad in [{'TOMI_BETA_DEVICE_ACCEPTED': '0'}, {'TOMI_API_URL': 'http://unsafe.test'}]:
            with self.assertRaises(ValueError):
                check(dict(env, **bad), fetch)
        health['version'] = '0.12.0'
        with self.assertRaises(ValueError):
            check(env, fetch)
        health['version'] = version
        data['publicationReady'] = False
        with self.assertRaises(ValueError):
            check(env, fetch)


if __name__ == '__main__':
    unittest.main(verbosity=2)
