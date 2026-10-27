#!/usr/bin/env python3
"""Exercise packaged atomic document editing without loading a model."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cli', type=Path, default=ROOT / 'output/bin/sevra')
CLI = parser.parse_args().cli.resolve(strict=True)

with tempfile.TemporaryDirectory(prefix='sevra-document-cli-') as directory:
    root = Path(directory)
    book = root / 'Documents.sevra'

    def run(*args, error=None):
        result = subprocess.run([str(CLI), *map(str, args)], cwd=root, capture_output=True, text=True, timeout=30)
        value = json.loads(result.stderr if error else result.stdout)
        if error:
            assert result.returncode != 0 and value['ok'] is False and value['error']['code'] == error, (result, value)
        else:
            assert result.returncode == 0 and value['ok'] is True, (result, value)
            return value['result']

    assert 'edit-document' in run('help')
    run('create', book)
    source = run('add', book, json.dumps({'category': 'source', 'kind': 'assumption', 'title': 'Packing', 'text': '0.10 kg per sample', 'meaning': 'estimate'}))
    original = run('tool', book, 'draft', json.dumps({'title': 'Packing plan', 'text': 'Original 0.10 kg', 'inputs': [source['id']]}))
    text = root / 'edited.txt'
    text.write_text('Use 0.25 kg. Café 👩🏽‍💻\n', encoding='utf-8')
    before = run('inspect', book)
    edited = run('edit-document', book, original['id'], text, '--token', 'edit-once', '--revision', before['revision'])
    assert edited['text'] == text.read_text() and edited['meaning'] == 'estimate' and edited['status'] == 'draft'
    after = run('inspect', book)
    assert after['revision'] == before['revision'] + 1
    assert run('edit-document', book, original['id'], text, '--token', 'edit-once', '--revision', before['revision']) == edited
    assert run('inspect', book) == after
    run('edit-document', book, original['id'], text, error='stale_revision')
    assert run('inspect', book) == after
    copy = run('edit-document', book, original['id'], text, '--separate')
    assert copy['logicalID'] != edited['logicalID'] and copy['text'] == edited['text']
    counts = run('inspect', book)
    invalid = root / 'invalid.txt'; invalid.write_bytes(b'\xff')
    run('edit-document', book, edited['id'], invalid, error='encoding')
    oversized = root / 'oversized.txt'
    with oversized.open('wb') as handle:
        handle.truncate(16_000_001)
    run('edit-document', book, edited['id'], oversized, error='limit')
    run('edit-document', book, edited['id'], text, '--unexpected', error='usage')
    run('edit-document', book, edited['id'], text, '--separate', '--separate', error='usage')
    run('edit-document', book, edited['id'], root, error='document_file')
    assert run('inspect', book) == counts
    accepted = run('accept', book, edited['id'])
    assert accepted['text'] == edited['text'] and accepted['meaning'] == 'estimate'
    assert run('verify', book)['ok'] is True
    print(json.dumps({'atomicEdit': True, 'exactRetry': True, 'staleRefusal': True, 'explicitCopy': True,
                      'boundedUTF8File': True, 'invalidInputsUnchanged': True, 'currentVersionAccepted': True}))
