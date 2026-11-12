"""Embed the minimal sandboxed JS service. Never sign it with parent entitlements."""
import pathlib, plistlib, shutil, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]

def package(app, binary):
    service = app / 'Contents/XPCServices/com.sevra.workbooks.app-worker.xpc'
    if service.exists(): shutil.rmtree(service)
    (service / 'Contents/MacOS').mkdir(parents=True)
    resources = service / 'Contents/Resources'
    resources.mkdir()
    shutil.copy2(binary / 'sevra-app-worker', service / 'Contents/MacOS/sevra-app-worker')
    shutil.copytree(binary / 'Sevra_SevraAppRuntime.bundle', resources / 'Sevra_SevraAppRuntime.bundle')
    shutil.copy2(ROOT / 'Sources/CQuickJS/LICENSE', resources / 'QuickJS-LICENSE.txt')
    info = {'CFBundleIdentifier': 'com.sevra.workbooks.app-worker', 'CFBundleName': 'Sevra App Worker',
            'CFBundleExecutable': 'sevra-app-worker', 'CFBundlePackageType': 'XPC!', 'CFBundleVersion': '1',
            'XPCService': {'ServiceType': 'Application', 'RunLoopType': 'dispatch_main'}}
    (service / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign','--force','--sign','-','--entitlements',str(ROOT/'Resources/AppWorker.entitlements'),str(service)],check=True)
    subprocess.run(['codesign','--verify','--strict',str(service)],check=True)
    return service

if __name__ == '__main__': package(pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]))
