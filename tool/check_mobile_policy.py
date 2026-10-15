"""Run native presentation policy on the JDK, without an Android emulator."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='tomi-mobile-policy-') as directory:
    subprocess.run(['java', 'com.sun.tools.javac.Main', '-encoding', 'UTF-8', '-d', directory,
                    str(root/'native/mobile/MobilePolicy.java'),
                    str(root/'native/test/MobilePolicyTest.java')], check=True)
    subprocess.run(['java', '-cp', directory, 'com.tomi.tomi_app.MobilePolicyTest'], check=True)
