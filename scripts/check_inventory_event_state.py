#!/usr/bin/env python3
"""Check installed historical inventory with exact knowledge and effective cutoffs."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def run(cli: Path, output: Path):
    calls = []
    with tempfile.TemporaryDirectory(prefix='sevra-inventory-history-') as directory:
        folder = Path(directory)
        book = folder / 'Inventory.sevra'
        def call(*arguments, error=None):
            p = subprocess.run([str(cli), *map(str, arguments)], capture_output=True, text=True, timeout=30)
            clean = lambda text: text.replace(str(folder), '<fixture>')
            calls.append({'arguments': [clean(str(a)) for a in arguments], 'returncode': p.returncode,
                          'stdout': clean(p.stdout), 'stderr': clean(p.stderr)})
            assert (p.returncode == 0) == (error is None), p
            result = json.loads(p.stdout if error is None else p.stderr)
            assert result['ok'] == (error is None), result
            if error:
                assert not p.stdout and (error == '*' or result['error']['code'] == error), result
                return result
            assert not p.stderr, p.stderr
            return result['result']
        def tail():
            return call('business-batches', book)['tail']['id']
        def state(batch, through='2026-12-31', target=book):
            result = call('inventory-at-batch', target, batch, 'parts', through)
            assert result['execution'] == 'inert' and result['knowledgeBatch']['id'] == batch
            assert result['coverage'] == 'exact-retained-business-cutoff'
            return result
        call('create', book)
        source = call('add', book, json.dumps({'category': 'source', 'kind': 'observation', 'title': 'Synthetic opening input'}))
        call('opening', book, 'parts', '20', '2026-01-01', source['id'])
        basis = tail()
        assert state(basis)['quantity'] == '20'
        request = {'subject': 'parts', 'quantity': '-2', 'occurrence': 'sale',
                   'effective': '2026-01-02', 'input': source['id']}
        draft = call('movement', book, json.dumps(request))
        accepted = call('accept', book, draft['id'], 'accept-sale')
        first = tail()
        original = state(first)
        assert original['quantity'] == '18' and original['effects'][0]['itemID'] == accepted['id']
        correction = call('movement', book, json.dumps({**request, 'quantity': '-5', 'supersedes': accepted['id']}))
        assert state(first) == original
        revised = call('accept', book, correction['id'], 'correct-sale')
        second = tail()
        assert state(second)['quantity'] == '15'
        assert state(first) == original and state(basis)['quantity'] == '20'
        call('undo', book, revised['id'], 'undo-correction')
        third = tail()
        assert state(third)['quantity'] == '18'
        future = call('movement', book, json.dumps({**request, 'quantity': '3', 'occurrence': 'future',
                                                  'effective': '2030-01-01', 'status': 'accepted'}))
        fourth = tail()
        assert state(fourth)['quantity'] == '18'
        projected = state(fourth, '2030-01-01')
        assert projected['quantity'] == '21' and len(projected['effects']) == 2
        assert projected['quantity'] == call('balance', book, 'parts')['quantity']
        unknown = state(fourth, '2025-12-31')
        assert unknown['known'] is False and unknown['quantity'] is None and unknown['reason'] == 'basis_not_effective'
        no_basis = call('inventory-at-batch', book, fourth, 'unknown-subject', '2030-01-01')
        assert no_basis['quantity'] is None and no_basis['reason'] == 'unknown_basis'
        commits = call('commits', book)
        assert state(first) == original
        assert call('commits', book) == commits
        call('inventory-at-batch', book, fourth, 'parts', error='usage')
        call('inventory-at-batch', book, fourth, 'parts', 'next week', error='date')
        call('inventory-at-batch', book, source['id'], 'parts', '2030-01-01', error='business_batch')
        restored = folder / 'Restored.sevra'
        call('reconstruct', book, restored)
        assert state(first, target=restored) == original
        assert state(fourth, '2030-01-01', target=restored) == projected
        assert call('verify', book)['ok'] and call('verify', restored)['ok']
    report = {'version': 1, 'scope': 'installed exact historical inventory oracle',
              'cliSHA256': hashlib.sha256(cli.read_bytes()).hexdigest(), 'callCount': len(calls),
              'actualModel': False, 'automaticConditionExecution': False, 'visibleOS': False, 'calls': calls}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, sort_keys=True, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('.build/inventory-event-state-cli.json'))
    args = parser.parse_args()
    result = run(args.cli.resolve(strict=True), args.output)
    print(json.dumps({key: value for key, value in result.items() if key != 'calls'}, sort_keys=True))
