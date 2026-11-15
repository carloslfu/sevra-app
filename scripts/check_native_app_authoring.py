"""Package the authoring checks with the actual signed isolated app worker."""
import argparse
import datetime
import hashlib
import json
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
from package_app_worker import package

ROOT = pathlib.Path(__file__).resolve().parents[1]


def evidence_sources():
    return sorted({
        ROOT / 'Package.swift', *ROOT.glob('Sources/**/*.swift'),
        *(p for p in ROOT.glob('Sources/**/Resources/**/*') if p.is_file()),
        *ROOT.glob('IntegrationTests/Agent/*.swift'), ROOT / 'sdk/src/runtime.ts',
        ROOT / 'sdk/build.mjs', ROOT / 'scripts/check_native_app_sources.py',
        ROOT / 'Sources/SevraAppRuntime/Resources/sdk.js',
        ROOT / 'Sources/CQuickJS/SevraJS.c', ROOT / 'Sources/CQuickJS/include/SevraJS.h',
        ROOT / 'integration/quickjs.json', pathlib.Path(__file__),
        *ROOT.glob('scripts/*excel*fixtures*'), *ROOT.glob('scripts/*excel*oracles*'),
        *ROOT.glob('scripts/qualify_excel_business.py')})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bin', default='.build/debug')
    parser.add_argument('--live', nargs=4, metavar=('MODELS', 'GUIDANCE', 'ENGINE', 'OUTPUT'))
    parser.add_argument('--home-live', nargs=4, metavar=('MODELS', 'GUIDANCE', 'ENGINE', 'OUTPUT'))
    parser.add_argument('--chat-live', nargs=4, metavar=('MODELS', 'GUIDANCE', 'ENGINE', 'OUTPUT'))
    parser.add_argument('--excel-live', nargs=4, metavar=('MODELS', 'GUIDANCE', 'ENGINE', 'OUTPUT'))
    parser.add_argument('--excel-behavior-live', nargs=4, metavar=('MODELS', 'GUIDANCE', 'ENGINE', 'OUTPUT'))
    parser.add_argument('--excel-only', action='store_true')
    parser.add_argument('--excel-business-live', nargs=4, metavar=('MODELS', 'GUIDANCE', 'ENGINE', 'OUTPUT'))
    args = parser.parse_args()
    binary = (ROOT / args.bin).resolve()
    sdk_source = ROOT / 'Sources/SevraAppRuntime/Resources/sdk.js'
    sdk_product = binary / 'Sevra_SevraAppRuntime.bundle/sdk.js'
    if not sdk_product.is_file() or sdk_product.read_bytes() != sdk_source.read_bytes():
        raise SystemExit('The worker SDK resource is stale. Build sevra-app-worker after building the SDK before running checks.')
    live = args.live or args.excel_live or args.excel_behavior_live or args.chat_live or args.home_live or args.excel_business_live
    suffix = hashlib.sha256(str(live).encode()).hexdigest()[:8] if live else 'validation'
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
        if args.excel_behavior_live:
            options = ['--excel-behavior-live', *args.excel_behavior_live]
        if args.home_live:
            options = ['--home-live', *args.home_live]
        if args.chat_live:
            options = ['--chat-live', *args.chat_live]
        if args.excel_business_live:
            options = ['--excel-business-live', *args.excel_business_live]
        identity = None
        if live:
            def digest(path):
                return hashlib.sha256(path.read_bytes()).hexdigest()
            identity = {
                'startedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'gitHead': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'buildProducts': {name: digest(binary / name) for name in [
                    'sevra-agent-checks', 'sevra-extract', 'sevra-app-worker']},
                'binaries': {str(path.relative_to(app)): digest(path) for path in [
                    app / 'Contents/MacOS/checks', app / 'Contents/MacOS/sevra-extract',
                    *sorted(app.glob('Contents/XPCServices/*.xpc/Contents/MacOS/sevra-app-worker'))]},
                'engineSHA256': digest(pathlib.Path(live[2])),
                'guidanceSHA256': digest(pathlib.Path(live[1])),
                'resources': {str(path.relative_to(app)): digest(path) for path in sorted(
                    app.glob('Contents/**/Resources/**/*')) if path.is_file()},
                'fixtures': {str(path.relative_to(ROOT)): digest(path) for path in sorted(
                    (ROOT / ('integration/fixtures/excel-business' if args.excel_business_live else 'integration/fixtures/excel-behavior')).glob('*')) if path.is_file()},
                'sources': {str(path.relative_to(ROOT)): digest(path) for path in evidence_sources()},
            }
        try:
            subprocess.run([str(app / 'Contents/MacOS/checks'), *options], cwd=ROOT, check=True, timeout=(6 * 3600 if args.excel_business_live else 3600) if live else 240)
        finally:
            if identity is not None and pathlib.Path(live[3]).is_dir():
                identity['finishedAt'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                identity['sourceUnchangedAtEnd'] = all(
                    (ROOT / name).is_file() and digest(ROOT / name) == expected
                    for group in ['sources', 'fixtures'] for name, expected in identity[group].items())
                (pathlib.Path(live[3]) / 'runtime.json').write_text(json.dumps(identity, indent=2) + '\n')


if __name__ == '__main__':
    main()
