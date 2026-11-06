"""macOS only: launch an unsigned simulator build, never a production account."""
import json,subprocess,time
from pathlib import Path
if __name__=='__main__':
    data=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
    devices=[d for runtime,items in data['devices'].items() if 'iOS' in runtime for d in items if d.get('isAvailable') and 'iPhone' in d['name']]
    if not devices:raise SystemExit('No available iPhone simulator runtime on this macOS runner')
    device=next((d for d in devices if d['state']=='Booted'),devices[0]);uid=device['udid']
    if device['state']!='Booted':subprocess.run(['xcrun','simctl','boot',uid],check=True)
    subprocess.run(['xcrun','simctl','bootstatus',uid,'-b'],check=True,timeout=300)
    subprocess.run(['xcrun','simctl','install',uid,'build/ios/iphonesimulator/Runner.app'],check=True)
    subprocess.run(['xcrun','simctl','launch',uid,'com.tomi.tomiapp'],check=True)
    time.sleep(8)
    # A dead app must not be confused with a successful compilation.
    processes=subprocess.check_output(['xcrun','simctl','spawn',uid,'launchctl','list'],text=True)
    if not any('com.tomi.tomiapp' in line and line.split()[0].isdigit() for line in processes.splitlines() if line.split()):raise SystemExit('TOMI did not remain running in the simulator')
    Path('build').mkdir(exist_ok=True)
    subprocess.run(['xcrun','simctl','io',uid,'screenshot','build/TOMI-iPhone-Simulator.png'],check=True)
    print('PASS: launched the iPhone Simulator build; physical signing, media and APNs still require device acceptance.')
