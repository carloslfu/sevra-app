"""Packaged CLI reads the exact journal fixture produced through the Swift core."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / 'output/bin/sevra'
with tempfile.TemporaryDirectory(prefix='sevra-receipt-cli-') as directory:
    root = Path(directory)
    archive = root / 'Fixture.sevraz'
    subprocess.run([str(ROOT / '.build/debug/sevra-checks')], check=True,
                   env={**os.environ, 'SEVRA_RECEIPT_FIXTURE': str(archive)}, capture_output=True, text=True)
    def run(*args, success=True):
        output = subprocess.run([str(CLI), *map(str, args)], capture_output=True, text=True)
        assert (output.returncode == 0) == success, output.stderr + output.stdout
        value = json.loads(output.stdout if success else output.stderr)
        assert value['ok'] == success, value
        return value.get('result') if success else value['error']
    book = root / 'Restored.sevra'
    run('open-archive', archive, book)
    messages = run('history', book)['messages']
    receipt = json.loads(next(message['body'] for message in messages if message['role'] == 'tool'))
    call = receipt['receiptID']
    assert run('tool-receipt', book, 'main', call)['state'] == 'completed'
    assert run('unresolved-calls', book) == []
    page = run('tool-result', book, 'main', call)
    assert page['complete'] is False and page['hash'] == receipt['resultHash']
    assert run('tool-result', book, 'main', call, '["data","299","decimal"]')['value'] == '0.10'
    text = 'café\0👩🏽‍💻\n' * 12_000
    for offset in [0, 1000, len(text) - 20]:
        page = run('tool-result', book, 'main', call, '["text"]', offset)
        assert page['textSegment'] == text[offset:offset + 1000]
    raw = run('tool-result', book, 'main', call, '--raw-json')
    assert raw['offsetUnit'] == 'Unicode scalar' and raw['textSegment'].startswith('{')
    run('tool-result', book, 'main', call, '"wrong path type"', success=False)
    run('tool-result', book, 'main', call, '[]', -1, success=False)
    run('tool-receipt', book, 'different-conversation', call, success=False)
    assert run('verify', book)['ok']
    print(json.dumps({'packagedReceiptCLI': True, 'exactDecimalAndUnicode': True,
                      'validPagesAndRawJSON': True, 'scopeAndArgumentRefusals': True,
                      'offlineArchive': True}))
