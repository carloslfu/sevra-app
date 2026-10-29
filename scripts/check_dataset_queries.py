"""Typed query/index qualification and paired storage workloads on synthetic data."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import platform
import resource
import sqlite3
import statistics
import subprocess
import tempfile
import time
from decimal import Decimal, localcontext
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cli', type=Path, required=True)
parser.add_argument('--rows', type=int, default=1000)
parser.add_argument('--output', type=Path)
parser.add_argument('--measure-rebuild-limit', action='store_true', help='Retain an expected bounded rebuild refusal as a failed stress operation, not a passing rebuild gate.')
options = parser.parse_args()
cli = options.cli.resolve(strict=True)
assert 100 <= options.rows <= 100000


def call(*args, error=None):
    process = subprocess.run([str(cli), *map(str, args)], capture_output=True, text=True, timeout=240)
    payload = json.loads(process.stderr if process.returncode else process.stdout)
    if error:
        assert process.returncode and payload['error']['code'] == error, payload
        return payload
    assert not process.returncode, payload
    return payload['result']


def measure(operation, repeats=3):
    times = []
    result = None
    for _ in range(repeats):
        started = time.perf_counter()
        result = operation()
        times.append(time.perf_counter() - started)
    return result, {'medianSeconds': round(statistics.median(times), 6), 'samplesSeconds': [round(x, 6) for x in times]}


def col(name, source=0):
    return {'source': source, 'column': name}


def field(name, source=0, aggregate=None, id=None):
    result = {'id': id or name, 'column': col(name, source)}
    if aggregate:
        result['aggregate'] = aggregate
    return result


def number(value):
    return format(Decimal(str(value)), 'f').rstrip('0').rstrip('.') if '.' in str(value) else str(value)


def decimal_order(a, b):
    try:
        a, b = Decimal(a), Decimal(b)
    except Exception:
        pass
    return (a > b) - (a < b)


class ExactSum:
    def __init__(self):
        self.value = Decimal(0)

    def step(self, value):
        if value is not None and value != '':
            with localcontext() as context:
                context.prec = 38
                self.value += Decimal(value)

    def finalize(self):
        return number(self.value)


with tempfile.TemporaryDirectory(prefix='sevra-query-') as directory:
    root = Path(directory)
    book = root / 'Queries.sevra'
    call('create', book, 'Query qualification')
    data = root / 'Orders.csv'
    data.write_text('sku,bucket,cost\n' + ''.join(f'SKU{i:06d},B{i % 20:02d},{i}.{i % 100:02d}\n' for i in range(options.rows)))
    started = time.perf_counter()
    dataset = call('import', book, data, '--role', 'values')['intake']['datasetIDs'][0]
    import_seconds = time.perf_counter() - started
    mapping = root / 'Regions.csv'
    mapping.write_text('bucket,region\n' + ''.join(f'B{i:02d},Region {i:02d}\n' for i in range(20)))
    lookup = call('import', book, mapping, '--role', 'values')['intake']['datasetIDs'][0]
    sources = [{'datasetID': ds, 'definitionID': call('table-schema', book, ds)['definitionID']} for ds in [dataset, lookup]]
    sources_main = sources[:1]
    filters = [{'column': col('cost'), 'op': 'gte', 'value': str(options.rows - 20)}, {'column': col('cost'), 'op': 'lt', 'value': str(options.rows)}]
    queries = {
        'range': {'sources': sources_main, 'select': [field('sku'), field('cost')], 'filters': filters, 'sort': [{'field': 'cost', 'descending': True}], 'limit': 100},
        'sort': {'sources': sources_main, 'select': [field('sku')], 'sort': [{'field': 'sku', 'descending': True}], 'limit': 50},
        'group': {'sources': sources_main, 'select': [field('bucket'), field('cost', aggregate='sum', id='total'), {'id': 'count', 'aggregate': 'countRows'}], 'groupBy': [col('bucket')], 'limit': 100},
        'join': {'sources': sources, 'joins': [{'kind': 'inner', 'left': col('bucket'), 'right': 'bucket'}], 'select': [field('sku'), field('region', 1)], 'filters': filters, 'sort': [{'field': 'sku'}], 'limit': 100},
    }
    history = call('commits', book, 1000)
    before = {}
    timing = {}
    plans = {}
    for name, query in queries.items():
        before[name], timing[name] = measure(lambda: call('table-query', book, json.dumps(query)))
        plans[name] = call('table-query-plan', book, json.dumps(query))
    assert len(before['range']['rows']) == 20
    assert before['sort']['rows'][0]['values']['sku'] == f'SKU{options.rows - 1:06d}'
    assert sum(int(row['values']['count']) for row in before['group']['rows']) == options.rows
    assert len(before['join']['rows']) == 20
    started = time.perf_counter()
    with ThreadPoolExecutor(2) as pool:
        competing_indexes = list(pool.map(lambda _: call('table-optimize', book, json.dumps(queries['range'])), range(2)))
    states = [value['decisions'][0]['state'] for value in competing_indexes]
    assert states.count('created') == 1 and states.count('existing') == 1, competing_indexes
    optimized = {'range': next(value for value in competing_indexes if value['decisions'][0]['state'] == 'created')}
    optimization_seconds = {'rangeCompetingWriters': round(time.perf_counter() - started, 6)}
    for name, query in queries.items():
        if name == 'range':
            continue
        started = time.perf_counter()
        optimized[name] = call('table-optimize', book, json.dumps(query))
        optimization_seconds[name] = round(time.perf_counter() - started, 6)
    assert call('commits', book, 1000) == history
    after = {}
    after_timing = {}
    for name, query in queries.items():
        after[name], after_timing[name] = measure(lambda: call('table-query', book, json.dumps(query)))
        assert before[name]['rows'] == after[name]['rows'], name
        assert any('sevra_perf_' in detail for detail in optimized[name]['afterPlan']), optimized[name]
    # Paired SQL storage comparison uses the same Python SQLite driver, warm
    # cache and exact Decimal adapter on both paths. It is not a native Swift
    # compiler/end-to-end timing, nor a historical binary speedup claim.
    connection = sqlite3.connect(book / 'workbook.sqlite')
    connection.create_collation('SEVRA_DECIMAL', decimal_order)
    connection.create_aggregate('exact_sum', 1, ExactSum)
    tables = {ds: connection.execute('select storage_table from datasets where id=?', (ds,)).fetchone()[0] for ds in [dataset, lookup]}
    q = lambda name: '"c_' + hashlib.sha256(name.encode()).hexdigest() + '"'
    native = '"' + tables[dataset] + '"'
    native_right = '"' + tables[lookup] + '"'
    baseline = '(SELECT i.data,d.ordinal,d.row_id FROM dataset_rows d JOIN heads h ON h.logical_id=d.logical_id JOIN items i ON i.id=h.item_id WHERE d.dataset_id=?)'
    native_sql = {
        'range': (f'SELECT {q("sku")},{q("cost")} FROM {native} WHERE {q("cost")}>=? AND {q("cost")}<? AND {q("cost")}<>\'\' ORDER BY {q("cost")} DESC,_sevra_ordinal,_sevra_row LIMIT 100', (str(options.rows - 20), str(options.rows))),
        'sort': (f'SELECT {q("sku")} FROM {native} ORDER BY {q("sku")} DESC,_sevra_ordinal,_sevra_row LIMIT 50', ()),
        'group': (f'SELECT {q("bucket")},exact_sum({q("cost")}),count(*) FROM {native} GROUP BY {q("bucket")} ORDER BY {q("bucket")}', ()),
        'join': (f'SELECT a.{q("sku")},b.{q("region")} FROM {native} a JOIN {native_right} b ON a.{q("bucket")}=b.{q("bucket")} WHERE a.{q("cost")}>=? AND a.{q("cost")}<? AND a.{q("cost")}<>\'\' ORDER BY a.{q("sku")},a._sevra_ordinal,a._sevra_row,b._sevra_ordinal,b._sevra_row LIMIT 100', (str(options.rows - 20), str(options.rows))),
    }
    extraction = lambda name, prefix='': f"json_extract({prefix}data,'$.{name}')"
    json_sql = {
        'range': (f'SELECT {extraction("sku")},{extraction("cost")} FROM {baseline} WHERE {extraction("cost")} COLLATE SEVRA_DECIMAL>=? AND {extraction("cost")} COLLATE SEVRA_DECIMAL<? ORDER BY {extraction("cost")} COLLATE SEVRA_DECIMAL DESC,ordinal,row_id LIMIT 100', (dataset, str(options.rows - 20), str(options.rows))),
        'sort': (f'SELECT {extraction("sku")} FROM {baseline} ORDER BY {extraction("sku")} DESC,ordinal,row_id LIMIT 50', (dataset,)),
        'group': (f'SELECT {extraction("bucket")},exact_sum({extraction("cost")}),count(*) FROM {baseline} GROUP BY {extraction("bucket")} ORDER BY {extraction("bucket")}', (dataset,)),
        'join': (f'SELECT {extraction("sku", "a.")},{extraction("region", "b.")} FROM {baseline} a JOIN {baseline} b ON {extraction("bucket", "a.")}={extraction("bucket", "b.")} WHERE {extraction("cost", "a.")} COLLATE SEVRA_DECIMAL>=? AND {extraction("cost", "a.")} COLLATE SEVRA_DECIMAL<? ORDER BY {extraction("sku", "a.")},a.ordinal,a.row_id,b.ordinal,b.row_id LIMIT 100', (dataset, lookup, str(options.rows - 20), str(options.rows))),
    }
    paired = {}
    for name in queries:
        native_rows, native_time = measure(lambda: connection.execute(*native_sql[name]).fetchall())
        json_rows, json_time = measure(lambda: connection.execute(*json_sql[name]).fetchall())
        assert native_rows == json_rows, (name, native_rows[:2], json_rows[:2])
        expected = [tuple(row['values'][selection['id']] for selection in queries[name]['select']) for row in after[name]['rows']]
        normalized = [tuple(str(value) if isinstance(value, int) else number(value) if selection.get('aggregate') == 'sum' or selection.get('column', {}).get('column') == 'cost' else value for value, selection in zip(row, queries[name]['select'])) for row in native_rows]
        assert normalized == expected, (name, normalized[:2], expected[:2])
        paired[name] = {'nativeSQL': native_time, 'sharedJSONSQL': json_time, 'exactResultsEqual': True}
    sizes = connection.execute("select name,sum(pgsize) from dbstat where substr(name,1,11)='sevra_perf_' group by name").fetchall()
    history_bytes = connection.execute('select sum(length(payload)) from committed_changes').fetchone()[0]
    sqlite_version = connection.execute('select sqlite_version()').fetchone()[0]
    connection.close()
    first = call('rows', book, dataset)[0]
    changed = dict(first['data'], cost='0.50')
    started = time.perf_counter()
    call('edit-row', book, first['id'], json.dumps(changed))
    edit_seconds = time.perf_counter() - started
    revision = call('inspect', book)['revision']
    started = time.perf_counter()
    rebuild_error = None
    rollback_verification_seconds = None
    if options.measure_rebuild_limit:
        process = subprocess.run([str(cli), 'table-rebuild', str(book), dataset, str(revision), 'repair-indexed-projection'], capture_output=True, text=True, timeout=240)
        rebuild_seconds = time.perf_counter() - started
        if process.returncode:
            rebuild_error = json.loads(process.stderr)['error']
            assert rebuild_error['code'] in ['deadline', 'change_limit'], rebuild_error
            verification_started = time.perf_counter()
            assert call('inspect', book)['revision'] == revision
            assert call('verify', book)['ok']
            rollback_verification_seconds = time.perf_counter() - verification_started
    else:
        call('table-rebuild', book, dataset, revision, 'repair-indexed-projection')
        rebuild_seconds = time.perf_counter() - started
    final = {name: call('table-query', book, json.dumps(query))['rows'] for name, query in queries.items()}
    for name in ['range', 'sort', 'join']:
        assert final[name] == after[name]['rows']
    data.unlink()
    mapping.unlink()
    replay = root / 'Replayed.sevra'
    started = time.perf_counter()
    call('reconstruct', book, replay)
    reconstruct_seconds = time.perf_counter() - started
    assert call('commits', replay, 1000) == call('commits', book, 1000)
    for name, query in queries.items():
        assert call('table-query', replay, json.dumps(query))['rows'] == final[name]
    portable = root / 'Portable.sevraz'
    call('export', book, portable)
    reopened = root / 'Portable.sevra'
    call('open-archive', portable, reopened)
    assert call('verify', reopened)['ok']
    assert call('table-query', reopened, json.dumps(queries['range']))['rows'] == final['range']
    call('table-query', reopened, json.dumps({'sql': 'DROP TABLE items'}), error='query')
    report = {
        'ok': rebuild_error is None, 'rows': options.rows, 'os': platform.platform(), 'machine': platform.machine(),
        'hardware': {'cpu': subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip(),
                     'physicalMemoryBytes': int(subprocess.check_output(['sysctl', '-n', 'hw.memsize'], text=True)),
                     'logicalCPUs': int(subprocess.check_output(['sysctl', '-n', 'hw.ncpu'], text=True))},
        'pythonSQLiteVersion': sqlite_version, 'intakeSeconds': round(import_seconds, 6),
        'cliBeforeIndex': timing, 'cliAfterIndex': after_timing, 'plansBefore': plans, 'optimizations': optimized,
        'competingIndexWriters': competing_indexes, 'optimizationSeconds': optimization_seconds,
        'pairedStorageSQL': paired, 'pairedStorageScope': 'same Python SQLite driver/cache/Decimal adapter on both representations; not Swift compiler or historical binary timing',
        'indexBytes': dict(sizes), 'sqliteBytes': (book / 'workbook.sqlite').stat().st_size, 'initialHistoryBytes': history_bytes,
        'indexedEditSeconds': round(edit_seconds, 6), 'indexedRebuildSeconds': round(rebuild_seconds, 6),
        'indexedRebuildError': rebuild_error,
        'rollbackVerificationSeconds': rollback_verification_seconds,
        'reconstructionSeconds': round(reconstruct_seconds, 6),
        'peakChildResidentBytes': resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss * (1 if platform.system() == 'Darwin' else 1024),
        'peakMemoryScope': 'maximum individual child lifetime RSS, not aggregate memory or hard heap bound',
        'queryResultsEqual': True, 'indexOperationsDoNotPublishBusinessHistory': True,
        'repairCompleted': rebuild_error is None, 'inertReconstruction': True, 'portableReopen': True,
        'scope': 'synthetic stored scalar range/sort/group/equality-join qualification, no full Excel or release claim',
    }
    if options.output:
        options.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
