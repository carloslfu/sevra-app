#!/usr/bin/env python3
"""Qualify real condition candidates across competing writers and process death."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import select
import shutil
import sqlite3
import subprocess
import tempfile
import time


def barrier(process, timeout=45):
    deadline = time.monotonic() + timeout
    data = b''
    while b'\n' not in data:
        left = deadline - time.monotonic()
        assert left > 0 and select.select([process.stdout], [], [], left)[0], 'Publication barrier timed out'
        chunk = os.read(process.stdout.fileno(), 4096)
        assert chunk, 'Worker exited before publication barrier'
        data += chunk
        assert len(data) <= 65_536, 'Oversized publication barrier'
    line, rest = data.split(b'\n', 1)
    assert not rest
    return json.loads(line)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', required=True, type=Path)
    parser.add_argument('--worker', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    cli, worker = args.cli.resolve(strict=True), args.worker.resolve(strict=True)
    report = {'version': 1, 'ok': False, 'calls': [],
              'cliSHA256': hashlib.sha256(cli.read_bytes()).hexdigest(),
              'workerSHA256': hashlib.sha256(worker.read_bytes()).hexdigest(),
              'scope': 'actual owned inventory-condition candidate selection, captured dispatch and shared admission; no native UI, timer or model qualification'}
    try:
        with tempfile.TemporaryDirectory(prefix='sevra-condition-dispatch-') as directory:
            root = Path(directory)

            def clean(value):
                return str(value).replace(str(root), '<fixture>')

            def call(*arguments, error=False):
                p = subprocess.run([str(cli), *map(str, arguments)], capture_output=True, text=True, timeout=90)
                record = {'arguments': [clean(a) for a in arguments], 'returncode': p.returncode,
                          'stdout': clean(p.stdout), 'stderr': clean(p.stderr)}
                report['calls'].append(record)
                if error:
                    assert p.returncode and not p.stdout and json.loads(p.stderr)['ok'] is False, record
                    return json.loads(p.stderr)
                assert p.returncode == 0 and not p.stderr, record
                return json.loads(p.stdout)['result']

            def setup(book, targets=1, admitted=0):
                p = subprocess.run([str(worker), '--condition-dispatch-fixture', str(book), str(targets), str(admitted)],
                                   capture_output=True, text=True, timeout=180)
                assert p.returncode == 0 and not p.stderr, (p.stdout, p.stderr)
                return json.loads(p.stdout)

            def counts(book):
                with sqlite3.connect(book / 'workbook.sqlite') as db:
                    return [db.execute('SELECT count(*) FROM ' + table).fetchone()[0] for table in
                            ['automation_runs', 'automatic_roots', 'automatic_admissions', 'automatic_root_members', 'automatic_independent_inputs']]

            book = root / 'Race.sevra'
            fixture = setup(book, 34, 25)
            assert counts(book) == [25, 1, 25, 25, 25]
            processes = []
            outcomes = []
            try:
                for definition in fixture['remaining']:
                    processes.append(subprocess.Popen([str(worker), '--condition-dispatch-worker', str(book), definition],
                                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True))
                for process in processes:
                    stdout, stderr = process.communicate(timeout=120)
                    outcomes.append({'returncode': process.returncode, 'stdout': clean(stdout), 'stderr': clean(stderr)})
            finally:
                for process in processes:
                    if process.poll() is None:
                        process.kill()
                        process.communicate(timeout=20)
            success = [r for r in outcomes if r['returncode'] == 0]
            refused = [r for r in outcomes if r['returncode'] != 0]
            assert len(success) == 7 and len(refused) == 2, outcomes
            assert all(json.loads(r['stderr'])['code'] == 'causal_work_limit' for r in refused), refused
            assert counts(book) == [32, 1, 32, 32, 32]
            with sqlite3.connect(book / 'workbook.sqlite') as db:
                assert db.execute('PRAGMA user_version').fetchone()[0] == 31
                assert db.execute('SELECT count(*) FROM automation_occurrences').fetchone()[0] == 0
                assert db.execute('SELECT count(*) FROM automation_runs WHERE occurrence_id IS NOT NULL OR candidate_id IS NULL').fetchone()[0] == 0
                assert db.execute("SELECT count(*) FROM condition_candidates WHERE state='pending'").fetchone()[0] == 2
                assert db.execute("SELECT count(*) FROM condition_candidates WHERE state='dispatched'").fetchone()[0] == 32
            run = fixture['admitted'][0]['runID']
            origin = call('automation-causality', book, run)
            assert origin['rootCharges'][0]['admittedRuns'] == 32
            assert call('verify', book)['ok']
            rebuilt = root / 'Rebuilt.sevra'
            call('reconstruct', book, rebuilt)
            assert call('verify', rebuilt)['ok']
            assert call('automation-causality', rebuilt, run) == origin
            assert counts(rebuilt) == counts(book)
            damaged = []
            for damage in ['owner', 'candidate-state', 'observation', 'dispatch', 'binding']:
                bad = root / (damage + '.sevra')
                shutil.copytree(book, bad)
                with sqlite3.connect(bad / 'workbook.sqlite') as db:
                    if damage == 'owner':
                        db.execute("UPDATE condition_consumers SET owner_logical='foreign'")
                    elif damage == 'candidate-state':
                        db.execute("UPDATE condition_candidates SET state='pending' WHERE id=(SELECT candidate_id FROM automation_runs LIMIT 1)")
                    elif damage == 'observation':
                        db.execute("UPDATE condition_observations SET payload=json_set(payload,'$.quantity','99') WHERE id=(SELECT observation_id FROM condition_candidates WHERE state='dispatched' LIMIT 1)")
                    elif damage == 'dispatch':
                        db.execute("UPDATE items SET data=json_set(data,'$.trigger.inputSetHash','altered') WHERE id=(SELECT dispatch_source FROM automation_runs LIMIT 1)")
                    else:
                        db.execute('DELETE FROM automation_runs WHERE run_id=?', [run])
                reply = call('verify', bad, error=True)
                damaged.append({'damage': damage, 'reply': reply})
            deaths = []
            for stage in ['prepared', 'committed']:
                path = root / (stage + '.sevra')
                data = setup(path)
                definition = data['definitions'][0]
                process = subprocess.Popen([str(worker), '--condition-dispatch-worker', str(path), definition, stage],
                                           stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                try:
                    reached = barrier(process)
                    assert reached['stage'] == stage and reached['operationSaved'] == 1 and reached['headCommitID']
                    process.kill()
                    stdout, stderr = process.communicate(timeout=20)
                    assert process.returncode == -9 and not stdout and not stderr, (stdout, stderr)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.communicate(timeout=20)
                expected = [0, 0, 0, 0, 0] if stage == 'prepared' else [1, 1, 1, 1, 1]
                assert counts(path) == expected, counts(path)
                with sqlite3.connect(path / 'workbook.sqlite') as db:
                    assert db.execute('SELECT state FROM condition_candidates').fetchone()[0] == ('pending' if stage == 'prepared' else 'dispatched')
                assert call('verify', path)['ok']
                copy = root / ('copy-' + stage + '.sevra')
                call('reconstruct', path, copy)
                assert call('verify', copy)['ok'] and counts(copy) == expected
                if stage == 'prepared':
                    resumed = subprocess.run([str(worker), '--condition-dispatch-worker', str(path), definition], capture_output=True, text=True, timeout=60)
                    assert resumed.returncode == 0, resumed.stderr
                    assert counts(path) == [1, 1, 1, 1, 1]
                    assert call('verify', path)['ok']
                deaths.append({'stage': stage, 'signal': 'SIGKILL', 'barrier': reached, 'reopenedCounts': expected})
            report.update({'ok': True, 'writers': outcomes, 'admittedBeforeRace': 25, 'admittedByRace': 7,
                           'refusedByRace': 2, 'finalCounts': [32, 1, 32, 32, 32],
                           'damagedCopies': damaged, 'publicationDeaths': deaths,
                           'limits': ['Local captured writer only; independent replicas have no shared quota.',
                                      'Native condition owner/authoring/background and real-model interaction remain unqualified.']})
    finally:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'ok': report['ok'], 'calls': len(report['calls']), 'writers': len(report['writers']), 'deaths': len(report['publicationDeaths'])}))


if __name__ == '__main__':
    main()
