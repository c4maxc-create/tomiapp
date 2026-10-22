"""Read-only deployment gates before a signed beta build; no store publishing."""
import json
import os
from pathlib import Path
import urllib.request
from urllib.parse import urlsplit


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def check(env=None, fetch=None):
    env = os.environ if env is None else env
    if env.get('TOMI_BETA_DEVICE_ACCEPTED') != '1':
        raise ValueError('Record two-phone beta acceptance before requesting the signed build.')
    base = env.get('TOMI_API_URL', '').rstrip('/')
    u = urlsplit(base)
    if u.scheme != 'https' or not u.hostname or u.username or u.password or u.query or u.fragment:
        raise ValueError('A public HTTPS API URL is required.')
    def get(path):
        if fetch:
            return fetch(base + path)
        opener = urllib.request.build_opener(NoRedirect)
        with opener.open(base + path, timeout=20) as response:
            content = response.read(1024 * 1024 + 1)
            if response.status != 200 or len(content) > 1024 * 1024:
                raise ValueError('Invalid public resource.')
            return content
    health = json.loads(get('/health'))
    documents = json.loads(get('/v1/privacy/documents'))
    version = next(line.split(':', 1)[1].strip().split('+')[0] for line in
                   (Path(__file__).resolve().parent.parent / 'pubspec.yaml').read_text().splitlines() if line.startswith('version:'))
    if health.get('status') != 'ok' or health.get('version') != version:
        raise ValueError('Deploy the matching beta API before building the signed client.')
    if documents.get('publicationReady') is not True or not documents.get('operatorName') or not documents.get('supportEmail'):
        raise ValueError('Public operator contact and backup retention must be configured on the API.')
    if {d.get('id') for d in documents.get('documents', [])} != {'privacy', 'terms', 'community', 'deletion'}:
        raise ValueError('Public policy documents are incomplete.')
    for path in ['/privacy', '/terms', '/community-guidelines', '/account/delete']:
        body = get(path)
        if b'TOMI' not in body or b'<html' not in body:
            raise ValueError('A required public policy/deletion page failed.')
    return version


if __name__ == '__main__':
    try:
        print('Verified public beta API/documents and recorded device gate for ' + check() + '.')
    except Exception:
        raise SystemExit('Release readiness failed: check the deployed API version, public contact/retention pages and recorded phone acceptance. No private response was printed.') from None
