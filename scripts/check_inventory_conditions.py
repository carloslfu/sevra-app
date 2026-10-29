#!/usr/bin/env python3
"""Installed, explicit and inert inventory condition qualification. Synthetic only."""
from __future__ import annotations
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from itertools import count
from pathlib import Path
import selectors
import signal
import subprocess
import tempfile
import time


def run(cli: Path, worker: Path | None, output: Path):
    calls = []
    tokens = count()
    deaths = []
    with tempfile.TemporaryDirectory(prefix='sevra-inventory-condition-') as directory:
        root = Path(directory)
        book = root / 'Conditions.sevra'
        def call(*args, error=None):
            p = subprocess.run([str(cli), *map(str, args)], capture_output=True, text=True, timeout=30)
            clean = lambda s: s.replace(str(root), '<fixture>')
            calls.append({'arguments': [clean(str(a)) for a in args], 'returncode': p.returncode,
                          'stdout': clean(p.stdout), 'stderr': clean(p.stderr)})
            assert (p.returncode == 0) == (error is None), p
            value = json.loads(p.stdout if error is None else p.stderr)
            assert value['ok'] == (error is None)
            if error:
                assert not p.stdout and value['error']['code'] == error, value
                return value
            assert not p.stderr, p.stderr
            return value['result']
        def rule(subject='parts'):
            return json.dumps({'policy': 'native-condition-v1', 'scope': 'inventory:' + subject,
                               'operator': '<', 'threshold': '10'})
        def drain(path, consumer, through='2026-12-31'):
            for n in range(1000):
                value = call('condition-state', path, consumer)
                assert value['execution'] == 'inert' and value['enabled'] is False
                if not value['hasMore'] or value['backpressure']:
                    return value
                call('condition-step', path, consumer, through, f'drain-{next(tokens)}')
            raise AssertionError('Did not drain')
        def movement(path, source, quantity, occurrence, date='2026-01-02'):
            return call('movement', path, json.dumps({'subject': 'parts', 'quantity': quantity,
                         'occurrence': occurrence, 'effective': date, 'input': source, 'status': 'accepted'}))
        call('create', book)
        source = call('add', book, json.dumps({'category': 'source', 'kind': 'observation', 'title': 'Synthetic inventory input'}))['id']
        call('opening', book, 'parts', '20', '2026-01-01', source)
        saved = call('condition-create', book, 'parts', rule(), '2026-12-31', 'create')
        consumer = saved['id']
        call('read', book, saved['sourceID'], error='item_scope')
        assert call('condition-create', book, 'parts', rule(), '2026-12-31', 'create') == saved
        baseline = drain(book, consumer)
        assert baseline['lastCompleteObservation']['quantity'] == '20'
        assert baseline['lastCompleteObservation']['disposition'] == 'baseline'
        movement(book, source, '-15', 'sale')
        movement(book, source, '15', 'restock')
        movement(book, source, '-15', 'second-sale')
        state = drain(book, consumer)
        assert state['pendingCandidates'] == 2 and state['lastCompleteObservation']['quantity'] == '5'
        history = call('condition-observations', book, consumer, '-', '2')
        assert history['hasMore'] and len(history['observations']) == 2
        remaining = call('condition-observations', book, consumer, history['nextCursor'], '2')
        assert not remaining['hasMore'] and len(remaining['observations']) == 2
        candidate = history['observations'][1]['candidateID']
        dismissed = call('condition-dismiss', book, candidate, 'Reviewed the request', 'dismiss')
        assert dismissed['execution'] == 'inert' and dismissed['state'] == 'dismissed'
        call('read', book, dismissed['sourceID'], error='item_scope')
        assert call('condition-dismiss', book, candidate, 'Reviewed the request', 'dismiss') == dismissed
        call('condition-dismiss', book, candidate, 'Another reason', 'dismiss-again', error='condition_candidate')
        call('condition-step', book, consumer, '2025-01-01', 'backwards', error='condition_clock')
        call('condition-observations', book, consumer, 'foreign', error='condition_cursor')
        call('condition-observations', book, consumer, '-', '51', error='condition_limit')
        call('condition-create', book, 'other', rule(), '2026-12-31', 'bad-scope', error='condition_scope')
        call('condition-step', book, consumer, 'tomorrow', 'bad-time', error='date')
        movement(book, source, '15', 'future-reset', date='2030-01-01')
        movement(book, source, '-15', 'future-sale', date='2030-01-02')
        assert drain(book, consumer)['lastCompleteObservation']['quantity'] == '5'
        call('condition-step', book, consumer, '2030-01-03', 'set-clock')
        future = drain(book, consumer, through='2030-01-03')
        assert future['pendingCandidates'] == 2 and future['lastCompleteObservation']['quantity'] == '5'
        oracle = call('inventory-at-batch', book, future['cursorID'], 'parts', '2030-01-03')
        assert oracle['quantity'] == future['lastCompleteObservation']['quantity']
        # Independent invocations serialize on saved pages, with no duplicate candidate.
        movement(book, source, '15', 'independent-reset')
        movement(book, source, '-15', 'independent-crossing')
        with ThreadPoolExecutor(max_workers=6) as pool:
            results = list(pool.map(lambda n: call('condition-step', book, consumer, '2030-01-03', f'writer-{n}'), range(6)))
        assert all(r['execution'] == 'inert' for r in results)
        final = drain(book, consumer, through='2030-01-03')
        assert final['pendingCandidates'] == 3
        before = call('commits', book)
        call('condition-state', book, consumer)
        records = call('condition-observations', book, consumer, '-', '50')
        assert call('commits', book) == before
        restored = root / 'Restored.sevra'
        call('reconstruct', book, restored)
        assert call('condition-state', restored, consumer) == final
        assert call('condition-observations', restored, consumer, '-', '50') == records
        assert call('verify', restored)['ok'] and call('verify', book)['ok']
        if worker:
            for stage in ['prepared', 'committed']:
                target = root / (stage + '.sevra')
                call('create', target)
                inp = call('add', target, json.dumps({'category': 'source', 'kind': 'observation', 'title': 'Crash input'}))['id']
                call('opening', target, 'parts', '20', '2026-01-01', inp)
                cid = call('condition-create', target, 'parts', rule(), '2026-12-31', 'crash-create')['id']
                drain(target, cid)
                movement(target, inp, '-15', 'crash-sale')
                initial = call('condition-state', target, cid)
                process = subprocess.Popen([str(worker), '--condition-death-worker', str(target), cid, stage], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                try:
                    selector = selectors.DefaultSelector()
                    selector.register(process.stdout, selectors.EVENT_READ)
                    deadline = time.monotonic() + 30
                    line = ''
                    while time.monotonic() < deadline:
                        if selector.select(timeout=1):
                            line = process.stdout.readline().strip()
                            break
                        assert process.poll() is None
                    assert line == 'CONDITION_PUBLICATION_' + stage, line
                    process.send_signal(signal.SIGKILL)
                    process.wait(timeout=10)
                    assert process.returncode == -signal.SIGKILL
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait(timeout=10)
                after = call('condition-state', target, cid)
                if stage == 'prepared':
                    assert after == initial
                else:
                    assert after['pendingCandidates'] == 1 and after['cursorID'] != initial['cursorID']
                retry = call('condition-step', target, cid, '2026-12-31', 'condition-death-step')
                assert retry['pendingCandidates'] == 1
                assert call('condition-step', target, cid, '2026-12-31', 'condition-death-step') == retry
                assert call('verify', target)['ok']
                deaths.append({'stage': stage, 'actualSignal': 'SIGKILL', 'returncode': process.returncode,
                               'atomicCursorObservationCandidate': True, 'retryIdentical': True})
    result = {'policy': 'synthetic-inventory-condition-v1', 'cliSHA256': hashlib.sha256(cli.read_bytes()).hexdigest(),
              'workerSHA256': hashlib.sha256(worker.read_bytes()).hexdigest() if worker else None,
              'calls': calls, 'callCount': len(calls), 'concurrentWriters': 6,
              'processDeaths': deaths, 'execution': 'inert', 'actualModelInference': False}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'ok': True, 'callCount': len(calls), 'processDeaths': len(deaths), 'output': str(output)}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--cli', required=True, type=Path)
    parser.add_argument('--worker', type=Path)
    parser.add_argument('--output', type=Path, default=Path('.build/inventory-conditions-installed.json'))
    args = parser.parse_args()
    run(args.cli.resolve(), args.worker.resolve() if args.worker else None, args.output)
