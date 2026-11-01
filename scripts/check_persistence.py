"""Current-format CLI reconstruction, conversation coexistence and bounded scaling."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import signal
import sqlite3
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cli', type=Path, required=True)
parser.add_argument('--rows', type=int, default=1000)
options = parser.parse_args()
cli = options.cli.resolve(strict=True)
assert 1 <= options.rows <= 100000

def run(*args, success=True):
    result = subprocess.run([str(cli), *map(str, args)], text=True, capture_output=True, timeout=180)
    assert (result.returncode == 0) == success, result.stdout + result.stderr
    envelope = json.loads(result.stdout if success else result.stderr)
    assert envelope['ok'] == success
    return envelope.get('result', envelope)

with tempfile.TemporaryDirectory(prefix='sevra-persistence-') as directory:
    folder = Path(directory)
    book = folder / 'Original.sevra'
    run('create', book, 'Reconstruction fixture')
    csv = folder / 'Rows.csv'
    csv.write_text('sku,quantity\n' + ''.join(f'{index:08d},{index % 23}\n' for index in range(options.rows)))
    started = time.monotonic()
    imported = run('import', book, csv, '--role', 'values', '--token', 'capture-once')
    intake_seconds = time.monotonic() - started
    dataset = imported['intake']['datasetIDs'][0]
    assert run('tables', book)[0]['rowCount'] == options.rows
    revision = run('inspect', book)['revision']
    saved_commits = len(run('commits', book, 1000))
    def write(index):
        return run('add', book, json.dumps({'title': f'Writer {index}', 'text': 'Independent evidence', 'token': f'write-{index}', 'status': 'accepted'}))
    with ThreadPoolExecutor(max_workers=4) as pool:
        written = list(pool.map(write, range(12)))
    assert len({item['id'] for item in written}) == 12
    # A reported write must be in the file the next process opens, once each.
    assert [run('read', book, item['id'])['item']['title'] for item in written] == [f'Writer {index}' for index in range(12)]
    assert run('inspect', book)['revision'] == revision + 12
    assert len(run('commits', book, 1000)) == saved_commits + 12
    commits = run('commits', book, 20)
    assert len(commits) >= 12 and all(item['actor']['kind'] == 'programmatic' for item in commits)
    assert len({item['writerID'] for item in commits}) >= 12
    run('history', book, 'main') # original conversation command must remain separate
    rejected = run('commits', book, 'main', success=False)
    assert rejected['error']['code'] == 'limit'
    assert write(0)['id'] == written[0]['id']
    assert run('commits', book, 20) == commits
    with sqlite3.connect(book / 'workbook.sqlite') as connection:
        before = connection.execute('select count(*) from items').fetchone()[0]
        expected = connection.execute('select id,previous_id,hash,recorded,writer_id,actor,row_changes from committed_changes order by rowid').fetchall()
    csv.unlink()
    started = time.monotonic()
    rebuilt = folder / 'Rebuilt.sevra'
    result = run('reconstruct', book, rebuilt)
    replay_seconds = time.monotonic() - started
    assert result['execution'] == 'inert'
    assert run('tables', rebuilt)[0]['rowCount'] == options.rows
    assert run('rows', rebuilt, dataset) == run('rows', book, dataset)
    with sqlite3.connect(rebuilt / 'workbook.sqlite') as connection:
        assert connection.execute('select count(*) from items').fetchone()[0] == before
        assert connection.execute('select id,previous_id,hash,recorded,writer_id,actor,row_changes from committed_changes order by rowid').fetchall() == expected
    assert run('verify', rebuilt)['ok']
    cancelled = folder / 'Cancelled reconstruction.sevra'
    process = subprocess.Popen([str(cli), 'reconstruct', str(book), str(cancelled)], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    deadline = time.monotonic() + 30
    observed = False
    try:
        while process.poll() is None and time.monotonic() < deadline:
            for staging in folder.glob('.sevra-reconstruct-*'):
                candidate = staging / 'workbook.sevra' / 'workbook.sqlite'
                if not candidate.exists():
                    continue
                try:
                    with sqlite3.connect(candidate, timeout=0.05) as connection:
                        observed = connection.execute('select count(*) from committed_changes').fetchone()[0] > 0
                except sqlite3.OperationalError:
                    pass
                if observed:
                    break
            if observed:
                process.send_signal(signal.SIGINT)
                break
            time.sleep(0.005)
        stdout, stderr = process.communicate(timeout=30)
        assert observed, 'No staged committed prefix observed before cancellation'
        assert process.returncode == 1, stdout + stderr
        assert json.loads(stderr)['error']['code'] == 'cancelled', stderr
        assert not cancelled.exists() and not list(folder.glob('.sevra-reconstruct-*'))
    finally:
        if process.poll() is None:
            process.kill()
            process.communicate()
    archive = folder / 'Portable.sevraz'
    run('export', rebuilt, archive)
    portable = folder / 'Portable.sevra'
    run('open-archive', archive, portable)
    run('reconstruct', portable, folder / 'Portable replay.sevra')
    run('reconstruct', book, rebuilt, success=False)
    print(json.dumps({'rows': options.rows, 'commits': len(expected), 'concurrentWriters': 12, 'intakeSeconds': round(intake_seconds, 3), 'reconstructionSeconds': round(replay_seconds, 3), 'sqliteBytes': (book / 'workbook.sqlite').stat().st_size, 'duplicateRetry': True, 'exactHistory': True, 'portableReconstruction': True, 'conversationHistoryPreserved': True, 'cancelledDuringApply': True}))
