"""Compile the actual C# UI and package its static assets into the Android APK.

No source-only placeholder: fail if WebAssembly or the native bridge is absent.
"""
from pathlib import Path
import argparse,json,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parent.parent

def package(source:Path,target:Path):
    if not (source/'native-bridge.js').is_file() or not (source/'_framework/Tomi.BlazorPreview.wasm').is_file():
        raise RuntimeError('Publish output is missing the C# UI or native bridge')
    if target.exists():shutil.rmtree(target)
    target.mkdir(parents=True)
    names=[]
    for p in sorted(source.rglob('*')):
        if not p.is_file() or p.suffix in ('.br','.gz') or p.name.startswith('.'):continue
        rel=p.relative_to(source)
        if len(rel.parts)>2:raise RuntimeError(f'Add nested Flutter asset directory before packaging: {rel}')
        dest=target/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,dest);names.append(rel.as_posix())
    (target/'asset-index.json').write_text(json.dumps(names))
    print(f'Packaged {len(names)} C# runtime/assets into {target.relative_to(ROOT)}')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--dotnet',default=shutil.which('dotnet') or 'dotnet');parser.add_argument('--published',type=Path);args=parser.parse_args()
    target=ROOT/'assets/tomi_games'
    if args.published:package(args.published,target)
    else:
        with tempfile.TemporaryDirectory(prefix='tomi-csharp-') as temp:
            subprocess.run([args.dotnet,'publish',str(ROOT/'previews/Tomi.BlazorPreview'),'-c','Release','-o',temp],check=True)
            package(Path(temp)/'wwwroot',target)
