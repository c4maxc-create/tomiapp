"""Bounded diagnostics; never dump host configuration or credentials."""
from pathlib import Path
import re
p=Path('build/tomi-android-native.log')
if p.exists():
    lines=p.read_text(errors='replace').splitlines();selected=[]
    for i,line in enumerate(lines):
        if re.search(r'(error:|^e: |What went wrong|Execution failed|Could not|FAILURE:|Incorrect package|namespace)',line,re.I):selected.append(' | '.join(x.strip() for x in lines[i:i+3]))
    for line in selected[-12:]:print('::error title=Android native compiler diagnostic::'+line[:800].replace('%','%25').replace('\r','%0D').replace('\n','%0A'))
