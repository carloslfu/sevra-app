"""Check pinned engine sources and reproducible SDK/example bundles."""
import hashlib,json,pathlib,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
pin=json.loads((ROOT/'integration/quickjs.json').read_text())
for name,digest in pin['files'].items():
    assert hashlib.sha256((ROOT/'Sources/CQuickJS'/name).read_bytes()).hexdigest()==digest, name
paths=[ROOT/'Sources/SevraAppRuntime/Resources/sdk.js',ROOT/'Sources/SevraAppRuntime/Resources/Signals-LICENSE.txt']+list((ROOT/'examples/apps').glob('*/app.sevraapp'))
before={p:p.read_bytes() for p in paths}
modified={p:p.stat().st_mtime_ns for p in paths}
subprocess.run(['node','sdk/build.mjs'],cwd=ROOT,check=True)
for folder in sorted((ROOT/'examples/apps').iterdir()):
    if (folder/'app.json').exists():subprocess.run(['node','sdk/build.mjs',str(folder)],cwd=ROOT,check=True)
for path in paths:
    assert path.read_bytes()==before[path], 'Stale generated bundle: '+str(path.relative_to(ROOT))
    assert path.stat().st_mtime_ns==modified[path], 'Unchanged bundle was rewritten: '+str(path.relative_to(ROOT))
print('Pinned QuickJS files and generated SDK/example bundles match.')
