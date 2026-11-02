"""Exercise the workflow's real shell with a local gh double; never publish."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = yaml.safe_load((ROOT / '.github/workflows/tomi-android.yml').read_text())
STEP = next(s for s in WORKFLOW['jobs']['android']['steps']
            if s['name'] == 'Publish verified TOMI downloads to Releases')
STUB = '''#!/usr/bin/env python3
import hashlib,json,os,sys
from pathlib import Path
a=sys.argv[1:]
with open(os.environ['GH_CALL_LOG'],'a') as f:f.write(json.dumps(a)+'\\n')
mode=os.environ.get('FIXTURE_MODE','ok')
if a[:2]==['release','create']:
 if mode=='create-failure':sys.exit(7)
 assert '--draft' in a and '--prerelease' in a and '--latest=false' in a
 assert a[a.index('--target')+1]==os.environ['GITHUB_SHA']
 assert a[a.index('--repo')+1]=='fixture/tomi'
 allowed={'output/TOMI-1.7.0-beta.1.apk','output/SHA256SUMS.txt'}
 if os.environ['TOMI_BUILD_DISTRIBUTION']=='signed_beta':allowed|={'output/TOMI-1.7.0-beta.1.aab','output/RELEASE_BUILD_INFO.json'}
 assert {x for x in a if x.startswith('output/')}==allowed
 sys.exit(0)
if a[:2]==['release','view']:
 if mode=='view-failure':sys.exit(11)
 print('bad' if mode=='invalid-release-id' else '' if mode=='empty-release-id' else '1234')
 sys.exit(0)
if a[0]=='api':
 if mode=='api-failure':sys.exit(8)
 tag='tomi-build-'+os.environ['GITHUB_RUN_ID']+'-'+os.environ['GITHUB_RUN_ATTEMPT']
 assert a[1]=='repos/fixture/tomi/releases/1234'
 names=['TOMI-1.7.0-beta.1.apk','SHA256SUMS.txt']
 if os.environ['TOMI_BUILD_DISTRIBUTION']=='signed_beta':names+=['TOMI-1.7.0-beta.1.aab','RELEASE_BUILD_INFO.json']
 assets=[]
 for n in names:
  p=Path('output')/n
  assets.append(dict(name=n,size=p.stat().st_size,state='uploaded',digest='sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()))
 r=dict(draft=True,prerelease=True,tag_name=tag,target_commitish=os.environ['GITHUB_SHA'],assets=assets)
 if mode=='missing-asset':assets.pop()
 if mode=='duplicate-asset':assets.append(assets[0])
 if mode=='wrong-size':assets[0]['size']+=1
 if mode=='wrong-digest':assets[0]['digest']='sha256:'+'0'*64
 if mode=='unfinished-asset':assets[0]['state']='new'
 if mode=='wrong-commit':r['target_commitish']='b'*40
 if mode=='wrong-tag':r['tag_name']='other'
 if mode=='not-draft':r['draft']=False
 if mode=='not-prerelease':r['prerelease']=False
 if mode=='no-digest':
  for x in assets:x.pop('digest')
 print(json.dumps(r));sys.exit(0)
if a[:2]==['release','edit']:
 assert '--draft=false' in a and '--prerelease' in a and '--latest=false' in a
 sys.exit(9 if mode=='publish-failure' else 0)
sys.exit(10)
'''


class DeliveryTest(unittest.TestCase):
    def exercise(self, mode='ok', distribution='debug', expected=True):
        with tempfile.TemporaryDirectory(prefix='tomi-delivery-fixture-') as directory:
            root = Path(directory)
            output = root / 'output'; output.mkdir()
            apk = output / 'TOMI-1.7.0-beta.1.apk'
            apk.write_bytes(b'fixture bytes, not an APK')
            if distribution == 'signed_beta':
                (output / 'TOMI-1.7.0-beta.1.aab').write_bytes(b'fixture bundle')
                (output / 'RELEASE_BUILD_INFO.json').write_text('{}')
            (output / 'unrelated-private-file.json').write_text('never upload')
            if mode == 'missing-apk': apk.unlink()
            if mode == 'empty-apk': apk.write_bytes(b'')
            if mode == 'symlink-apk':
                apk.unlink(); target=root/'other'; target.write_bytes(b'preserve')
                apk.symlink_to(target)
            if mode == 'oversized-apk':
                with apk.open('wb') as stream: stream.truncate(2147483648)
            if mode == 'missing-aab': (output / 'TOMI-1.7.0-beta.1.aab').unlink()
            if mode == 'missing-evidence': (output / 'RELEASE_BUILD_INFO.json').unlink()
            binary=root/'bin'; binary.mkdir(); gh=binary/'gh'; gh.write_text(STUB); gh.chmod(0o700)
            script=root/'publish.sh'; script.write_text(STEP['run'])
            calls=root/'calls.jsonl'; summary=root/'summary.md'
            env=dict(os.environ,PATH=str(binary)+os.pathsep+os.environ['PATH'],
                     GH_TOKEN='test-only',GH_CALL_LOG=str(calls),FIXTURE_MODE=mode,
                     GITHUB_RUN_ID='42',GITHUB_RUN_ATTEMPT='3',GITHUB_RUN_NUMBER='42',
                     GITHUB_SHA='a'*40,GITHUB_REPOSITORY='fixture/tomi',RUNNER_TEMP=str(root),
                     GITHUB_STEP_SUMMARY=str(summary),TOMI_BUILD_DISTRIBUTION=distribution)
            result=subprocess.run(['bash',str(script)],cwd=root,env=env,capture_output=True,text=True,timeout=20)
            logged=[json.loads(x) for x in calls.read_text().splitlines()] if calls.exists() else []
            if expected:
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual([x[:2] for x in logged],[['release','create'],['release','view'],['api','repos/fixture/tomi/releases/1234'],['release','edit']])
                self.assertIn('https://github.com/fixture/tomi/releases/tag/tomi-build-42-3',summary.read_text())
                sums=(output/'SHA256SUMS.txt').read_text()
                self.assertNotIn('unrelated-private-file',sums)
                self.assertIn(hashlib.sha256(apk.read_bytes()).hexdigest(),sums)
            else:
                self.assertNotEqual(result.returncode,0)
                self.assertFalse(summary.exists(),'A failed delivery must not advertise downloads')
                if mode != 'publish-failure':
                    self.assertFalse(any(x[:2]==['release','edit'] for x in logged),'Bad upload must remain unpublished')
                if mode in ['missing-apk','empty-apk','symlink-apk','oversized-apk','missing-aab','missing-evidence','bad-mode']:
                    self.assertEqual(logged,[],'Invalid local build must fail before remote writes')

    def test_debug_download_and_hash_manifest(self): self.exercise()
    def test_signed_bundle_and_signature_evidence_are_included(self): self.exercise(distribution='signed_beta')
    def test_older_api_without_digest_still_checks_sizes_and_names(self): self.exercise(mode='no-digest')
    def test_workflow_keeps_tests_gates_and_scopes_permissions(self):
        self.assertEqual(WORKFLOW['permissions'],{'contents':'read'})
        self.assertEqual(WORKFLOW['jobs']['android']['permissions'],{'contents':'write'})
        self.assertEqual(WORKFLOW['jobs']['android']['needs'],'accounts-api')
        self.assertNotIn('continue-on-error',STEP)
        self.assertNotIn('if',STEP)
        self.assertNotIn('actions/upload-artifact',str(WORKFLOW))
        self.assertEqual(STEP['env']['GH_TOKEN'],'${{ github.token }}')
        steps=WORKFLOW['jobs']['android']['steps']
        self.assertLess(next(i for i,s in enumerate(steps) if s['name']=='Verify release signatures and artifact hashes'),steps.index(STEP))
        self.assertEqual(WORKFLOW['jobs']['accounts-api']['permissions'] if 'permissions' in WORKFLOW['jobs']['accounts-api'] else WORKFLOW['permissions'],{'contents':'read'})


def failure_case(mode, distribution='debug'):
    def run(self): self.exercise(mode=mode,distribution=distribution,expected=False)
    return run


for mode in ['create-failure','view-failure','invalid-release-id','empty-release-id','api-failure','missing-asset','duplicate-asset','wrong-size','wrong-digest',
             'unfinished-asset','wrong-commit','wrong-tag','not-draft','not-prerelease','publish-failure',
             'missing-apk','empty-apk','symlink-apk','oversized-apk']:
    setattr(DeliveryTest,'test_rejects_'+mode.replace('-','_'),failure_case(mode))
for mode in ['missing-aab','missing-evidence']:
    setattr(DeliveryTest,'test_rejects_'+mode.replace('-','_'),failure_case(mode,'signed_beta'))
setattr(DeliveryTest,'test_rejects_bad_mode',failure_case('bad-mode','invalid'))

if __name__ == '__main__': unittest.main(verbosity=2)
