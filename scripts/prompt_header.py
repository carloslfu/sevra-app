"""The prepared prompt header for packaging and for the real-model check scripts.

The app never computes the ordinary chat header. `sevra header make DIRECTORY` makes it once
with the installed model, or finds a matching one already in DIRECTORY, which needs no model.
Packaging copies it into the app before the app is signed. Check scripts make it first and
point the command line tool at it with SEVRA_PROMPT_HEADER, because a tool outside an app has
no header of its own.

    python3 scripts/prompt_header.py status [DIRECTORY]
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / '.build/prompt-header'


def _run(cli, *arguments):
    environment = dict(os.environ)
    environment.pop('SEVRA_PROMPT_HEADER', None)
    process = subprocess.run([str(cli), *arguments], capture_output=True, text=True, env=environment)
    progress = [line for line in process.stderr.splitlines() if not line.startswith('{')]
    for line in progress:
        print('prompt header: ' + line, file=sys.stderr, flush=True)
    if process.returncode == 0:
        return json.loads(process.stdout)['result'], None
    errors = [line for line in process.stderr.splitlines() if line.startswith('{')]
    error = json.loads(errors[-1])['error'] if errors else {'code': 'unknown', 'message': process.stderr}
    return None, error


def make(cli, cache=CACHE, models=None):
    """The header for this build, made with the installed model if the cache has none."""
    arguments = ['header', 'make', str(cache)]
    models = models or os.environ.get('SEVRA_MODEL_DIRECTORY')
    if models:
        arguments.append(str(models))
    return _run(cli, *arguments)


def place(cli, app, required):
    """Copies the matching header into APP/Contents/Resources/PromptHeader. Without the model a
    development package has none and says so; a release that requires one fails."""
    target = Path(app) / 'Contents/Resources/PromptHeader'
    if target.exists():
        shutil.rmtree(target)
    result, error = make(cli)
    if error:
        if error['code'] == 'model_missing' and not required:
            print('No prompt header in this build: the local model is not installed. Chat stays '
                  'unavailable until the model is downloaded and bash scripts/install.sh runs again.',
                  file=sys.stderr, flush=True)
            return None
        raise SystemExit('The prompt header could not be made: ' + error['message'])
    folder = Path(result['folder'])
    target.mkdir(parents=True)
    shutil.copytree(folder, target / folder.name)
    return json.loads((folder / 'manifest.json').read_text())


def ensure(cli, models=None):
    """For a real-model check: make the header first, then point every tool it runs at it."""
    result, error = make(cli, models=models)
    if error:
        raise SystemExit('The prompt header could not be made: ' + error['message'])
    os.environ['SEVRA_PROMPT_HEADER'] = str(CACHE)
    return result


def self_test():
    """No model: a package without the model has no header and says so, a release that needs one
    fails, and a found header is copied whole into the app."""
    import tempfile
    with tempfile.TemporaryDirectory(prefix='sevra-header-test-') as temporary:
        root = Path(temporary)
        header = root / 'made' / ('a' * 64)
        header.mkdir(parents=True)
        for name in ('kv.records', 'kv.slots', 'state.records', 'state.slots'):
            (header / name).write_bytes(name.encode())
        (header / 'manifest.json').write_text(json.dumps({'inputs': 'a' * 64, 'tokens': 9}))
        missing, found = root / 'missing', root / 'found'
        missing.write_text('#!/bin/sh\necho \'{"ok":false,"error":{"code":"model_missing","message":"no model"}}\' >&2\nexit 1\n')
        found.write_text('#!/bin/sh\necho \'{"ok":true,"result":{"folder":"%s"}}\'\n' % header)
        for script in (missing, found):
            script.chmod(0o755)
        app = root / 'Sevra.app'
        (app / 'Contents/Resources/PromptHeader/old').mkdir(parents=True)
        assert place(missing, app, required=False) is None
        assert not (app / 'Contents/Resources/PromptHeader').exists(), 'A stale header was kept'
        try:
            place(missing, app, required=True)
            raise AssertionError('A release without a header was packaged')
        except SystemExit as error:
            assert 'no model' in str(error)
        assert place(found, app, required=True) == {'inputs': 'a' * 64, 'tokens': 9}
        copied = app / 'Contents/Resources/PromptHeader' / ('a' * 64)
        assert sorted(p.name for p in copied.iterdir()) == sorted(p.name for p in header.iterdir())
    print('PASS prompt header packaging: none without the model, refused for a release, copied whole')


if __name__ == '__main__':
    if sys.argv[1:] == ['self-test']:
        self_test()
        sys.exit(0)
    if len(sys.argv) in (2, 3) and sys.argv[1] == 'status':
        cli = Path(os.environ.get('SEVRA_CLI', ROOT / 'output/native/bin/sevra'))
        status, error = _run(cli, 'header', 'status', sys.argv[2] if len(sys.argv) == 3 else str(CACHE))
        print(json.dumps(status or error, indent=2))
        sys.exit(1 if error else 0)
    print(__doc__, file=sys.stderr)
    sys.exit(2)
