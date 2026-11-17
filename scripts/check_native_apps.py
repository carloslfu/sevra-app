"""Exercise the real signed XPC service and native renderer in an isolated host bundle."""
import argparse, pathlib, plistlib, re, shutil, subprocess, tempfile
from package_app_worker import package
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser();p.add_argument('--bin',default='.build/debug');args=p.parse_args()
    binary=(ROOT/args.bin).resolve()
    with tempfile.TemporaryDirectory(prefix='native-app-checks-', dir=ROOT/'.build') as temporary:
        app=pathlib.Path(temporary)/'Native App Checks.app'
        (app/'Contents/MacOS').mkdir(parents=True);(app/'Contents/Resources').mkdir()
        shutil.copy2(binary/'sevra-native-app-checks',app/'Contents/MacOS/checks')
        shutil.copy2(binary/'sevra-extract',app/'Contents/MacOS/sevra-extract')
        shutil.copytree(binary/'Sevra_SevraAppRuntime.bundle',app/'Contents/Resources/Sevra_SevraAppRuntime.bundle')
        shutil.copytree(binary/'Sevra_SevraExtractionWorker.bundle',app/'Contents/Resources/Sevra_SevraExtractionWorker.bundle')
        (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.sevra.native-app-checks','CFBundleExecutable':'checks','CFBundleName':'Native App Checks','CFBundlePackageType':'APPL'}))
        package(app,binary)
        subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
        subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
        result=subprocess.run([str(app/'Contents/MacOS/checks'),'--xpc'],cwd=ROOT,timeout=90,stdout=subprocess.PIPE,text=True)
        print(result.stdout,end='')
        result.check_returncode()
        if not re.search(r'(?m)^\d+ passed, 0 failed$',result.stdout):
            raise RuntimeError('Native app checks exited without completing the suite.')
if __name__=='__main__':main()
