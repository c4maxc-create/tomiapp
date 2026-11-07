"""Verify a built APK and report public signer hashes; never read a keystore."""
from pathlib import Path
import hashlib,os,re,subprocess,sys

def fingerprints(output):
    result={}
    for label,length in [('SHA-1',40),('SHA-256',64)]:
        matches=re.findall(r'^(?:Signer #1 |V[1-4](?:\.[0-9]+)? Signer: )certificate '+label+r' digest: ([0-9a-fA-F]{'+str(length)+r'})\s*$',output,re.M)
        matches=list(set(matches))
        if len(matches)!=1:raise ValueError('Expected exactly one signer '+label+' fingerprint')
        result[label]=':'.join(matches[0][i:i+2].upper() for i in range(0,length,2))
    counts=re.findall(r'^Number of signers: ([0-9]+)\s*$',output,re.M)
    if counts and any(n!='1' for n in counts):raise ValueError('Multiple signers require manual review')
    if re.search(r'^Signer #[2-9][0-9]* certificate ',output,re.M):raise ValueError('Multiple signers require manual review')
    return result

def main():
    apk=Path(sys.argv[1]).resolve()
    if not apk.is_file():raise SystemExit('APK missing')
    sdk=Path(os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT') or '/usr/local/lib/android/sdk')
    candidates=[p for p in (sdk/'build-tools').glob('*/apksigner') if re.fullmatch(r'\d+(?:\.\d+)+',p.parent.name)]
    if not candidates:raise SystemExit('Android build tools with apksigner are required')
    signer=max(candidates,key=lambda p:tuple(map(int,p.parent.name.split('.'))))
    verified=subprocess.run([str(signer),'verify','--verbose','--print-certs',str(apk)],capture_output=True,text=True)
    try:
        if verified.returncode:raise ValueError('apksigner did not verify the APK')
        values=fingerprints(verified.stdout)
    except ValueError as error:
        # apksigner reads only the APK's public signature, never a keystore or secret.
        for line in (verified.stdout+'\n'+verified.stderr).splitlines()[-24:]:
            safe=line[:800].replace('%','%25').replace('\r','%0D').replace('\n','%0A')
            print('::warning title=Public APK certificate diagnostic::'+safe)
        raise SystemExit(str(error)) from None
    sha=hashlib.file_digest(apk.open('rb'),'sha256').hexdigest()
    report='# Verified APK certificate\n\nPublic certificate fingerprints for this exact APK. No private key was read.\n\n'
    for label,value in values.items():
        print(f'::notice title=Firebase {label} fingerprint::{value}')
        report+=f'**{label}**\n\n```text\n{value}\n```\n\n'
    report+='**APK file SHA-256** (file checksum, not the Firebase certificate fingerprint)\n\n```text\n'+sha+'\n```\n'
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'],'a') as f:f.write(report)
    Path('apk-certificate-report.md').write_text(report)
if __name__=='__main__':main()
