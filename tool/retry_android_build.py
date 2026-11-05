"""Retry transient Gradle artifact download failures, never compiler/config errors.

Flutter retries a download failure after 100 ms. A gateway 504 needs a longer
pause. Keep the exact build command and exit status, with at most three runs.
"""
import re
import subprocess
import sys
import time

TRANSIENT = re.compile(
    r'received status code (?:408|429|500|502|503|504)\b|'
    r'\b(?:read|connect|connection) timed out\b|'
    r'\bconnection reset\b|temporary failure in name resolution|'
    r'\b(?:bad gateway|gateway time-out|gateway timeout|service unavailable)\b',
    re.IGNORECASE,
)
# An unrelated warning must not turn a deterministic build failure into a retry.
COMPILER_ERROR = re.compile(
    r'^\s*(?:e: (?:file:|/)|error: |.*?\.dart:\d+:\d+: Error:|'
    r'.*?\.java:\d+: error:)|'
    r'invalid keystore format|password was incorrect|failed to read key',
    re.IGNORECASE | re.MULTILINE,
)
PERMANENT_HTTP = re.compile(r'received status code (?:400|401|403|404|405|410|422)\b', re.I)
NETWORK_CONTEXT = re.compile(r'could not (?:get|head|download|resolve)|downloading artifacts|https?://', re.I)


def transient_download(output):
    return bool(TRANSIENT.search(output) and NETWORK_CONTEXT.search(output) and not COMPILER_ERROR.search(output) and not PERMANENT_HTTP.search(output))


def execute(command):
    lines = []
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True, encoding='utf-8', errors='replace', bufsize=1) as child:
        for line in child.stdout:
            print(line, end='', flush=True)
            lines.append(line)
        return child.wait(), ''.join(lines)


def build(command, run=execute, pause=time.sleep):
    if not command:
        raise ValueError('Supply the exact Flutter build command after --')
    for attempt in range(3):
        code, output = run(command)
        if code == 0 or not transient_download(output) or attempt == 2:
            return code
        delay = (30, 60)[attempt]
        print(f'Transient artifact download failure. Retrying build {attempt+2}/3 in {delay}s; downloaded artifacts are retained.', flush=True)
        pause(delay)
    raise AssertionError('Unreachable')


if __name__ == '__main__':
    args = sys.argv[1:]
    if args[:1] == ['--']:
        args = args[1:]
    if not args:
        raise SystemExit('Usage: python3 tool/retry_android_build.py -- flutter build ...')
    raise SystemExit(build(args))
