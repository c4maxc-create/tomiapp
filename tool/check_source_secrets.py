"""Bounded scan of tracked text files. Complements, never replaces, secret review."""
from pathlib import Path
import re,subprocess,sys
root=Path(__file__).resolve().parent.parent
patterns=[re.compile(rb'-----BEGIN (?:RSA |EC )?PRIVATE KEY-----(?:[A-Za-z0-9+/=\r\n]|\\n){64,}-----END (?:RSA |EC )?PRIVATE KEY-----'),re.compile(rb'\bgh[pousr]_[A-Za-z0-9]{30,255}\b'),re.compile(rb'\bgithub_pat_[A-Za-z0-9_]{70,255}\b'),re.compile(rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b')]
files=subprocess.check_output(['git','ls-files','-z'],cwd=root).split(b'\0')
found=[];scanned=0;skipped=0
for raw in files:
 if not raw:continue
 p=root/raw.decode()
 if not p.is_file() or p.stat().st_size>8*1024*1024:skipped+=1;continue
 data=p.read_bytes()
 if b'\0' in data[:8192]:skipped+=1;continue
 scanned+=1
 # Exact public AWS documentation example used by the signing-vector test.
 if any(m.group()!=b'AKIAIOSFODNN7EXAMPLE' for pattern in patterns for m in pattern.finditer(data)):found.append(str(p.relative_to(root)))
if found:
 print('Potential credentials found; inspect these files locally. Values are not printed:')
 print('\n'.join(found));sys.exit(1)
print(f'PASS: {scanned} tracked text files checked for common private-key and token patterns; {skipped} binary/large/missing files skipped. This does not cover every credential format or repository history.')
