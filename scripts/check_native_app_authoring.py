"""Package the authoring checks with the actual signed isolated app worker."""
import argparse
import hashlib
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
from package_app_worker import package

ROOT = pathlib.Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bin', default='.build/debug')
    parser.add_argument('--live', nargs=4, metavar=('MODELS', 'GUIDANCE', 'ENGINE', 'OUTPUT'))
    parser.add_argument('--excel-live', nargs=4, metavar=('MODELS', 'GUIDANCE', 'ENGINE', 'OUTPUT'))
    parser.add_argument('--excel-only', action='store_true')
    args = parser.parse_args()
    binary = (ROOT / args.bin).resolve()
    suffix = hashlib.sha256(str(args.live or args.excel_live).encode()).hexdigest()[:8] if args.live or args.excel_live else 'validation'
    with tempfile.TemporaryDirectory(prefix='native-app-authoring-', dir=ROOT / '.build') as temporary:
        app = pathlib.Path(temporary) / 'Authoring Checks.app'
        (app / 'Contents/MacOS').mkdir(parents=True)
        (app / 'Contents/Resources').mkdir()
        shutil.copy2(binary / 'sevra-agent-checks', app / 'Contents/MacOS/checks')
        shutil.copy2(binary / 'sevra-extract', app / 'Contents/MacOS/sevra-extract')
        for resource in binary.glob('*.bundle'):
            shutil.copytree(resource, app / 'Contents/Resources' / resource.name)
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'com.sevra.native-app-authoring-checks.' + suffix,
            'CFBundleExecutable': 'checks', 'CFBundleName': 'Authoring Checks', 'CFBundlePackageType': 'APPL'}))
        package(app, binary)
        subprocess.run(['codesign', '--force', '--sign', '-', str(app / 'Contents/MacOS/sevra-extract')], check=True)
        subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        options = ['--excel-conversion-live', *args.excel_live] if args.excel_live else ['--native-app-authoring', *args.live] if args.live else ['--excel-conversion-checks'] if args.excel_only else ['--native-app-authoring-checks']
        subprocess.run([str(app / 'Contents/MacOS/checks'), *options], cwd=ROOT, check=True, timeout=3600 if args.live or args.excel_live else 240)


if __name__ == '__main__':
    main()
