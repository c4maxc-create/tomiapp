"""Validate optional client setup without network, accounts or secrets."""
import json
import tempfile
from pathlib import Path
from configure_firebase import configure_firebase

def main():
    with tempfile.TemporaryDirectory() as d:
        root=Path(d)
        assert configure_firebase(root,raw='') is False
        try:configure_firebase(root,raw='',required=True)
        except ValueError as e:assert 'TOMI_GOOGLE_SERVICES_JSON' in str(e)
        else:raise AssertionError('Accounts APK accepted without Firebase client configuration')
        settings=root/'android/settings.gradle.kts';settings.parent.mkdir(parents=True)
        settings.write_text('pluginManagement {}\nplugins {\n}\n')
        app=root/'android/app/build.gradle.kts';app.parent.mkdir();app.write_text('plugins {}\nandroid {}\n')
        config={'project_info':{'project_id':'test-project','project_number':'123456789'},'client':[{'client_info':{'mobilesdk_app_id':'1:123456789:android:fake','android_client_info':{'package_name':'com.tomi.tomi_app'}},'api_key':[{'current_key':'fake-client-key'}]}]}
        raw=json.dumps(config)
        persistent=root/'config/google-services.json';persistent.parent.mkdir();persistent.write_text(raw)
        assert configure_firebase(root,raw='',required=True)
        persistent.unlink()
        assert configure_firebase(root,raw)
        assert configure_firebase(root,raw)
        assert settings.read_text().count('com.google.gms.google-services')==1
        assert app.read_text().count('com.google.gms.google-services')==1
        assert json.loads((root/'android/app/google-services.json').read_text())==config
        try:configure_firebase(root,json.dumps({'type':'service_account','private_key':'NEVER-IN-APK'}))
        except ValueError:pass
        else:raise AssertionError('Accepted a server private key')
        try:configure_firebase(root,raw,require_google=True)
        except ValueError as e:assert 'Web OAuth client' in str(e)
        else:raise AssertionError('Google APK accepted with messaging-only Firebase configuration')
        config['client'][0]['oauth_client']=[{'client_type':3,'client_id':'123456789-web.apps.googleusercontent.com'}]
        assert configure_firebase(root,json.dumps(config),required=True,require_google=True)
        config['client'][0]['client_info']['android_client_info']['package_name']='other.app'
        try:configure_firebase(root,json.dumps(config))
        except ValueError:pass
        else:raise AssertionError('Accepted a wrong package')
    print('PASS: Firebase required/optional setup, persistent config path, client package, repeated setup and rejection of server credentials.')
if __name__=='__main__':main()
