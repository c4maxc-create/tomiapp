"""Compare public Google OAuth configuration without exposing Firebase client JSON."""
import json,os,re,subprocess,sys
from pathlib import Path
PACKAGE='com.tomi.tomi_app'
def web_client(config):
    clients=[c for c in config.get('client',[]) if c.get('client_info',{}).get('android_client_info',{}).get('package_name')==PACKAGE]
    ids={o.get('client_id') for c in clients for o in c.get('oauth_client',[]) if o.get('client_type')==3}
    if len(ids)!=1:return None
    value=ids.pop()
    if not isinstance(value,str) or not re.fullmatch(r'[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com',value):raise ValueError('Invalid web OAuth client configuration')
    return value

def apk_web_client(dump):
    match=re.search(r'\bstring/default_web_client_id\b',dump)
    if match is None:return None
    section=re.split(r'\n\s*resource\s',dump[match.end():],maxsplit=1)[0]
    ids=set(re.findall(r'[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com',section))
    if len(ids)!=1:raise ValueError('Google web client resource exists but its value could not be decoded')
    return ids.pop()

def main():
    apk=Path(sys.argv[1]).resolve()
    sdk=Path(os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT') or '/usr/local/lib/android/sdk')
    tools=[p for p in (sdk/'build-tools').glob('*/aapt2') if re.fullmatch(r'\d+(?:\.\d+)+',p.parent.name)]
    if not tools:raise SystemExit('Android aapt2 is required')
    aapt=max(tools,key=lambda p:tuple(map(int,p.parent.name.split('.'))))
    badging=subprocess.check_output([str(aapt),'dump','badging',str(apk)],text=True)
    if "package: name='"+PACKAGE+"'" not in badging:raise SystemExit('APK package does not match TOMI')
    dump=subprocess.check_output([str(aapt),'dump','resources',str(apk)],text=True)
    installed=apk_web_client(dump)
    raw=os.environ.get('TOMI_GOOGLE_SERVICES_JSON','')
    configured=web_client(json.loads(raw)) if raw else None
    message=f'Packaged web OAuth client present: {str(installed is not None).lower()}; updated Firebase client contains web OAuth client: {str(configured is not None).lower()}; same client: {str(installed is not None and installed==configured).lower()}'
    print('::notice title=Google OAuth configuration comparison::'+message)
    if '--require-google' in sys.argv[2:] and (installed is None or configured is None or installed!=configured):
        raise SystemExit('Packaged Google OAuth configuration is missing or differs from the updated Firebase client. APK must not be distributed.')
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'],'a') as f:f.write('\n## Google configuration\n\n'+message+'\n')
if __name__=='__main__':main()
