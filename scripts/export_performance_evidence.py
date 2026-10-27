"""Preserve benchmark receipts with local paths removed for public review."""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('runs', type=Path, nargs='+')
args = parser.parse_args()


def sanitize(value):
    if isinstance(value, str):
        value = value.replace(str(ROOT), '<repo>').replace(str(Path.home()), '<home>')
        return re.sub(r'/var/folders/[^\s"\']+', '<temporary-folder>', value)
    if isinstance(value, list):
        return [sanitize(item) for item in value]
    if isinstance(value, dict):
        return {key: sanitize(item) for key, item in value.items()}
    return value


result = {'schemaVersion': 1, 'scope': 'Matched request performance evidence; not production adoption.',
          'sanitization': 'Repository, home and randomized temporary paths replaced. Raw-file hashes precede sanitization.',
          'runs': {}}
for folder in args.runs:
    assert folder.name not in result['runs'], 'Duplicate run name'
    assert (folder / 'summary.json').is_file(), 'Run has no summary'
    files = {}
    for path in sorted(folder.iterdir()):
        if path.suffix not in ['.json', '.stderr']:
            continue
        raw = path.read_bytes()
        files[path.name] = {'rawSHA256': hashlib.sha256(raw).hexdigest(),
                            'content': sanitize(json.loads(raw) if path.suffix == '.json' else raw.decode())}
    result['runs'][folder.name] = files
encoded = json.dumps(result, ensure_ascii=False, separators=(',', ':')) + '\n'
assert '/Users/' not in encoded and '/var/folders/' not in encoded, 'Unexpected local path remains'
with args.output.open('x') as output:
    output.write(encoded)
print(json.dumps({'output': str(args.output), 'runs': len(result['runs']), 'bytes': len(encoded.encode())}))
