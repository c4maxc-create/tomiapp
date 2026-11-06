"""Exercise the actual Java trim helper used by the vendored Android plugin."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as tmp:
    subprocess.run(['java','com.sun.tools.javac.Main','-encoding','UTF-8','-d',tmp,str(root/'third_party/video_compress/android/src/main/kotlin/com/example/video_compress/TomiTrim.java'),str(root/'native/test/TomiTrimTest.java')],check=True)
    subprocess.run(['java','-cp',tmp,'TomiTrimTest'],check=True)
