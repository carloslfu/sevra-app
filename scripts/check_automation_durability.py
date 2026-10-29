#!/usr/bin/env python3
"""SIGKILL owned synthetic automation workers before and after dispatch commit."""
import argparse
import hashlib
import json
from pathlib import Path
import select
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, default=ROOT / '.build/debug/sevra-automation-durability')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve(strict=True)
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='automation-durability-', dir=ROOT / '.build'))
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    evidence = {'ok': False, 'binarySHA256': hashlib.sha256(binary.read_bytes()).hexdigest(), 'calls': [], 'checks': [],
                'limits': ['Synthetic exact deterministic foreground automation dispatch; two actual SIGKILL publication boundaries.',
                           'No real inference, native timer/device permission, UI, background scheduling or release claim.']}

    def save():
        (output / 'result.json').write_text(json.dumps(evidence, indent=2) + '\n')

    def run(operation, root, error=None):
        p = subprocess.run([str(binary), operation, str(root)], capture_output=True, text=True, timeout=60)
        call = {'operation': operation, 'fixture': root.name, 'returncode': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr}
        evidence['calls'].append(call)
        save()
        if error:
            assert p.returncode == 1 and json.loads(p.stderr)['code'] == error, call
            return
        assert p.returncode == 0, call
        return json.loads(p.stdout)

    try:
        for phase in ['prepared', 'committed']:
            root = output / phase
            root.mkdir()
            baseline = run('setup', root)
            assert baseline['runs'] == [] and baseline['occurrences']['occurrences'][0]['state'] == 'pending'
            worker = subprocess.Popen([str(binary), phase, str(root)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                assert select.select([worker.stdout], [], [], 20)[0], 'Dispatch barrier timed out'
                barrier = json.loads(worker.stdout.readline())
                assert barrier['stage'] == phase, barrier
                worker.kill()
                stdout, stderr = worker.communicate(timeout=20)
                evidence['calls'].append({'operation': phase, 'fixture': root.name, 'barrier': barrier, 'returncode': worker.returncode,
                                          'stdout': stdout, 'stderr': stderr, 'sentSIGKILL': True})
                save()
                assert worker.returncode == -9
            finally:
                if worker.poll() is None:
                    worker.kill()
                    worker.communicate(timeout=20)
            interrupted = run('inspect', root)
            assert interrupted['integrity']['ok']
            if phase == 'prepared':
                assert interrupted == baseline, 'Uncommitted dispatch leaked authority, run, occurrence state or event'
            else:
                assert len(interrupted['runs']) == 1 and interrupted['runs'][0]['state'] == 'queued'
                assert interrupted['occurrences']['occurrences'][0]['state'] == 'dispatched'
                assert len(interrupted['events']['events']) == len(baseline['events']['events']) + 1
            copies = run('copies', root)
            assert all(value == interrupted for value in copies.values()), 'Copy changed or executed saved work'
            dispatched = run('dispatch', root)
            assert len(dispatched['runs']) == 1 and dispatched['runs'][0]['state'] == 'queued'
            if phase == 'committed':
                assert dispatched == interrupted, 'Recovery duplicated committed dispatch'
            assert run('dispatch', root) == dispatched, 'Dispatch retry duplicated work'
            completed = run('resume', root)
            assert len(completed['runs']) == 1 and completed['runs'][0]['state'] == 'completed'
            assert completed['integrity']['ok']
            assert run('resume', root) == completed, 'Explicit repeat re-executed completed work'
            evidence['checks'].append({'phase': phase, 'ok': True})
        evidence['ok'] = True
    finally:
        save()
    print(json.dumps({'ok': evidence['ok'], 'boundaries': len(evidence['checks']), 'calls': len(evidence['calls']), 'output': str(output)}))


if __name__ == '__main__':
    main()
