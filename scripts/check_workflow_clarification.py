#!/usr/bin/env python3
"""Qualify supplied workflow information, separate review and atomic recovery."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import select
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cli', type=Path, required=True)
parser.add_argument('--worker', type=Path)
parser.add_argument('--model-root', type=Path)
parser.add_argument('--skip-crashes', action='store_true')
parser.add_argument('--output', type=Path)
args = parser.parse_args()
cli = args.cli.resolve(strict=True)
worker = args.worker.resolve(strict=True) if args.worker else None
assert worker or (args.model_root and args.skip_crashes), 'A synthetic worker is required without a model or for crash checks'
scratch = None if args.output else tempfile.TemporaryDirectory(prefix='sevra-clarification-')
root = args.output.resolve() if args.output else Path(scratch.name)
if args.output:
    root.mkdir(parents=True, exist_ok=False)
result = {'ok': False, 'calls': [], 'crashChecks': [],
          'recordedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'products': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [cli, *([worker] if worker else [])]},
          'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
          'sourceSHA256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [
              *sorted((ROOT / 'Sources').rglob('*.swift')),
              *sorted((ROOT / 'IntegrationTests/WorkflowDurability').glob('*.swift')), Path(__file__).resolve()]},
          'integrationPins': {p: json.loads((ROOT / p).read_text()) for p in [
              'integration/splash.json', 'integration/llguidance.json']},
          'limits': ['Synthetic core/CLI submission with honest programmatic attribution. Native input UX and '
                     'conversation submission are unqualified. No broad model accuracy, performance or release claim.']}


def save():
    (root / 'result.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')


def j(value):
    return json.dumps(value, ensure_ascii=False)


def call(command, *values):
    started = time.monotonic()
    p = subprocess.run([str(cli), command, *map(str, values)], capture_output=True, text=True, timeout=240)
    entry = {'command': command, 'arguments': list(map(str, values)), 'returncode': p.returncode,
             'seconds': time.monotonic() - started, 'stdout': p.stdout, 'stderr': p.stderr}
    result['calls'].append(entry)
    save()
    assert p.returncode == 0, entry
    envelope = json.loads(p.stdout)
    assert envelope['ok'], envelope
    return envelope['result']


def fixture(folder):
    folder.mkdir()
    book = folder / 'Clarification.sevra'
    call('create', book, 'Synthetic missing delivery count')
    source = call('add', book, j({'category': 'source', 'kind': 'observation', 'title': 'Delivery D9',
        'text': 'Delivery D9: bolts were received. The received unit count was not recorded.',
        'meaning': 'actual'}))
    call('opening', book, 'bolts', '20', '2026-10-01', source['id'])
    field = {'id': 'evidence', 'label': 'Delivery evidence', 'type': 'item', 'required': True}
    def definition(content, token):
        return call('definition-save', book, uuid.uuid4(), j(content), 'new', token)
    interpretation = definition({'kind': 'interpretation', 'title': 'Read received count',
        'description': 'Missing information must be requested, never invented.', 'parameters': [field],
        'payload': {'instruction': 'Extract the explicitly stated received unit count as a decimal string. '
            'Quote the exact original statement establishing the count. If the count is absent or ambiguous, '
            'return needs_input with empty values and explain what information is needed. Do not guess or accept stock.',
            'evidence': ['evidence'], 'outputs': [
                {'id': 'quantity', 'label': 'Received count', 'type': 'decimal', 'unit': 'items', 'required': True}],
            'meaning': 'actual', 'scenario': 'actual'}}, 'read')
    primitive = next(p for p in call('action-registry', book) if p['id'] == 'inventory.proposeMovement')
    action = definition({'kind': 'action', 'title': 'Draft received stock',
        'description': 'Separate explicit inventory review.', 'parameters': primitive['parameters'],
        'payload': {'primitive': {'id': primitive['id'], 'version': primitive['version']},
            'arguments': {p['id']: {'parameter': p['id']} for p in primitive['parameters']}}}, 'action')
    workflow = definition({'kind': 'workflow', 'title': 'Receive with supplied missing information',
        'description': 'An interpretation can pause for an exact later submission.', 'parameters': [field],
        'payload': {'readPolicy': 'latest-at-step', 'steps': [
            {'id': 'read', 'kind': 'interpret', 'binding': {'mode': 'exact', 'versionID': interpretation['id']},
             'arguments': {'evidence': {'parameter': 'evidence'}}},
            {'id': 'stock', 'kind': 'action', 'binding': {'mode': 'exact', 'versionID': action['id']},
             'arguments': {'subject': {'literal': 'bolts'},
                'quantity': {'step': 'read', 'field': 'quantity', 'unit': 'items'},
                'occurrence': {'literal': 'delivery-d9'}, 'effective': {'literal': '2026-10-29'},
                'evidence': {'parameter': 'evidence'}, 'meaning': {'literal': 'actual'}}},
            {'id': 'review', 'kind': 'review', 'review': 'stock'}]}}, 'workflow')
    run_id = call('workflow-start', book, workflow['id'], j({'evidence': source['id']}), 'start')['id']
    (folder / 'plan.json').write_text(j({'runID': run_id}))
    return book, run_id


def worker_call(operation, folder):
    p = subprocess.run([str(worker), operation, str(folder)], capture_output=True, text=True, timeout=60)
    result['calls'].append({'worker': operation, 'fixture': str(folder), 'returncode': p.returncode,
                            'stdout': p.stdout, 'stderr': p.stderr})
    save()
    assert p.returncode == 0, result['calls'][-1]
    return json.loads(p.stdout)


def snapshot(book, run_id):
    return {'run': call('workflow-read', book, run_id), 'counts': call('inspect', book),
            'balance': call('balance', book, 'bolts', '2099-12-31'), 'events': call('workflow-events', book),
            'integrity': call('verify', book)}


def finish(book, run_id):
    waiting = call('workflow-continue', book, run_id, root / 'absent-model')
    assert waiting['state'] == 'waiting_review'
    assert call('balance', book, 'bolts')['quantity'] == '20'
    proposal = waiting['steps'][1]['output']['value']['proposals'][0]
    accepted = call('accept', book, proposal, 'synthetic-explicit-review')
    assert call('accept', book, proposal, 'synthetic-explicit-review') == accepted
    done = call('workflow-continue', book, run_id, root / 'absent-model')
    assert done['state'] == 'completed' and call('balance', book, 'bolts')['quantity'] == '25'
    assert call('workflow-continue', book, run_id, root / 'absent-model') == done
    assert call('verify', book)['ok']
    return done


try:
    result['version'] = call('version')
    folder = root / 'submission'
    book, run_id = fixture(folder)
    if args.model_root:
        paused = call('workflow-continue', book, run_id, args.model_root)
    else:
        paused = worker_call('clarify-pause', folder)['run']
    assert paused['state'] == 'needs_attention'
    original = paused['steps'][0]['output']['value']
    assert original['response']['state'] == 'needs_input' and original['response']['values'] == {}
    assert original['response']['issues']
    target = call('workflow-clarification', book, run_id)
    values, reason = {'quantity': '5'}, 'The synthetic calling program supplies five received units.'
    clarified = call('workflow-clarify', book, run_id, j(target), j(values), reason, 'cli-answer')
    assert clarified['state'] == 'queued' and clarified['steps'][1]['output'] is None
    value = clarified['steps'][0]['output']['value']
    assert {k: v for k, v in value.items() if k != 'clarification'} == original
    supplied = value['clarification']
    assert supplied['values'] == values and supplied['actor']['kind'] == 'programmatic'
    source = call('read', book, supplied['sourceID'])['item']
    assert source['category'] == 'source' and source['data']['actor']['kind'] == 'programmatic'
    assert source['data']['values'] == values
    assert call('workflow-clarify', book, run_id, j(target), j(values), reason, 'cli-answer') == clarified
    assert call('balance', book, 'bolts')['quantity'] == '20'
    done = finish(book, run_id)
    assert done['steps'][0]['output'] == clarified['steps'][0]['output'], 'Completed interpretation was repeated'
    copy = folder / 'Reconstructed.sevra'
    assert call('reconstruct', book, copy)['execution'] == 'inert'
    assert call('workflow-read', copy, run_id) == done and call('verify', copy)['ok']
    assert call('balance', copy, 'bolts')['quantity'] == '25'
    result.update(actualModel=bool(args.model_root), originalModelOutput=original,
                  target=target, clarified=clarified, completed=done)
    if not args.skip_crashes:
        for phase in ['clarify-prepared', 'clarify-committed']:
            folder = root / phase
            book, run_id = fixture(folder)
            worker_call('clarify-pause', folder)
            target = call('workflow-clarification', book, run_id)
            (folder / 'plan.json').write_text(j({'runID': run_id, 'target': target}))
            before = snapshot(book, run_id)
            p = subprocess.Popen([str(worker), phase, str(folder)], stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                assert select.select([p.stdout], [], [], 20)[0], 'Clarification barrier timed out'
                barrier = json.loads(p.stdout.readline())
                assert barrier['stage'] == phase
                p.kill()
                stdout, stderr = p.communicate(timeout=20)
                result['calls'].append({'worker': phase, 'barrier': barrier, 'returncode': p.returncode,
                                        'sentSIGKILL': True, 'stdout': stdout, 'stderr': stderr})
                assert p.returncode == -9
            finally:
                if p.poll() is None:
                    p.kill()
                    p.communicate(timeout=20)
            interrupted = snapshot(book, run_id)
            assert interrupted['integrity']['ok'] and interrupted['balance']['quantity'] == '20'
            if phase == 'clarify-prepared':
                assert interrupted == before, 'Uncommitted clarification left partial state'
            else:
                assert interrupted['run']['state'] == 'queued'
                assert interrupted['counts']['sources'] == before['counts']['sources'] + 1
                assert interrupted['counts']['records'] == before['counts']['records'] + 1
                assert len(interrupted['events']['events']) == len(before['events']['events']) + 1
            copy = folder / 'InterruptedCopy.sevra'
            assert call('reconstruct', book, copy)['execution'] == 'inert'
            assert snapshot(copy, run_id) == interrupted, 'Reconstruction executed or changed work'
            resumed = worker_call('clarify-resume', folder)
            if phase == 'clarify-committed':
                assert resumed == interrupted, 'Retry changed committed clarification'
            assert worker_call('clarify-resume', folder) == resumed
            completed = finish(book, run_id)
            result['crashChecks'].append({'phase': phase, 'ok': True, 'interrupted': interrupted,
                                           'resumed': resumed, 'completed': completed})
            save()
    result.update(ok=True, checks=['missing count stays unresolved', 'exact supplied Source and draft Record',
        'honest programmatic attribution', 'original model output unchanged', 'no implicit continuation/acceptance',
        'absent-model continuation', 'stock20 before review and25 after exact acceptance once',
        'completed steps retained', 'inert reconstruction', 'integrity', 'atomic SIGKILL recovery when selected'])
    save()
    print(j({'ok': True, 'actualModel': result['actualModel'], 'calls': len(result['calls']),
             'crashBoundaries': len(result['crashChecks']), 'output': str(args.output or '')}))
except BaseException as error:
    result['failure'] = repr(error)
    save()
    raise
