"""Optional Android Firebase client configuration; never accept a server key."""
import json
import os
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
PACKAGE='com.tomi.tomi_app'

def configure_firebase(root=ROOT, raw=None):
    config=root/'android/app/google-services.json'
    raw=os.environ.get('TOMI_GOOGLE_SERVICES_JSON','') if raw is None else raw
    if not raw and config.is_file():
        raw=config.read_text()
    if not raw:
        return False
    if len(raw.encode())>131072:
        raise ValueError('Firebase client configuration is too large.')
    data=json.loads(raw)
    if 'private_key' in data or data.get('type')=='service_account':
        raise ValueError('Use google-services.json; a service-account private key must only be stored on the server.')
    project=data.get('project_info',{})
    clients=[c for c in data.get('client',[]) if c.get('client_info',{}).get('android_client_info',{}).get('package_name')==PACKAGE]
    if not clients or not project.get('project_id') or not str(project.get('project_number','')).isdigit():
        raise ValueError('Firebase Android package must be com.tomi.tomi_app.')
    if not clients[0].get('client_info',{}).get('mobilesdk_app_id') or not clients[0].get('api_key',[{}])[0].get('current_key'):
        raise ValueError('Firebase client app ID or API key is missing.')
    settings=root/'android/settings.gradle.kts'
    app=root/'android/app/build.gradle.kts'
    if not settings.exists() or not app.exists():
        raise ValueError('Generate the Android scaffold before configuring Firebase.')
    source=settings.read_text()
    if 'com.google.gms.google-services' not in source:
        source,count=re.subn(r'(?m)^plugins\s*\{','plugins {\n    id("com.google.gms.google-services") version "4.5.0" apply false',source,count=1)
        if count!=1:
            raise ValueError('Android settings plugin block was not found.')
        settings.write_text(source)
    source=app.read_text()
    if 'com.google.gms.google-services' not in source:
        app.write_text(source+'\napply(plugin = "com.google.gms.google-services")\n')
    config.parent.mkdir(parents=True,exist_ok=True)
    config.write_text(json.dumps(data,ensure_ascii=False))
    return True

if __name__=='__main__':
    enabled=configure_firebase()
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'],'a') as f:
            f.write('TOMI_PUSH_CONFIGURED='+str(enabled).lower()+'\n')
    print('Firebase push client configured.' if enabled else 'Building with push disabled; audio and avatars remain available.')
