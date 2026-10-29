#!/usr/bin/env python3
"""Race shared business-root budgets and kill the actual admission publisher."""
import argparse
import hashlib
import json
from pathlib import Path
import select
import shutil
import sqlite3
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', required=True, type=Path)
    parser.add_argument('--worker', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    cli, worker = args.cli.resolve(strict=True), args.worker.resolve(strict=True)
    report = {'version': 1, 'cliSHA256': hashlib.sha256(cli.read_bytes()).hexdigest(),
              'workerSHA256': hashlib.sha256(worker.read_bytes()).hexdigest(), 'calls': [],
              'scope': 'trusted shared business-root admission; no actual condition selection or dispatch'}
    with tempfile.TemporaryDirectory(prefix='sevra-shared-admissions-') as directory:
        folder = Path(directory)

        def call(*arguments, error=None):
            p = subprocess.run([str(cli), *map(str, arguments)], capture_output=True, text=True, timeout=90)
            clean = lambda text: text.replace(str(folder), '<fixture>')
            report['calls'].append({'arguments': [clean(str(a)) for a in arguments],
                                    'returncode': p.returncode, 'stdout': clean(p.stdout), 'stderr': clean(p.stderr)})
            if error:
                assert p.returncode and json.loads(p.stderr)['error']['code'] == error, report['calls'][-1]
                return
            assert p.returncode == 0 and not p.stderr, report['calls'][-1]
            return json.loads(p.stdout)['result']

        book = folder / 'Shared.sevra'
        p = subprocess.run([str(worker), '--shared-admission-fixture', str(book)], capture_output=True, text=True, timeout=90)
        assert p.returncode == 0 and not p.stderr, (p.stdout, p.stderr)
        fixture = json.loads(p.stdout)
        source, run = fixture['sourceID'], fixture['runID']
        before = call('automation-causality', book, run)
        assert before['rootCharges'][0]['admittedRuns'] == 25
        with sqlite3.connect(book / 'workbook.sqlite') as db:
            assert db.execute('PRAGMA user_version').fetchone()[0] == 29
            workbook = db.execute("SELECT value FROM meta WHERE key='workbook-id'").fetchone()[0]
            commit = db.execute('SELECT commit_id FROM business_inputs WHERE source_id=?', [source]).fetchone()[0]
        canonical = json.dumps(['business-input-v1', workbook, commit], ensure_ascii=False, separators=(',', ':'))
        root = 'business-root:' + hashlib.sha256(canonical.encode()).hexdigest()
        assert before['origin']['roots'] == [root] and before['origin']['independentInputs'] == [source]
        workers = []
        outcomes = []
        try:
            for definition in fixture['children']:
                workers.append(subprocess.Popen([str(worker), '--shared-admission-worker', str(book), definition, source],
                                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True))
            for process in workers:
                stdout, stderr = process.communicate(timeout=90)
                outcomes.append({'returncode': process.returncode, 'stdout': stdout, 'stderr': stderr})
        finally:
            for process in workers:
                if process.poll() is None:
                    process.kill()
                    process.communicate(timeout=20)
        successes = [outcome for outcome in outcomes if outcome['returncode'] == 0]
        failures = [outcome for outcome in outcomes if outcome['returncode'] != 0]
        assert len(successes) == 7 and len(failures) == 2, outcomes
        assert all(json.loads(outcome['stderr'])['code'] == 'causal_work_limit' for outcome in failures), failures
        trace = call('automation-causality', book, run)
        assert trace['rootCharges'] == [{'rootID': root, 'admittedRuns': 32}]
        assert trace['enabled'] is False and trace['dispatchEligibility'] == 'not-evaluated'
        for outcome in successes:
            child = json.loads(outcome['stdout'])['runID']
            origin = call('automation-causality', book, child)
            assert origin['origin']['roots'] == [root] and origin['origin']['parents'] == []
            assert origin['origin']['independentInputs'] == [source] and origin['origin']['depth'] == 1
        history = call('commits', book)
        assert call('automation-causality', book, run) == trace
        assert call('commits', book) == history
        with sqlite3.connect(book / 'workbook.sqlite') as db:
            counts = [db.execute('SELECT count(*) FROM ' + table).fetchone()[0] for table in
                      ['automatic_roots', 'automatic_admissions', 'automatic_root_members', 'automatic_independent_inputs']]
        assert counts == [1, 32, 32, 32], counts
        assert call('verify', book)['ok']
        copy = folder / 'Inert.sevra'
        assert call('reconstruct', book, copy)['execution'] == 'inert'
        assert call('automation-causality', copy, run) == trace
        assert call('verify', copy)['ok']
        damaged = []
        for damage in ['root-commit', 'representative', 'declaration', 'relation', 'lineage']:
            bad = folder / (damage + '.sevra')
            shutil.copytree(book, bad)
            with sqlite3.connect(bad / 'workbook.sqlite') as db:
                if damage == 'root-commit': db.execute("UPDATE automatic_roots SET commit_id='foreign'")
                elif damage == 'representative': db.execute('UPDATE automatic_roots SET source_id=(SELECT dispatch_source FROM automation_runs LIMIT 1)')
                elif damage == 'declaration': db.execute('DELETE FROM business_inputs WHERE source_id=?', [source])
                elif damage == 'relation': db.execute('DELETE FROM automatic_independent_inputs WHERE run_id=?', [run])
                else: db.execute('UPDATE lineage SET roles=2 WHERE child=(SELECT source_id FROM workflow_runs WHERE id=?) AND parent=?', [run, source])
            p = subprocess.run([str(cli), 'automation-causality', str(bad), run], capture_output=True, text=True, timeout=30)
            assert p.returncode != 0 and not p.stdout and json.loads(p.stderr)['ok'] is False, (damage, p.stdout, p.stderr)
            damaged.append({'damage': damage, 'returncode': p.returncode, 'stderr': p.stderr})
        deaths = []
        for stage in ['prepared', 'committed']:
            path = folder / (stage + '.sevra')
            process = subprocess.Popen([str(worker), '--shared-admission-death-worker', str(path), stage],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                assert select.select([process.stdout], [], [], 30)[0], 'Admission barrier timed out'
                barrier = json.loads(process.stdout.readline())
                assert barrier['stage'] == stage
                process.kill()
                stdout, stderr = process.communicate(timeout=20)
                assert process.returncode == -9 and not stdout and not stderr, (stdout, stderr)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate(timeout=20)
            with sqlite3.connect(path / 'workbook.sqlite') as db:
                counts = [db.execute('SELECT count(*) FROM ' + table).fetchone()[0] for table in
                          ['automation_runs', 'automatic_roots', 'automatic_admissions', 'automatic_root_members', 'automatic_independent_inputs']]
            assert counts == ([0] * 5 if stage == 'prepared' else [1] * 5), counts
            assert call('verify', path)['ok']
            recovered = folder / ('recovered-' + stage + '.sevra')
            call('reconstruct', path, recovered)
            assert call('verify', recovered)['ok']
            deaths.append({'stage': stage, 'signal': 'SIGKILL', 'counts': counts})
        report.update({'ok': True, 'writers': outcomes, 'admittedBeforeRace': 25,
                       'admittedByRace': 7, 'refusedByRace': 2, 'rootID': root,
                       'damagedCopiesRefused': 5, 'damagedCopies': damaged, 'publicationDeaths': deaths,
                       'callCount': len(report['calls'])})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: v for k, v in report.items() if k not in ['calls', 'writers']}))


if __name__ == '__main__':
    main()
