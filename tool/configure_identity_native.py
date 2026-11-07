"""Public OAuth client settings only. Never accept Google/Admin or Facebook app secrets."""
from pathlib import Path
import os,re,plistlib,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parent.parent
A='http://schemas.android.com/apk/res/android';T='http://schemas.android.com/tools'
def facebook(env):
    app=env.get('TOMI_FACEBOOK_APP_ID','').strip();token=env.get('TOMI_FACEBOOK_CLIENT_TOKEN','').strip()
    if bool(app)!=bool(token):raise ValueError('Configure both public Facebook App ID and client token, or neither.')
    if app and (not re.fullmatch(r'[0-9]{5,30}',app) or not re.fullmatch(r'[A-Za-z0-9_-]{10,256}',token)):raise ValueError('Invalid Facebook client configuration. Never use the App Secret.')
    return app,token
def android(root=ROOT,env=os.environ):
    app,token=facebook(env);path=root/'android/app/src/main/AndroidManifest.xml';ET.register_namespace('android',A);ET.register_namespace('tools',T);tree=ET.parse(path);manifest=tree.getroot();application=manifest.find('application')
    for name in ['AutoInitEnabled','AutoLogAppEventsEnabled','AdvertiserIDCollectionEnabled']:
        key='com.facebook.sdk.'+name;item=next((x for x in application.findall('meta-data') if x.get('{'+A+'}name')==key),None)
        if item is None:item=ET.SubElement(application,'meta-data',{'{'+A+'}name':key})
        item.set('{'+A+'}value','false')
    p=next((x for x in manifest.findall('uses-permission') if x.get('{'+A+'}name')=='com.google.android.gms.permission.AD_ID'),None)
    if p is None:p=ET.SubElement(manifest,'uses-permission',{'{'+A+'}name':'com.google.android.gms.permission.AD_ID'})
    p.set('{'+T+'}node','remove')
    if app:
        values=root/'android/app/src/main/res/values/tomi_facebook.xml';values.parent.mkdir(parents=True,exist_ok=True);resources=ET.Element('resources')
        for name,value in [('facebook_app_id',app),('facebook_client_token',token),('fb_login_protocol_scheme','fb'+app)]:ET.SubElement(resources,'string',{'name':name}).text=value
        ET.ElementTree(resources).write(values,encoding='utf-8',xml_declaration=True)
        for name,value in [('ApplicationId','@string/facebook_app_id'),('ClientToken','@string/facebook_client_token')]:
            key='com.facebook.sdk.'+name;item=next((x for x in application.findall('meta-data') if x.get('{'+A+'}name')==key),None)
            if item is None:item=ET.SubElement(application,'meta-data',{'{'+A+'}name':key})
            item.set('{'+A+'}value',value)
        if not any(x.get('{'+A+'}name')=='com.facebook.CustomTabActivity' for x in application.findall('activity')):
            activity=ET.SubElement(application,'activity',{'{'+A+'}name':'com.facebook.CustomTabActivity','{'+A+'}exported':'true'});f=ET.SubElement(activity,'intent-filter');ET.SubElement(f,'action',{'{'+A+'}name':'android.intent.action.VIEW'})
            for category in ['android.intent.category.DEFAULT','android.intent.category.BROWSABLE']:ET.SubElement(f,'category',{'{'+A+'}name':category})
            ET.SubElement(f,'data',{'{'+A+'}scheme':'@string/fb_login_protocol_scheme'})
    tree.write(path,encoding='utf-8',xml_declaration=True)
def ios(root=ROOT,env=os.environ):
    app,token=facebook(env);runner=root/'ios/Runner';path=runner/'Info.plist';data=plistlib.loads(path.read_bytes());data.update({'FacebookAutoInitEnabled':False,'FacebookAutoLogAppEventsEnabled':False,'FacebookAdvertiserIDCollectionEnabled':False})
    # Custom Rust encryption requires the owner's App Store export-compliance determination.
    data.pop('ITSAppUsesNonExemptEncryption',None)
    schemes=data.setdefault('CFBundleURLTypes',[])
    def add(name,scheme):
        if not any(scheme in x.get('CFBundleURLSchemes',[]) for x in schemes):schemes.append({'CFBundleURLName':name,'CFBundleURLSchemes':[scheme],'CFBundleTypeRole':'Editor'})
    firebase=runner/'GoogleService-Info.plist'
    if firebase.exists():
        config=plistlib.loads(firebase.read_bytes());reverse=config.get('REVERSED_CLIENT_ID')
        if reverse:
            if not isinstance(reverse,str) or not re.fullmatch(r'com\.googleusercontent\.apps\.[A-Za-z0-9.-]+',reverse):raise ValueError('Invalid reversed OAuth client ID')
            add('com.tomi.google',reverse)
        client=config.get('CLIENT_ID')
        if client:data['GIDClientID']=client
    if app:data.update({'FacebookAppID':app,'FacebookClientToken':token,'FacebookDisplayName':'TOMI'});add('com.tomi.facebook','fb'+app)
    data['LSApplicationQueriesSchemes']=list(dict.fromkeys(data.get('LSApplicationQueriesSchemes',[])+['fbapi','fb-messenger-share-api','fbauth2','fbshareextension']))
    path.write_bytes(plistlib.dumps(data,sort_keys=False))
    entitlements=runner/'Runner.entitlements'
    values=plistlib.loads(entitlements.read_bytes()) if entitlements.exists() else {}
    values['com.apple.developer.applesignin']=['Default']
    entitlements.write_bytes(plistlib.dumps(values,sort_keys=False))
    project=root/'ios/Runner.xcodeproj/project.pbxproj'
    if project.exists():
        text=project.read_text()
        text=re.sub(r'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\s*', '', text)
        text=text.replace('PRODUCT_BUNDLE_IDENTIFIER = com.tomi.tomiapp;', 'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.tomi.tomiapp;')
        project.write_text(text)
if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('platform',choices=['android','ios']);a=p.parse_args();globals()[a.platform]();print('Public OAuth client settings configured; no values printed.')
