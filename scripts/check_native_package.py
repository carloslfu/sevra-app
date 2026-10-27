"""Verify the isolated installed native product without model weights or build-tree reads."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--paths-only', action='store_true',
                        help='Check packaging without GPU validation or model loading on CI hosts.')
    options = parser.parse_args()
    product = ROOT / "output/native"
    profile = '(version 1) (allow default) (deny file-read* (subpath ' + json.dumps(str(ROOT / '.build')) + '))'
    app = product / "Sevra Native Preview.app"
    executables = [(product / 'bin/sevra', ['check-resources']),
                   (app / 'Contents/MacOS/Sevra', ['--check-resources'])]
    for binary, arguments in executables:
        if options.paths_only:
            arguments += ['--paths-only']
        result = subprocess.run(['sandbox-exec', '-p', profile, str(binary), *arguments],
                                capture_output=True, text=True, timeout=60)
        assert result.returncode == 0, result.stdout + result.stderr
        response = json.loads(result.stdout)
        value = response.get('result', response)
        assert value['runtimeDigests'] and value['grammarLibrary'], value
        assert (value['kernelCount'] == 0 if options.paths_only else value['kernelCount'] > 0), value
        symbols = subprocess.check_output(['nm', '-j', str(binary)], text=True)
        demangled = subprocess.run(['xcrun', 'swift-demangle'], input=symbols, capture_output=True, text=True, check=True).stdout
        assert not any(name in demangled for name in ['Slotstream.', 'MLX.', 'SevraBaseline.'])
        linked = subprocess.check_output(['otool', '-L', str(binary)], text=True)
        assert not any(name.lower() in linked.lower() for name in ['python', 'mlx', 'slotstream'])
        print(json.dumps({'check': 'installed_resources', 'product': str(binary.relative_to(product)),
                          'buildTreeDenied': True, 'noBaselineSymbols': True, **value}), flush=True)
    with tempfile.TemporaryDirectory(prefix='sevra-native-package-') as temporary:
        folder = Path(temporary) / 'bin'
        shutil.copytree(product / 'bin', folder)
        binary = folder / 'sevra'
        cases = ['Sevra_SevraSplash.bundle', 'Sevra_SevraSplashText.bundle',
                 'Sevra_SevraSplashGrammar.bundle', 'swift-transformers_Hub.bundle',
                 'NativeRuntime/engine/splash', 'NativeRuntime/engine/splash.metallib',
                 'NativeRuntime/engine/host-step.metallib', 'NativeRuntime/libllguidance.dylib',
                 'native-runtime.json']
        for relative in cases:
            path = folder / relative
            hidden = path.with_name(path.name + '.held')
            path.rename(hidden)
            try:
                result = subprocess.run([str(binary), 'check-resources'], capture_output=True, text=True, timeout=60)
                assert result.returncode != 0, 'Missing installed resource silently used build tree: ' + relative
                assert not json.loads(result.stderr)['ok'], result.stderr
            finally:
                hidden.rename(path)
        for command in ['model-setup', 'model-status']:
            result = subprocess.run([str(binary), command, '--unknown-option'], cwd=temporary,
                                    capture_output=True, text=True, timeout=10)
            assert result.returncode != 0 and json.loads(result.stderr)['error']['code'] == 'usage', result.stderr
        assert not (Path(temporary) / '--unknown-option').exists()
        if not options.paths_only:
            workbook = Path(temporary) / 'Missing model.sevra'
            subprocess.run([str(binary), 'demo', str(workbook)], check=True, capture_output=True)
            result = subprocess.run([str(binary), 'ask', str(workbook), 'What is the current stock?',
                                     str(Path(temporary) / 'No model')], capture_output=True, text=True, timeout=30)
            assert result.returncode != 0 and 'Open Model Settings' in result.stderr, result.stderr
            runs = json.loads(subprocess.check_output([str(binary), 'runs', str(workbook)], text=True))['result']
            assert runs[0]['status'] == 'failed', runs
            verified = json.loads(subprocess.check_output([str(binary), 'verify', str(workbook)], text=True))['result']
            assert verified['ok'], verified
        print(json.dumps({'check': 'native_setup_refusal', 'invalidOptionsRefused': True,
                          'missingModelGuidance': None if options.paths_only else True,
                          'failedRunSaved': None if options.paths_only else True,
                          'workbookPreserved': None if options.paths_only else True}), flush=True)
        path = folder / 'NativeRuntime/engine/splash.metallib'
        with path.open('r+b') as f:
            byte = f.read(1)
            f.seek(0)
            f.write(bytes([byte[0] ^ 1]))
        result = subprocess.run([str(binary), 'check-resources'], capture_output=True, text=True, timeout=60)
        assert result.returncode != 0 and 'verification failed' in result.stderr, result.stderr
        print(json.dumps({'check': 'installed_resource_failures', 'missingRefused': len(cases), 'alteredRefused': True}), flush=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    print(json.dumps({'check': 'native_signature', 'passed': True}), flush=True)


if __name__ == '__main__':
    main()
