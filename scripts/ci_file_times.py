#!/usr/bin/env python3
"""Keep file times across hosted CI runs, so a cached Swift build recompiles only what changed.

A fresh checkout stamps every file with the current time, and Swift treats a new time as a change.
`save` records each tracked file's content hash and time in the build folder. `restore` gives every
file whose content is unchanged its recorded time; changed and new files keep the checkout time.
"""
import json
import os
from pathlib import Path
import subprocess
import sys

RECORD = Path('.build/ci-file-times.json')


def tracked():
    """Each tracked regular file with its content hash. Symbolic links are left alone."""
    listing = subprocess.check_output(['git', 'ls-files', '-s', '-z'], text=True)
    for entry in filter(None, listing.split('\0')):
        meta, path = entry.split('\t', 1)
        mode, digest = meta.split()[:2]
        if mode != '120000' and os.path.isfile(path):
            yield path, digest


if sys.argv[1:] == ['save']:
    RECORD.write_text(json.dumps({path: [digest, os.stat(path).st_mtime_ns] for path, digest in tracked()}))
elif sys.argv[1:] == ['restore']:
    recorded = json.loads(RECORD.read_text()) if RECORD.exists() else {}
    kept = changed = 0
    for path, digest in tracked():
        if recorded.get(path, [None])[0] == digest:
            os.utime(path, ns=(recorded[path][1], recorded[path][1]))
            kept += 1
        else:
            changed += 1
    print(f'Kept the recorded times of {kept} unchanged files; {changed} changed or new files are rebuilt.')
else:
    sys.exit('Usage: ci_file_times.py save|restore')
