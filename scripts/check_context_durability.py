#!/usr/bin/env python3
"""Kill owned fixture processes inside/after real checkpoint transactions.

No model, audio or user workbook is opened. The package-internal observer is
installed only by the fixture worker, never through a production environment
variable. Preserve every attempted fixture and result, including failures.
"""
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import select
import signal
import sqlite3
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, default=ROOT / '.build/debug/sevra-context-durability')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve(strict=True)
    if args.output:
        output = args.output.resolve()
        output.mkdir(parents=True, exist_ok=False)
    else:
        output = Path(tempfile.mkdtemp(prefix='context-durability-', dir=ROOT / '.build'))
    evidence = {'schemaVersion': 1, 'binarySHA256': hashlib.sha256(binary.read_bytes()).hexdigest(),
                'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'sourceSHA256': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                                 for path in [*sorted((ROOT / 'Sources/SevraCore').glob('*.swift')),
                                              ROOT / 'IntegrationTests/ContextDurability/Worker.swift',
                                              ROOT / 'scripts/check_context_durability.py']},
                'checks': [], 'calls': [], 'ok': False,
                'limits': 'Core transaction/process-death checks only; no LLM compaction or UI recovery qualification.'}

    def save():
        temporary = output / 'result.json.tmp'
        temporary.write_text(json.dumps(evidence, indent=2) + '\n')
        temporary.replace(output / 'result.json')

    def run(operation, root, expected=0):
        result = subprocess.run([str(binary), operation, str(root)], capture_output=True, text=True, timeout=40)
        evidence['calls'].append({'operation': operation, 'fixture': root.name, 'returncode': result.returncode,
                                  'stdout': result.stdout, 'stderr': result.stderr})
        save()
        assert result.returncode == expected, evidence['calls'][-1]
        return json.loads(result.stdout)

    def line(process):
        assert select.select([process.stdout], [], [], 20)[0], 'Timed out waiting for owned worker barrier'
        value = process.stdout.readline()
        assert value, 'Owned worker exited before barrier'
        return json.loads(value)

    def spawn(operation, root):
        return subprocess.Popen([str(binary), operation, str(root)], stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def finish(process, root, operation, barrier=None, kill=False):
        if kill:
            process.kill()
        stdout, stderr = process.communicate(timeout=20)
        evidence['calls'].append({'operation': operation, 'fixture': root.name, 'barrier': barrier,
                                  'returncode': process.returncode, 'stdout': stdout, 'stderr': stderr,
                                  'sentSIGKILL': kill})
        save()
        return stdout

    def business_unchanged(before, after):
        for key in ['messages', 'payloads', 'historyDigest', 'items', 'balance', 'forecast']:
            assert before[key] == after[key], f'Changed {key}'
        assert after['integrity']['ok'] is True, after['integrity']
        assert after['balance']['quantity'] == '18' and len(after['balance']['effects']) == 1

    save()
    try:
        for phase in ['prepared', 'published']:
            root = output / phase
            root.mkdir()
            before = run('setup', root)
            process = spawn('pause-' + phase, root)
            barrier = None
            try:
                barrier = line(process)
                assert barrier['phase'] == phase and barrier['checkpoint']
                # A separate reader must see only committed rows even while the
                # child is paused after writing its checkpoint and input rows.
                with closing(sqlite3.connect(f'file:{root / "Checkpoint.sevra/workbook.sqlite"}?mode=ro', uri=True, timeout=2)) as db:
                    visible = db.execute('SELECT count(*) FROM context_checkpoints').fetchone()[0]
                    visible_inputs = db.execute('SELECT count(*) FROM checkpoint_inputs').fetchone()[0]
                expected = 1 if phase == 'prepared' else 2
                assert visible == visible_inputs == expected, (visible, visible_inputs, phase)
                finish(process, root, 'pause-' + phase, barrier, kill=True)
                assert process.returncode == -signal.SIGKILL
            finally:
                if process.poll() is None:
                    finish(process, root, 'cleanup-' + phase, barrier, kill=True)
            after = run('inspect', root)
            business_unchanged(before, after)
            if phase == 'prepared':
                assert after == before, 'Uncommitted checkpoint survived process death'
            else:
                assert len(after['checkpoints']) == 2
                assert after['checkpoints'][0]['id'] == barrier['checkpoint']
                assert after['checkpoints'][1] == before['checkpoints'][0]
                assert after['revision'] == before['revision'] + 1
            first_retry = run('publish', root)
            second_retry = run('publish', root)
            assert first_retry == second_retry, 'Exact retry changed checkpoint identity'
            final = run('inspect', root)
            business_unchanged(before, final)
            assert len(final['checkpoints']) == 2 and final['revision'] == before['revision'] + 1
            assert final['checkpoints'][0]['id'] == first_retry['checkpoint']
            if phase == 'published':
                assert first_retry['checkpoint'] == barrier['checkpoint']
            assert run('portable', root) == final, 'Export/reopen changed durable state'
            evidence['checks'].append({'name': 'SIGKILL-' + phase, 'passed': True,
                                       'externalVisibleCheckpoints': visible, 'idempotentRetry': True,
                                       'portableIdentical': True, 'inventoryEffectCount': 1})
            save()

        root = output / 'cancelled'
        root.mkdir()
        before = run('setup', root)
        assert run('cancel-prepared', root, expected=1)['error'] == 'cancelled'
        assert run('inspect', root) == before, 'Cancellation left partial checkpoint rows'
        evidence['checks'].append({'name': 'cancel-after-checkpoint-and-input-inserts', 'passed': True})
        save()

        root = output / 'concurrent-acceptance'
        root.mkdir()
        before = run('setup', root)
        process = spawn('pause-before', root)
        barrier = None
        try:
            barrier = line(process)
            assert barrier['phase'] == 'before'
            changed = run('accept', root)
            process.stdin.write('continue\n'); process.stdin.flush()
            stdout = finish(process, root, 'concurrent-acceptance', barrier)
            assert process.returncode == 1 and json.loads(stdout)['error'] == 'stale_revision'
        finally:
            if process.poll() is None:
                finish(process, root, 'cleanup-acceptance', barrier, kill=True)
        after = run('inspect', root)
        assert after == changed and after['checkpoints'] == before['checkpoints']
        assert after['balance'] == before['balance']
        assert after['messages'] == before['messages'] and after['historyDigest'] == before['historyDigest']
        assert after['forecast']['status'] == 'accepted' and after['forecast']['meaning'] == 'estimate'
        inputs = after['checkpointDetails'][0]['inputs']
        assert len(inputs) == 1 and inputs[0]['currentStatus'] == 'accepted' and inputs[0]['currentMeaning'] == 'estimate'
        assert after['integrity']['ok'] is True
        evidence['checks'].append({'name': 'concurrent-acceptance-refuses-stale-publication', 'passed': True,
                                   'currentStateReconstructed': True, 'inventoryUnchanged': True})
        evidence['ok'] = True
    except BaseException as error:
        evidence['error'] = f'{type(error).__name__}: {error}'
        raise
    finally:
        save()
        print(json.dumps({'ok': evidence['ok'], 'checks': evidence['checks'], 'evidence': str(output / 'result.json')}))


if __name__ == '__main__':
    main()
