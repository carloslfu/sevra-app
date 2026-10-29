"""Packaged managed storage, projection repair and inert reconstruction proof."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import platform
import resource
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cli', type=Path, required=True)
parser.add_argument('--rows', type=int, default=1000)
parser.add_argument('--output', type=Path)
options = parser.parse_args()
cli = options.cli.resolve(strict=True)
assert 1 <= options.rows <= 100000


def run(*args, success=True):
    process = subprocess.run([str(cli), *map(str, args)], text=True, capture_output=True, timeout=240)
    assert (process.returncode == 0) == success, process.stdout + process.stderr
    result = json.loads(process.stdout if success else process.stderr)
    return result.get('result', result)


def decimal_order(a, b):
    from decimal import Decimal, InvalidOperation
    try:
        first, second = Decimal(a), Decimal(b)
    except InvalidOperation:
        first, second = a, b
    return (first > second) - (first < second)


def connect(book):
    connection = sqlite3.connect(book / 'workbook.sqlite')
    connection.create_collation('SEVRA_DECIMAL', decimal_order)
    return connection


with tempfile.TemporaryDirectory(prefix='sevra-managed-') as directory:
    folder = Path(directory)
    book = folder / 'Managed.sevra'
    run('create', book, 'Managed native datasets')
    csv = folder / 'Rows.csv'
    csv.write_text('sku,quantity\n' + ''.join(f'part-{index:08d},{index % 23}\n' for index in range(options.rows)))
    started = time.monotonic()
    intake = run('import', book, csv, '--role', 'values', '--token', 'capture')
    intake_seconds = time.monotonic() - started
    dataset = intake['intake']['datasetIDs'][0]
    assert run('tables', book)[0]['rowCount'] == options.rows
    schema = run('table-schema', book, dataset)
    assert schema['representation'] == 'managed-native' and schema['version'] == 1
    rows = run('rows', book, dataset)
    with connect(book) as db:
        table = db.execute('select storage_table from datasets where id=?', (dataset,)).fetchone()[0]
        assert db.execute(f'select count(*) from "{table}"').fetchone()[0] == options.rows
        columns = db.execute(f'pragma table_info("{table}")').fetchall()
        assert len(columns) == 7
        history_bytes = db.execute('select sum(length(payload)) from committed_changes').fetchone()[0]
        version, = db.execute('select sqlite_version()').fetchone()
        limits = [row[0] for row in db.execute('pragma compile_options') if row[0].startswith(('MAX_COLUMN=', 'MAX_VARIABLE_NUMBER=', 'MAX_FUNCTION_ARG='))]
        ordinal_plan = db.execute(f'explain query plan select _sevra_item from "{table}" order by _sevra_ordinal,_sevra_row limit 200').fetchall()
        assert any(table + '_order' in row[3] for row in ordinal_plan), ordinal_plan
        expected_revision = int(db.execute("select value from meta where key='revision'").fetchone()[0])
    def rebuild(token):
        process = subprocess.run([str(cli), 'table-rebuild', str(book), dataset, str(expected_revision), token], capture_output=True, text=True, timeout=240)
        return process
    started = time.monotonic()
    with ThreadPoolExecutor(2) as pool:
        writers = list(pool.map(rebuild, ['writer-one', 'writer-two']))
    rebuild_seconds = time.monotonic() - started
    assert sum(process.returncode == 0 for process in writers) == 1, [process.stdout + process.stderr for process in writers]
    assert next(json.loads(process.stderr)['error']['code'] for process in writers if process.returncode) == 'stale_revision'
    winning = 'writer-one' if writers[0].returncode == 0 else 'writer-two'
    assert rebuild(winning).returncode == 0
    assert run('rows', book, dataset) == rows
    with connect(book) as db:
        data_column = next(row[1] for row in columns if row[1].startswith('c_'))
        db.execute(f'update "{table}" set "{data_column}"=? where _sevra_ordinal=0', ('damaged projection',))
        db.commit()
        expected_revision = int(db.execute("select value from meta where key='revision'").fetchone()[0])
    assert run('verify', book, success=False)['error']['code'] == 'managed_projection'
    run('table-rebuild', book, dataset, expected_revision, 'repair')
    assert run('rows', book, dataset) == rows
    assert run('verify', book)['ok']
    csv.unlink()
    started = time.monotonic()
    rebuilt = folder / 'Replayed.sevra'
    assert run('reconstruct', book, rebuilt)['execution'] == 'inert'
    replay_seconds = time.monotonic() - started
    assert run('rows', rebuilt, dataset) == rows
    assert run('table-schema', rebuilt, dataset) == schema
    assert run('commits', rebuilt, 1000) == run('commits', book, 1000)
    archive = folder / 'Portable.sevraz'
    run('export', rebuilt, archive)
    portable = folder / 'Portable.sevra'
    run('open-archive', archive, portable)
    assert run('verify', portable)['ok'] and run('rows', portable, dataset) == rows
    result = {'peakChildResidentBytes': resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss * (1 if platform.system() == 'Darwin' else 1024),
              'peakMemoryScope': 'maximum individual child lifetime RSS, not aggregate concurrent memory',
              'os': platform.platform(), 'machine': platform.machine(),
              'rows': options.rows, 'sqliteVersion': version, 'sqliteLimits': limits,
              'intakeSeconds': round(intake_seconds, 3), 'rebuildCompetitionSeconds': round(rebuild_seconds, 3),
              'reconstructionSeconds': round(replay_seconds, 3), 'sqliteBytes': (book / 'workbook.sqlite').stat().st_size,
              'initialHistoryBytes': history_bytes, 'ordinalQueryPlan': ordinal_plan,
              'nativeScalarColumns': True, 'competingWriters': 2, 'exactlyOneWinner': True,
              'sameTokenRetry': True, 'corruptionDetected': True, 'canonicalRepair': True,
              'inertRepairReconstruction': True, 'exactHistory': True, 'portableReopen': True,
              'scope': 'managed storage foundation; ordinal index only; no range/join/group speed or full MJ qualification'}
    print(json.dumps(result, indent=2))
    if options.output:
        options.output.write_text(json.dumps(result, indent=2) + '\n')
