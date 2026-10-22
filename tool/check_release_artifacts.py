"""Verify release APK/AAB signatures and publish only public build evidence."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def run(args):
    r = subprocess.run(args, capture_output=True, timeout=60, check=False)
    if r.returncode:
        raise ValueError('Artifact signature verification failed.')
    return r.stdout


def check(root):
    expected = os.environ.get('TOMI_SIGNING_CERT_SHA256', '').replace(':', '').upper()
    if not re.fullmatch(r'[A-F0-9]{64}', expected):
        raise ValueError('Missing pinned signing certificate fingerprint.')
    sdk = Path(os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT') or '/missing-sdk')
    candidates = sorted((sdk / 'build-tools').glob('*/apksigner'), key=lambda p: [int(x) for x in re.findall(r'\d+', p.parent.name)])
    if not candidates:
        raise ValueError('Android apksigner is unavailable.')
    files = sorted(Path(root).glob('*'))
    apks = [p for p in files if p.suffix == '.apk']
    bundles = [p for p in files if p.suffix == '.aab']
    if len(apks) != 1 or len(bundles) != 1:
        raise ValueError('Expected exactly one signed APK and one signed AAB.')
    output = run([str(candidates[-1]), 'verify', '--print-certs', str(apks[0])]).decode()
    fingerprints = re.findall(r'certificate SHA-256 digest:\s*([a-fA-F0-9]{64})', output)
    if len(fingerprints) != 1 or fingerprints[0].upper() != expected:
        raise ValueError('APK signer does not match the configured key.')
    verified = run(['jarsigner', '-J-Duser.language=en', '-verify', str(bundles[0])])
    if b'jar verified.' not in verified:
        raise ValueError('AAB JAR signature was not verified.')
    cert = run(['keytool', '-J-Duser.language=en', '-printcert', '-rfc', '-jarfile', str(bundles[0])])
    pems = re.findall(rb'-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----', cert, re.S)
    if len(pems) != 1 or hashlib.sha256(base64.b64decode(re.sub(rb'\s', b'', pems[0]))).hexdigest().upper() != expected:
        raise ValueError('AAB signer does not match the configured key.')
    evidence = {'certificateSha256': expected, 'commit': os.environ.get('GITHUB_SHA'),
                'files': {p.name: {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in [*apks, *bundles]}}
    (Path(root) / 'RELEASE_BUILD_INFO.json').write_text(json.dumps(evidence, indent=2) + '\n')


if __name__ == '__main__':
    try:
        check(Path(__file__).resolve().parent.parent / 'output')
        print('Verified APK/AAB signatures against the pinned key and wrote public artifact hashes.')
    except Exception:
        raise SystemExit('Release artifact verification failed; do not distribute these artifacts.') from None
