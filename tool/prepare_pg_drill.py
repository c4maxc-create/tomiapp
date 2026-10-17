"""Create CI-only wrappers for the already-running PostgreSQL17 test container."""
import os
import re
import tempfile
from pathlib import Path

container = os.environ.get('TOMI_PG_CONTAINER', '')
if os.environ.get('CI') != 'true' or not re.fullmatch(r'[a-f0-9]{12,64}', container):
    raise SystemExit('This helper is restricted to the ephemeral GitHub CI container.')
directory = Path(tempfile.mkdtemp(prefix='tomi-pg-ci12-'))
values = {}
for binary in ['pg_dump', 'pg_restore']:
    script = directory / binary
    # The password below is the public, ephemeral CI fixture password from YAML.
    # Production credentials and passfiles are never accepted by this wrapper.
    script.write_text('#!/bin/sh\nset -eu\nexec docker exec -i -e PGHOST=127.0.0.1 -e PGPORT=5432 -e PGDATABASE -e PGUSER '
                      '-e PGPASSWORD=ephemeral_ci_password ' + container + ' ' + binary + ' "$@"\n')
    script.chmod(0o700)
    values['TOMI_PG_' + ('DUMP' if binary == 'pg_dump' else 'RESTORE') + '_BIN'] = str(script)
with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output:
    for name, value in values.items():
        output.write(name + '=' + value + '\n')
print('Prepared PostgreSQL17 client wrappers for the isolated CI restore drill.')
