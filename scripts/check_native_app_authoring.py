"""Package the authoring checks with the actual signed isolated app worker."""
import argparse
import hashlib
import pathlib
import plistlib
import shutil
import subprocess
from package_app_worker import package

ROOT = pathlib.Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bin', default='.build/debug')
    parser.add_argument('--live', nargs=4, metavar=('MODELS', 'GUIDANCE', 'ENGINE', 'OUTPUT'))
    args = parser.parse_args()
    binary = (ROOT / args.bin).resolve()
    suffix = hashlib.sha256(str(args.live).encode()).hexdigest()[:8] if args.live else 'validation'
    app = ROOT / ('.build/native-app-authoring/Authoring Checks-' + suffix + '.app')
    if app.exists():
        shutil.rmtree(app)
    (app / 'Contents/MacOS').mkdir(parents=True)
    (app / 'Contents/Resources').mkdir()
    shutil.copy2(binary / 'sevra-agent-checks', app / 'Contents/MacOS/checks')
    for resource in binary.glob('*.bundle'):
        shutil.copytree(resource, app / 'Contents/Resources' / resource.name)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'com.sevra.native-app-authoring-checks.' + suffix,
        'CFBundleExecutable': 'checks', 'CFBundleName': 'Authoring Checks', 'CFBundlePackageType': 'APPL'}))
    package(app, binary)
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    options = ['--native-app-authoring', *args.live] if args.live else ['--native-app-authoring-checks']
    subprocess.run([str(app / 'Contents/MacOS/checks'), *options], cwd=ROOT, check=True, timeout=3600 if args.live else 120)


if __name__ == '__main__':
    main()
