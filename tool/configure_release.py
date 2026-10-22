"""Prepare explicit Android release signing; never generate a production key."""
import base64
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
START, END = '// TOMI_SIGNING_START', '// TOMI_SIGNING_END'
BLOCK = '''// TOMI_SIGNING_START
val tomiReleaseRequested = System.getenv("TOMI_RELEASE_BUILD") == "1"
if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) } && !tomiReleaseRequested) {
    error("TOMI release requires explicit verified signing configuration")
}
if (tomiReleaseRequested) {
    android {
        signingConfigs {
            create("tomiRelease") {
                storeFile = file(System.getenv("TOMI_SIGNING_FILE") ?: error("Missing TOMI signing file"))
                storePassword = System.getenv("TOMI_ANDROID_STORE_PASSWORD") ?: error("Missing store password")
                keyAlias = System.getenv("TOMI_ANDROID_KEY_ALIAS") ?: error("Missing key alias")
                keyPassword = System.getenv("TOMI_ANDROID_KEY_PASSWORD") ?: error("Missing key password")
            }
        }
        buildTypes {
            getByName("release") {
                signingConfig = signingConfigs.getByName("tomiRelease")
                isDebuggable = false
            }
        }
    }
}
// TOMI_SIGNING_END
'''

def command(args, env):
    result = subprocess.run(['keytool', '-J-Duser.language=en', '-J-Duser.country=US', *args],
                            env=env, capture_output=True, timeout=20, check=False)
    if result.returncode:
        raise ValueError('Signing key verification failed; no secret output was printed.')
    return result.stdout


def configure_release(root=ROOT, env=None):
    env = dict(os.environ if env is None else env)
    if env.get('TOMI_RELEASE_BUILD') != '1':
        return {'configured': False}
    required = ['TOMI_ANDROID_KEYSTORE_BASE64', 'TOMI_ANDROID_STORE_PASSWORD',
                'TOMI_ANDROID_KEY_ALIAS', 'TOMI_ANDROID_KEY_PASSWORD', 'TOMI_SIGNING_CERT_SHA256']
    if any(not env.get(key) for key in required):
        raise ValueError('Release signing requires every documented signing secret and certificate fingerprint.')
    alias = env['TOMI_ANDROID_KEY_ALIAS']
    if not re.fullmatch(r'[A-Za-z0-9_.-]{1,80}', alias):
        raise ValueError('Invalid signing alias.')
    fingerprint = env['TOMI_SIGNING_CERT_SHA256'].replace(':', '').upper()
    if not re.fullmatch(r'[A-F0-9]{64}', fingerprint):
        raise ValueError('A SHA256 signing certificate fingerprint is required.')
    encoded = ''.join(env['TOMI_ANDROID_KEYSTORE_BASE64'].split())
    if len(encoded) > 1500000:
        raise ValueError('Signing keystore is too large.')
    try:
        content = base64.b64decode(encoded, validate=True)
    except ValueError:
        raise ValueError('Invalid signing keystore encoding.') from None
    if not 32 <= len(content) <= 1024 * 1024:
        raise ValueError('Invalid signing keystore size.')
    gradle = Path(root) / 'android/app/build.gradle.kts'
    if not gradle.is_file():
        raise ValueError('Generate the Kotlin Android scaffold before release signing.')
    directory = Path(tempfile.mkdtemp(prefix='tomi-sign-', dir=env.get('RUNNER_TEMP')))
    keyfile = directory / 'upload.jks'
    try:
        keyfile.write_bytes(content)
        keyfile.chmod(0o600)
        args = ['-keystore', str(keyfile), '-alias', alias, '-storepass:env', 'TOMI_ANDROID_STORE_PASSWORD']
        if b'PrivateKeyEntry' not in command(['-list', '-v', *args], env):
            raise ValueError('The selected alias is not a private signing key.')
        certificate = command(['-exportcert', *args], env)
        if hashlib.sha256(certificate).hexdigest().upper() != fingerprint:
            raise ValueError('Signing certificate does not match the pinned SHA256 fingerprint.')
        # Reading the private key for a CSR verifies the key password too. The CSR
        # is never sent, stored, printed or used to issue a certificate.
        command(['-certreq', *args, '-keypass:env', 'TOMI_ANDROID_KEY_PASSWORD'], env)
        text = gradle.read_text()
        text = re.sub(re.escape(START) + r'.*?' + re.escape(END) + r'\n?', '', text, flags=re.S)
        text = re.sub(r'^\s*signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)\s*$', '', text, flags=re.M)
        gradle.write_text(text.rstrip() + '\n\n' + BLOCK)
        if env.get('GITHUB_ENV'):
            with open(env['GITHUB_ENV'], 'a', encoding='utf-8') as output:
                output.write('TOMI_SIGNING_FILE=' + str(keyfile) + '\n')
        return {'configured': True, 'keyfile': str(keyfile), 'certificateSha256': fingerprint}
    except BaseException:
        shutil.rmtree(directory, ignore_errors=True)
        raise


def cleanup(env=None):
    env = os.environ if env is None else env
    value = env.get('TOMI_SIGNING_FILE')
    if not value:
        return
    path = Path(value).resolve()
    if path.name != 'upload.jks' or not path.parent.name.startswith('tomi-sign-'):
        raise ValueError('Refused to remove a non-TOMI signing path.')
    if env.get('RUNNER_TEMP') and path.parent.parent != Path(env['RUNNER_TEMP']).resolve():
        raise ValueError('Signing cleanup must stay in the runner temporary directory.')
    shutil.rmtree(path.parent)


if __name__ == '__main__':
    import sys
    try:
        if sys.argv[1:] == ['--cleanup']:
            cleanup()
            print('Removed the temporary signing material.')
        elif sys.argv[1:]:
            raise ValueError('Unknown release signing option.')
        else:
            result = configure_release()
            print('Verified private signing key and configured release Gradle.' if result['configured'] else 'Debug build: release signing is not configured.')
    except Exception:
        raise SystemExit('Release signing failed. Check the documented secrets, fingerprint and scaffold; no secret output was printed.') from None
