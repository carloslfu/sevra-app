#!/usr/bin/env python3
"""Current-format synthetic CLI journeys for bounded bulk intake: saved-change limits,
cancellation, a killed process and exact resumption from the same original."""
import argparse
import hashlib
import json
from pathlib import Path
import signal
import sqlite3
import subprocess
import tempfile
import time

from check_table_updates import write_xlsx

BATCH_ROWS = 1000


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_rows(path, count):
    lines = ['sku,note,amount']
    lines += [f'SKU{n:06d},"line {n}, with comma",{n % 97}.50' for n in range(count)]
    path.write_text('\n'.join(lines) + '\n')


def saved(book):
    """Reads committed progress the way a second process does, without taking the write lock."""
    connection = sqlite3.connect(f'file:{book / "workbook.sqlite"}?mode=ro', uri=True, timeout=5)
    try:
        rows = connection.execute("SELECT value FROM meta WHERE key LIKE 'intake:%'").fetchall()
    finally:
        connection.close()
    return [json.loads(row[0]) for row in rows]


def batches(book):
    connection = sqlite3.connect(f'file:{book / "workbook.sqlite"}?mode=ro', uri=True, timeout=5)
    try:
        return connection.execute("SELECT count(*) FROM operations WHERE kind='import_batch'").fetchone()[0]
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, default=Path('output/native/bin/sevra'))
    cli = parser.parse_args().cli.resolve()
    checks = []

    def run(*args, error=None, timeout=240):
        reply = subprocess.run([str(cli), *map(str, args)], capture_output=True, text=True, timeout=timeout)
        data = json.loads(reply.stdout if reply.returncode == 0 else reply.stderr)
        if error:
            assert reply.returncode != 0 and data['error']['code'] == error, data
            return data['error']
        assert reply.returncode == 0 and data['ok'], data
        return data['result']

    def checked(name, condition):
        assert condition, name
        checks.append(name)

    def all_rows(book, table, expected):
        rows, offset = [], 0
        while len(rows) < expected + 1:
            page = run('rows', book, table, offset)
            if not page:
                break
            rows += page
            offset += len(page)
        return rows

    def exact(book, table, count, column='sku'):
        """Every expected row once, in source order."""
        values = [row['data'][column] for row in all_rows(book, table, count)]
        return values == [f'SKU{n:06d}' for n in range(count)]

    def interrupted(book, arguments, send, after=BATCH_ROWS):
        """Starts a long command and signals it once more rows than `after` are saved."""
        process = subprocess.Popen([str(cli), *map(str, arguments)],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        seen, deadline = [], time.monotonic() + 180
        while process.poll() is None and time.monotonic() < deadline:
            try:
                status = saved(book)
            except sqlite3.Error:
                status = []
            done = sum(entry['completed'] for entry in status)
            if not seen or seen[-1] != done:
                seen.append(done)
            if done > after:
                process.send_signal(send)
                break
            time.sleep(0.01)
        out, err = process.communicate(timeout=180)
        return process.returncode, out, err, seen

    with tempfile.TemporaryDirectory(prefix='sevra-bulk-intake-') as temporary:
        root = Path(temporary)

        # Long values overflow a 1,000 row batch. The same source now commits in smaller ones.
        wide = root / 'Wide.csv'
        note = 'n' * 16_000
        wide.write_text('sku,note\n' + ''.join(f'SKU{n:06d},{note}{n}\n' for n in range(1100)))
        digest = sha256(wide)
        book = root / 'Wide.sevra'
        run('create', book, 'Synthetic wide')
        imported = run('import', book, wide, '--role', 'values')
        table = imported['intake']['datasetIDs'][0]
        checked('wide rows commit in batches of at most 6 MB of values',
                imported['intake']['state'] == 'ready' and batches(book) == 3)
        rows = all_rows(book, table, 1100)
        checked('wide rows keep exact order and full values',
                [row['data']['sku'] for row in rows] == [f'SKU{n:06d}' for n in range(1100)]
                and rows[1099]['data']['note'] == f'{note}1099')
        checked('wide status reports every row saved',
                [(s['completed'], s['total'], s['state']) for s in saved(book)]
                == [(1100, 1100, 'ready')])
        checked('wide original stays byte-identical and the workbook verifies',
                sha256(wide) == digest and run('verify', book)['ok'] is True)

        # Long headings make rows large without long values, so the byte budget cannot see
        # them. A rejected batch saves nothing and a smaller one starts at the same row.
        headings = ['sku'] + [f'{n:04d}_' + 'h' * 90 for n in range(300)]
        keyed = root / 'Keyed.csv'
        keyed.write_text(','.join(headings) + '\n' + ''.join(
            f'SKU{n:06d},' + ','.join('x' for _ in headings[1:]) + '\n' for n in range(1050)))
        book = root / 'Keyed.sevra'
        run('create', book, 'Synthetic keyed')
        imported = run('import', book, keyed, '--role', 'values')
        table = imported['intake']['datasetIDs'][0]
        checked('a batch over the limit splits and keeps every row in order',
                imported['intake']['state'] == 'ready' and batches(book) == 3
                and exact(book, table, 1050))

        # Cancelling keeps committed batches, never part of one, and says what was saved.
        source = root / 'Bulk.csv'
        write_rows(source, 4200)
        digest = sha256(source)
        book = root / 'Cancelled.sevra'
        run('create', book, 'Synthetic cancelled')
        code, _, err, seen = interrupted(
            book, ['import', book, source, '--role', 'values'], signal.SIGINT)
        checked('cancellation stops the command with a cancelled result',
                code != 0 and json.loads(err)['error']['code'] == 'cancelled')
        status = run('intake-status', book)
        entry = status['tables'][0]
        job = status['jobs'][0]
        table = entry['datasetID']
        checked('progress only moves forward and lands on committed batches',
                seen == sorted(seen) and all(value % BATCH_ROWS == 0 for value in seen))
        checked('a cancelled import is partial and counts only committed rows',
                entry['state'] == 'partial' and entry['total'] == 4200
                and 0 < entry['completed'] < 4200 and entry['completed'] % BATCH_ROWS == 0
                and exact(book, table, entry['completed']))
        checked('the cancelled job states the saved count',
                job['state'] == 'cancelled'
                and f"Stopped with {entry['completed']:,} rows saved." in job['detail'])
        checked('a stopped import appears once among the items needing attention',
                len(status['extraction']) == 1 and status['extraction'][0]['job_id'] == job['id'])
        checked('the partial workbook verifies', run('verify', book)['ok'] is True)
        edited = run('rows', book, table)[0]
        values = {**edited['data'], 'note': 'corrected while stopped'}
        run('edit-row', book, edited['id'], json.dumps(values))
        resumed = run('intake-resume', book, job['id'])
        first = run('rows', book, table)[0]
        checked('resuming saves only the remaining rows, in order',
                resumed['state'] == 'ready' and exact(book, table, 4200))
        checked('resuming keeps an edit made to a saved row',
                first['data']['note'] == 'corrected while stopped')
        again = run('intake-resume', book, job['id'])
        checked('a repeated resume changes nothing',
                again['state'] == 'ready' and exact(book, table, 4200)
                and [s['completed'] for s in saved(book)] == [4200])
        archive = root / 'Finished.sevraz'
        reopened = root / 'Reopened.sevra'
        run('export', book, archive)
        run('open-archive', archive, reopened)
        checked('a finished import exports and reopens with every row',
                exact(reopened, table, 4200) and run('verify', reopened)['ok'] is True)
        checked('the original stays byte-identical', sha256(source) == digest)

        # A killed process leaves no half batch and a later attempt continues after it.
        book = root / 'Killed.sevra'
        run('create', book, 'Synthetic killed')
        code, _, _, _ = interrupted(
            book, ['import', book, source, '--role', 'values', '--token', 'bulk'], signal.SIGKILL)
        first = saved(book)[0]
        job = run('intake-status', book)['jobs'][0]
        checked('a killed process leaves whole batches',
                code == -signal.SIGKILL and first['state'] == 'partial'
                and first['completed'] % BATCH_ROWS == 0
                and exact(book, first['datasetID'], first['completed']))
        reached = first['completed']
        code, _, _, seen = interrupted(
            book, ['intake-resume', book, job['id']], signal.SIGKILL, after=reached)
        second = saved(book)[0]
        checked('a second attempt continues after the saved rows',
                code == -signal.SIGKILL and second['completed'] > reached
                and all(value >= reached for value in seen))
        checked('a killed import still verifies', run('verify', book)['ok'] is True)
        run('resume-intake', book, job['sourceID'])
        checked('resuming after two kills finishes without duplicates',
                exact(book, first['datasetID'], 4200) and saved(book)[0]['state'] == 'ready')
        repeat = run('import', book, source, '--role', 'values', '--token', 'bulk')
        checked('the same import token returns the finished table',
                repeat['intake']['datasetIDs'] == [first['datasetID']]
                and exact(book, first['datasetID'], 4200))

        # A partial table that changed underneath the import is not silently completed.
        book = root / 'Changed.sevra'
        run('create', book, 'Synthetic changed')
        interrupted(book, ['import', book, source, '--role', 'values'], signal.SIGINT)
        entry = run('intake-status', book)['tables'][0]
        job = run('intake-status', book)['jobs'][0]
        table = entry['datasetID']
        schema = run('table-schema', book, table)
        run('table-edit-schema', book, table, schema['version'], schema['definitionID'],
            json.dumps({'title': 'Renamed while stopped'}), 'rename')
        run('intake-resume', book, job['id'], error='import_changed')
        checked('a changed partial table refuses to resume and keeps its rows',
                saved(book)[0]['completed'] == entry['completed']
                and exact(book, table, entry['completed']))

        # A very long row takes a batch of its own. One beyond the record bound stops there.
        field = 'x' * 900_000
        def long_rows(name, cells):
            filler = ','.join('a' for _ in range(cells))
            large = root / f'{name}.csv'
            large.write_text('sku,' + ','.join(f'c{n}' for n in range(cells)) + '\n'
                             f'SKU000000,{filler}\nSKU000001,{filler}\n'
                             'SKU000002,' + ','.join(field for _ in range(cells)) + '\n'
                             f'SKU000003,{filler}\n')
            book = root / f'{name}.sevra'
            run('create', book, f'Synthetic {name}')
            return book, large

        book, large = long_rows('Long', 17)
        imported = run('import', book, large, '--role', 'values')
        table = imported['intake']['datasetIDs'][0]
        checked('a 15 MB row saves in full between its neighbours',
                imported['intake']['state'] == 'ready' and batches(book) == 3
                and exact(book, table, 4) and run('rows', book, table)[2]['data']['c16'] == field)
        book, large = long_rows('Longest', 30)
        failure = run('import', book, large, '--role', 'values', error='limit')
        status = run('intake-status', book)
        checked('a row over the record bound is named and earlier rows stay',
                'Row 3 is too large' in failure['message']
                and status['tables'][0]['completed'] == 2
                and status['jobs'][0]['state'] == 'failed'
                and 'Row 3 is too large' in status['jobs'][0]['detail'])
        run('intake-resume', book, status['jobs'][0]['id'], error='limit')
        checked('retrying the oversized row repeats nothing',
                exact(book, status['tables'][0]['datasetID'], 2)
                and run('verify', book)['ok'] is True)

        # Every worksheet resumes, including one that had not started.
        sheets = root / 'Sheets.xlsx'
        write_xlsx(sheets, {
            name: {n + 1: [f'SKU{n:06d}', n] for n in range(count)}
            for name, count in (('First', 2300), ('Second', 1200))})
        digest = sha256(sheets)
        book = root / 'Sheets.sevra'
        run('create', book, 'Synthetic sheets')
        interrupted(book, ['import', book, sheets, '--role', 'values'], signal.SIGINT)
        job = run('intake-status', book)['jobs'][0]
        resumed = run('intake-resume', book, job['id'])
        tables = {entry['title'].rsplit(' ', 1)[-1]: entry for entry in saved(book)}
        checked('both worksheets finish exactly after a stop',
                resumed['state'] == 'ready' and len(resumed['datasetIDs']) == 2
                and (tables['First']['completed'], tables['Second']['completed']) == (2300, 1200)
                and exact(book, tables['First']['datasetID'], 2300, 'c1')
                and exact(book, tables['Second']['datasetID'], 1200, 'c1')
                and sha256(sheets) == digest and run('verify', book)['ok'] is True)

    print(json.dumps({'checks': checks, 'count': len(checks)}, indent=2))


if __name__ == '__main__':
    main()
