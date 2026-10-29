#!/usr/bin/env python3
"""Exercise the installed semantic feed and real process-death publication."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import selectors
import signal
import sqlite3
import subprocess
import tempfile
import time


def run(cli: Path, worker: Path, output: Path) -> dict:
    calls = []
    deaths = []
    with tempfile.TemporaryDirectory(prefix='sevra-business-events-') as directory:
        folder = Path(directory)

        def clean(text):
            return text.replace(str(folder), '<fixture>')

        def call(*arguments, error=None):
            result = subprocess.run([str(cli), *map(str, arguments)], text=True,
                                    capture_output=True, timeout=120)
            calls.append({'arguments': [clean(str(a)) for a in arguments],
                          'returncode': result.returncode,
                          'stdout': clean(result.stdout), 'stderr': clean(result.stderr)})
            assert (result.returncode == 0) == (error is None), result
            envelope = json.loads(result.stdout if error is None else result.stderr)
            assert envelope['ok'] == (error is None), envelope
            if error:
                assert not result.stdout and envelope['error']['code'] == error, envelope
                return envelope
            assert not result.stderr, result.stderr
            return envelope['result']

        def add_source(book):
            return call('add', book, json.dumps({'category': 'source', 'kind': 'observation',
                                               'title': 'Synthetic exact input'}))

        def history_count(book):
            with sqlite3.connect(book / 'workbook.sqlite') as connection:
                return connection.execute('SELECT count(*) FROM committed_changes').fetchone()[0]

        book = folder / 'Business.sevra'
        call('create', book)
        source = add_source(book)
        assert call('business-batches', book)['batches'] == []
        forecast = call('add', book, json.dumps({
            'category': 'record', 'kind': 'forecast', 'title': 'Estimate', 'meaning': 'estimate',
            'scenario': 'forecast', 'inputs': [source['id']], 'token': 'forecast-draft',
        }))
        assert call('business-batches', book)['batches'] == []
        accepted = call('accept', book, forecast['id'], 'accept-forecast')
        first = call('business-batches', book)
        assert first['execution'] == 'inert' and len(first['batches']) == 1
        batch = first['batches'][0]
        page = call('business-batch', book, batch['id'])
        event = page['events'][0]
        assert event['afterID'] == accepted['id'] and event['beforeID'] is None
        assert event['payload']['after']['meaning'] == 'estimate'
        assert event['payload']['after']['scenario'] == 'forecast'
        assert page['batchComplete'] and page['execution'] == 'inert'
        assert call('accept', book, forecast['id'], 'accept-forecast')['id'] == accepted['id']
        assert call('business-batches', book) == first
        call('opening', book, 'parts', '20', '2030-01-01', source['id'])
        for number, quantity in enumerate(['-16', '20', '-20']):
            call('movement', book, json.dumps({
                'subject': 'parts', 'quantity': quantity, 'occurrence': f'sale-{number}',
                'effective': '2030-01-02', 'input': source['id'], 'status': 'accepted',
                'token': f'movement-{number}',
            }))
        cursor = '-'
        seen = []
        while True:
            result = call('business-batches', book, cursor, 1, 'inventory', 'parts')
            seen.extend(result['batches'])
            if not result['hasMore']:
                assert result['nextCursor'] == result['tail']['id']
                break
            cursor = result['nextCursor']
        assert len(seen) == 4 and [b['position'] for b in seen] == ['2', '3', '4', '5']
        empty = call('business-batches', book, '-', 2, 'inventory', 'missing')
        assert empty['batches'] == [] and empty['nextCursor'] == empty['tail']['id']
        call('business-batches', book, source['id'], error='business_cursor')
        call('business-batches', book, '-', 0, error='business_limit')
        call('business-batches', book, '-', 2, 'invalid', 'x', error='business_scope')
        call('business-batches', book, '-', 2, 'inventory', error='usage')
        call('business-batch', book, source['id'], error='business_batch')
        call('business-batch', book, batch['id'], '-1', error='business_cursor')
        call('business-batch', book, batch['id'], 1, error='business_cursor')
        call('business-batch', book, batch['id'], '-', 101, error='business_limit')
        csv = folder / 'Rows.csv'
        csv.write_text('sku,quantity\n' + ''.join(f'{n:04d},{n}\n' for n in range(103)))
        imported = call('import', book, csv, '--role', 'values', '--token', 'business-intake')
        dataset = imported['intake']['datasetIDs'][0]
        scoped = call('business-batches', book, '-', 50, 'dataset', dataset)
        largest = max(scoped['batches'], key=lambda b: b['eventCount'])
        assert largest['eventCount'] > 100
        ordinal = '-'
        entries = []
        before_read = history_count(book)
        while True:
            result = call('business-batch', book, largest['id'], ordinal, 17)
            entries.extend(result['events'])
            assert result['batchComplete'] == (not result['hasMore'])
            if not result['hasMore']:
                break
            ordinal = result['nextOrdinal']
        assert len(entries) == largest['eventCount']
        assert len({e['id'] for e in entries}) == len(entries)
        assert [e['ordinal'] for e in entries] == list(range(len(entries)))
        assert history_count(book) == before_read
        assert call('verify', book)['ok']
        restored = folder / 'Restored.sevra'
        call('reconstruct', book, restored)
        assert call('business-batches', restored, '-', 50) == call('business-batches', book, '-', 50)
        assert call('business-batch', restored, batch['id']) == page
        assert call('verify', restored)['ok']
        # This deliberately altered throwaway sequence tests lossless delivery,
        # not valid historical continuity. Ordinary verify must reject its gap.
        large = folder / 'IntegerBoundary.sevra'
        call('create', large)
        basis = add_source(large)
        call('opening', large, 'parts', '1', '2026-01-01', basis['id'])
        seed = call('business-batches', large)['batches'][0]['id']
        with sqlite3.connect(large / 'workbook.sqlite') as connection:
            connection.execute('UPDATE business_batches SET position=9007199254740993')
            connection.execute('UPDATE business_events SET batch_position=9007199254740993')
        assert call('business-batches', large)['batches'][0]['position'] == '9007199254740993'
        call('movement', large, json.dumps({
            'subject': 'parts', 'quantity': '1', 'occurrence': 'exact-integer',
            'effective': '2026-01-02', 'input': basis['id'], 'status': 'accepted',
        }))
        exact = call('business-batches', large, seed)
        assert exact['batches'][0]['position'] == '9007199254740994'
        call('verify', large, error='business_integrity')
        concurrent = folder / 'Concurrent.sevra'
        call('create', concurrent)
        independent = add_source(concurrent)
        def publish(number):
            return call('movement', concurrent, json.dumps({
                'subject': 'parts', 'quantity': '1', 'occurrence': f'independent-{number}',
                'effective': '2026-01-01', 'input': independent['id'], 'status': 'accepted',
            }))
        with ThreadPoolExecutor(max_workers=6) as pool:
            written = list(pool.map(publish, range(6)))
        positions = call('business-batches', concurrent)['batches']
        assert [b['position'] for b in positions] == [str(n) for n in range(1, 7)]
        assert len({item['id'] for item in written}) == 6
        assert call('verify', concurrent)['ok']
        # Preserve unsupported development files; no migration or reset.
        old = folder / 'Unsupported.sevra'
        call('create', old)
        manifest = old / 'manifest.json'
        with sqlite3.connect(old / 'workbook.sqlite') as connection:
            assert connection.execute('PRAGMA user_version').fetchone()[0] == 27
            connection.execute('PRAGMA user_version=26')
        paths = [manifest, old / 'workbook.sqlite']
        hashes = [hashlib.sha256(p.read_bytes()).hexdigest() for p in paths]
        call('business-batches', old, error='schema')
        assert hashes == [hashlib.sha256(p.read_bytes()).hexdigest() for p in paths]
        for stage in ['before-commit', 'after-commit']:
            target = folder / (stage + '.sevra')
            call('create', target)
            add_source(target)
            initial = history_count(target)
            process = subprocess.Popen([str(worker), '--business-death-worker', str(target), stage],
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                selector = selectors.DefaultSelector()
                selector.register(process.stdout, selectors.EVENT_READ)
                deadline = time.monotonic() + 30
                line = ''
                while time.monotonic() < deadline:
                    if selector.select(timeout=1):
                        line = process.stdout.readline().strip()
                        if line.startswith('BUSINESS_PUBLICATION_'):
                            break
                    assert process.poll() is None, process.stderr.read()
                selector.close()
                assert line == 'BUSINESS_PUBLICATION_' + stage, line
                process.kill()
                stdout, stderr = process.communicate(timeout=10)
                assert process.returncode == -signal.SIGKILL and not stderr, stderr
                result = call('business-batches', target)
                expected = 0 if stage == 'before-commit' else 1
                assert len(result['batches']) == expected
                assert history_count(target) == initial + expected
                with sqlite3.connect(target / 'workbook.sqlite') as connection:
                    assert connection.execute("SELECT count(*) FROM operations WHERE id='business-process-death'").fetchone()[0] == expected
                    assert connection.execute("SELECT count(*) FROM items WHERE category='record'").fetchone()[0] == expected
                assert call('verify', target)['ok']
                deaths.append({'stage': stage, 'signal': 'SIGKILL', 'committedBatches': expected,
                               'receiptVersionsFeedAtomic': True, 'barrier': line})
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate(timeout=10)
    report = {'version': 1, 'scope': 'installed-cli-semantic-feed-and-process-death',
              'actualModel': False, 'visibleOS': False, 'automaticConditionExecution': False,
              'cliSHA256': hashlib.sha256(cli.read_bytes()).hexdigest(),
              'workerSHA256': hashlib.sha256(worker.read_bytes()).hexdigest(),
              'callCount': len(calls), 'concurrentWriters': 6, 'unsupportedFilesPreserved': True,
              'processDeaths': deaths, 'calls': calls}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, required=True)
    parser.add_argument('--worker', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('.build/business-events-cli.json'))
    options = parser.parse_args()
    report = run(options.cli.resolve(strict=True), options.worker.resolve(strict=True), options.output)
    print(json.dumps({key: value for key, value in report.items() if key != 'calls'}, sort_keys=True))
