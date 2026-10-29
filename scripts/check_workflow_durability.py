#!/usr/bin/env python3
"""Kill owned synthetic workflow workers at real claim/checkpoint boundaries."""
import argparse
import hashlib
import json
from pathlib import Path
import select
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--binary', type=Path, default=ROOT / '.build/debug/sevra-workflow-durability')
parser.add_argument('--output', type=Path)
args = parser.parse_args()
binary = args.binary.resolve(strict=True)
output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='workflow-durability-', dir=ROOT / '.build'))
if args.output:
    output.mkdir(parents=True, exist_ok=False)
evidence = {'ok': False, 'schemaVersion': 1, 'checks': [], 'calls': [],
            'binarySHA256': hashlib.sha256(binary.read_bytes()).hexdigest(),
            'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
            'sourceSHA256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in [*sorted((ROOT / 'Sources/SevraCore').glob('*.swift')),
                                       *sorted((ROOT / 'IntegrationTests/WorkflowDurability').glob('*.swift')), Path(__file__).resolve()]},
            'limits': ['Synthetic manual core workflows, structured interpretation, native document preparation, registered document drafting and reviewed CSV/TSV intake publication.',
                       'No real model, Excel continuity, UI, background automation or schedule qualification.']}


def save():
    (output / 'result.json').write_text(json.dumps(evidence, indent=2) + '\n')


def run(operation, root, error=None):
    p = subprocess.run([str(binary), operation, str(root)], capture_output=True, text=True, timeout=60)
    call = {'operation': operation, 'fixture': root.name, 'returncode': p.returncode,
            'stdout': p.stdout, 'stderr': p.stderr}
    evidence['calls'].append(call)
    save()
    if error:
        assert p.returncode == 1 and json.loads(p.stderr)['code'] == error, call
        return None
    assert p.returncode == 0, call
    return json.loads(p.stdout)


def step(snapshot, ordinal):
    return snapshot['run']['steps'][ordinal]


try:
    for phase in ['claimed', 'prepared', 'committed']:
        root = output / phase
        root.mkdir()
        baseline = run('setup', root)
        assert step(baseline, 0)['output']['value']['result'] == '2'
        assert baseline['balance']['quantity'] == '20'
        p = subprocess.Popen([str(binary), phase, str(root)], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        barrier = None
        try:
            assert select.select([p.stdout], [], [], 20)[0], 'Worker barrier timed out'
            line = p.stdout.readline()
            assert line, 'Worker exited before its barrier'
            barrier = json.loads(line)
            assert barrier['stage'] == phase, barrier
            (root / 'claim.json').write_text(json.dumps(barrier['value']))
            if phase == 'claimed':
                # A distinct native process sees the still-live claim.
                run('claimed', root, error='workflow_busy')
            p.kill()
            stdout, stderr = p.communicate(timeout=20)
            evidence['calls'].append({'operation': phase, 'fixture': root.name,
                                      'barrier': barrier, 'returncode': p.returncode,
                                      'stdout': stdout, 'stderr': stderr, 'sentSIGKILL': True})
            save()
            assert p.returncode == -9
        finally:
            if p.poll() is None:
                p.kill()
                p.communicate(timeout=20)
        interrupted = run('inspect', root)
        assert interrupted['integrity']['ok'] is True
        assert step(interrupted, 0) == step(baseline, 0), 'Completed calculation changed'
        assert interrupted['balance']['quantity'] == '20'
        if phase == 'committed':
            assert step(interrupted, 1)['state'] == 'completed'
            assert len(step(interrupted, 1)['output']['value']['proposals']) == 1
            assert len(interrupted['events']['events']) == len(baseline['events']['events']) + 1
        else:
            assert step(interrupted, 1)['state'] == 'claimed'
            assert step(interrupted, 1)['output'] is None
            assert interrupted['counts']['records'] == baseline['counts']['records']
            assert interrupted['events'] == baseline['events'], 'Rolled-back step left an outbox event'
        copies = run('inert-copies', root)
        for copy in copies.values():
            assert copy['run'] == interrupted['run']
            assert copy['balance'] == interrupted['balance']
            assert copy['counts'] == interrupted['counts']
            assert copy['events'] == interrupted['events']
            assert copy['integrity']['ok'] is True
        # Let the deliberately short fixture lease expire before a fresh owner.
        if phase != 'committed':
            time.sleep(2.1)
            run('late', root, error='workflow_fenced')
            proposed = run('advance', root)
        else:
            proposed = interrupted
        waiting = run('advance', root)
        assert waiting['run']['state'] == 'waiting_review'
        assert waiting['balance']['quantity'] == '20'
        assert step(waiting, 1) == step(proposed, 1), 'Recovery repeated a completed action'
        accepted = run('accept', root)
        assert accepted['balance']['quantity'] == '25'
        completed = run('advance', root)
        assert completed['run']['state'] == 'completed'
        assert completed['balance']['quantity'] == '25'
        assert len(completed['balance']['effects']) == 1
        assert step(completed, 0) == step(baseline, 0)
        assert step(completed, 1) == step(proposed, 1)
        again = run('advance', root)
        assert again['run'] == completed['run']
        assert again['balance'] == completed['balance']
        evidence['checks'].append({'phase': phase, 'ok': True})
        save()
    for phase in ['form-prepared', 'form-committed']:
        root = output / phase
        root.mkdir()
        baseline = run('setup-form', root)
        assert baseline['receipt'] is None and baseline['runs'] == []
        p = subprocess.Popen([str(binary), phase, str(root)], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            assert select.select([p.stdout], [], [], 20)[0], 'Form publication barrier timed out'
            barrier = json.loads(p.stdout.readline())
            assert barrier['stage'] == phase, barrier
            p.kill()
            stdout, stderr = p.communicate(timeout=20)
            evidence['calls'].append({'operation': phase, 'fixture': root.name,
                                      'barrier': barrier, 'returncode': p.returncode,
                                      'stdout': stdout, 'stderr': stderr, 'sentSIGKILL': True})
            save()
            assert p.returncode == -9
        finally:
            if p.poll() is None:
                p.kill()
                p.communicate(timeout=20)
        interrupted = run('form-inspect', root)
        assert interrupted['integrity']['ok'] and interrupted['draft'] == baseline['draft']
        assert interrupted['counts']['records'] == 0
        if phase == 'form-prepared':
            assert interrupted['receipt'] is None and interrupted['runs'] == []
            assert interrupted['counts'] == baseline['counts']
        else:
            assert interrupted['receipt']['workflowRunID'] == barrier['value']
            assert len(interrupted['runs']) == 1 and interrupted['runs'][0]['state'] == 'queued'
        copies = run('form-copies', root)
        assert all(copy == interrupted for copy in copies.values()), 'Form copy resumed or changed work'
        resumed = run('form-resume', root)
        assert len(resumed['runs']) == 1 and resumed['runs'][0]['state'] == 'queued'
        assert resumed['draft'].get('lastReceipt') is None, 'Worker invented a presentation checkpoint'
        assert resumed['receipt']['workflowRunID'] == resumed['runs'][0]['id']
        if phase == 'form-committed':
            assert resumed == interrupted, 'Exact retry changed a committed run'
        assert run('form-resume', root) == resumed, 'Repeated submission created another run'
        evidence['checks'].append({'phase': phase, 'ok': True})
        save()
    for phase in ['interpret-request', 'interpret-response', 'interpret-prepared', 'interpret-committed']:
        root = output / phase
        root.mkdir()
        baseline = run('interpret-setup', root)
        assert baseline['counts']['records'] == 0
        p = subprocess.Popen([str(binary), phase, str(root)], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            assert select.select([p.stdout], [], [], 20)[0], 'Interpretation barrier timed out'
            barrier = json.loads(p.stdout.readline())
            assert barrier['stage'] == phase, barrier
            (root / 'capture.json').write_text(json.dumps(barrier['value']))
            p.kill()
            stdout, stderr = p.communicate(timeout=20)
            evidence['calls'].append({'operation': phase, 'fixture': root.name, 'barrier': barrier,
                                      'returncode': p.returncode, 'stdout': stdout, 'stderr': stderr,
                                      'sentSIGKILL': True})
            save()
            assert p.returncode == -9
        finally:
            if p.poll() is None:
                p.kill()
                p.communicate(timeout=20)
        interrupted = run('interpret-inspect', root)
        assert interrupted['integrity']['ok'] is True
        saved = interrupted['inspection']['steps'][0]
        if phase == 'interpret-committed':
            assert saved['state'] == 'completed' and interrupted['counts']['records'] == 1
            assert saved['output']['value']['response'] == barrier['value']['envelope']['response']
        else:
            assert saved['state'] == 'claimed' and saved['output'] is None
            assert interrupted['counts']['records'] == 0
            assert interrupted['events'] == baseline['events']
        if phase == 'interpret-request':
            assert 'modelResponse' not in saved['attempt']
        else:
            assert saved['attempt']['modelResponse'] == barrier['value']['envelope']['response']
        copies = run('interpret-copies', root)
        assert all(copy == interrupted for copy in copies.values()), 'Copied interpretation executed or changed'
        if phase != 'interpret-committed':
            time.sleep(2.1)
            run('interpret-late', root, error='workflow_fenced')
        resumed = run('interpret-resume', root)
        assert resumed['inspection']['run']['state'] == 'completed'
        assert resumed['counts']['records'] == 1 and resumed['integrity']['ok']
        assert run('interpret-resume', root) == resumed, 'Completed interpretation repeated'
        if phase == 'interpret-committed':
            assert resumed == interrupted, 'Recovery changed the committed interpretation'
        evidence['checks'].append({'phase': phase, 'ok': True})
        save()
    for phase in ['extract-request', 'extract-parsed', 'extract-prepared', 'extract-committed']:
        root = output / phase
        root.mkdir()
        baseline = run('extract-setup', root)
        assert baseline['priorHits'] == 1 and baseline['receivedHits'] == 0
        p = subprocess.Popen([str(binary), phase, str(root)], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            assert select.select([p.stdout], [], [], 20)[0], 'Document preparation barrier timed out'
            barrier = json.loads(p.stdout.readline())
            assert barrier['stage'] == phase, barrier
            (root / 'capture.json').write_text(json.dumps(barrier['value']))
            p.kill()
            stdout, stderr = p.communicate(timeout=20)
            evidence['calls'].append({'operation': phase, 'fixture': root.name, 'barrier': barrier,
                                      'returncode': p.returncode, 'stdout': stdout, 'stderr': stderr,
                                      'sentSIGKILL': True})
            save()
            assert p.returncode == -9
        finally:
            if p.poll() is None:
                p.kill()
                p.communicate(timeout=20)
        interrupted = run('extract-inspect', root)
        assert interrupted['integrity']['ok'] and interrupted['counts']['records'] == 0
        saved = step(interrupted, 0)
        if phase == 'extract-committed':
            assert saved['state'] == 'completed' and saved['output']['value']['complete'] is True
            assert interrupted['priorHits'] == 0 and interrupted['receivedHits'] == 1
        else:
            assert saved['state'] == 'claimed' and saved['output'] is None
            assert interrupted['priorHits'] == 1 and interrupted['receivedHits'] == 0
            assert interrupted['extraction'] == baseline['extraction']
            assert interrupted['events'] == baseline['events']
        copies = run('extract-copies', root)
        assert all(copy == interrupted for copy in copies.values()), 'Document copy executed or changed'
        if phase != 'extract-committed':
            time.sleep(2.1)
            run('extract-late', root, error='workflow_fenced')
        resumed = run('extract-resume', root)
        assert resumed['run']['state'] == 'completed' and resumed['integrity']['ok']
        assert resumed['counts']['records'] == 0 and resumed['receivedHits'] == 1 and resumed['priorHits'] == 0
        assert run('extract-resume', root) == resumed, 'Completed preparation repeated'
        if phase == 'extract-committed':
            assert resumed == interrupted, 'Recovery changed committed document text or identity'
        evidence['checks'].append({'phase': phase, 'ok': True})
        save()
    for phase in ['document-prepared', 'document-committed']:
        root = output / phase
        root.mkdir()
        baseline = run('document-setup', root)
        assert baseline['documents'] == [] and baseline['reportHits'] == 0
        p = subprocess.Popen([str(binary), phase, str(root)], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            assert select.select([p.stdout], [], [], 20)[0], 'Report publication barrier timed out'
            barrier = json.loads(p.stdout.readline())
            assert barrier['stage'] == phase, barrier
            (root / 'claim.json').write_text(json.dumps(barrier['value']))
            p.kill()
            stdout, stderr = p.communicate(timeout=20)
            evidence['calls'].append({'operation': phase, 'fixture': root.name, 'barrier': barrier,
                                      'returncode': p.returncode, 'stdout': stdout, 'stderr': stderr,
                                      'sentSIGKILL': True})
            save()
            assert p.returncode == -9
        finally:
            if p.poll() is None:
                p.kill()
                p.communicate(timeout=20)
        interrupted = run('document-inspect', root)
        assert interrupted['integrity']['ok'] is True
        if phase == 'document-committed':
            assert step(interrupted, 0)['state'] == 'completed'
            assert len(interrupted['documents']) == interrupted['reportHits'] == 1
            assert interrupted['documents'][0]['meaning'] == 'estimate'
        else:
            assert step(interrupted, 0)['state'] == 'claimed'
            assert interrupted['documents'] == [] and interrupted['reportHits'] == 0
            assert interrupted['counts'] == dict(baseline['counts'], revision=baseline['counts']['revision'] + 1)
            assert interrupted['events'] == baseline['events']
        copies = run('document-copies', root)
        assert all(copy == interrupted for copy in copies.values()), 'Copied report executed or changed'
        if phase != 'document-committed':
            time.sleep(2.1)
            run('document-late', root, error='workflow_fenced')
        resumed = run('document-resume', root)
        assert len(resumed['documents']) == resumed['reportHits'] == 1 and resumed['integrity']['ok']
        assert resumed['documents'][0]['status'] == 'draft'
        assert run('document-resume', root) == resumed, 'Completed report repeated'
        if phase == 'document-committed':
            assert resumed == interrupted, 'Recovery changed a committed report'
        waiting = run('document-review', root)
        assert waiting['run']['state'] == 'waiting_review'
        accepted = run('document-accept', root)
        assert accepted['documents'][0]['status'] == 'accepted'
        assert accepted['documents'][0]['meaning'] == 'estimate'
        completed = run('document-review', root)
        assert completed['run']['state'] == 'completed' and completed['integrity']['ok']
        assert run('document-review', root) == completed
        evidence['checks'].append({'phase': phase, 'ok': True})
        save()
    for phase in ['intake-request', 'intake-parsed', 'intake-prepared', 'intake-committed',
                  'intake-accept-prepared', 'intake-accept-committed']:
        root = output / phase
        root.mkdir()
        baseline = run('intake-setup', root)
        acceptance = phase.startswith('intake-accept-')
        if acceptance:
            run('intake-resume', root)
            baseline = run('intake-review', root)
            assert baseline['run']['state'] == 'waiting_review'
        assert len(baseline['rows']) == 1 and baseline['balance']['quantity'] == '20'
        p = subprocess.Popen([str(binary), phase, str(root)], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            assert select.select([p.stdout], [], [], 20)[0], 'Structured-intake barrier timed out'
            barrier = json.loads(p.stdout.readline())
            assert barrier['stage'] == phase, barrier
            (root / 'claim.json').write_text(json.dumps(barrier['value']))
            p.kill()
            stdout, stderr = p.communicate(timeout=20)
            evidence['calls'].append({'operation': phase, 'fixture': root.name, 'barrier': barrier,
                                      'returncode': p.returncode, 'stdout': stdout, 'stderr': stderr,
                                      'sentSIGKILL': True})
            save()
            assert p.returncode == -9
        finally:
            if p.poll() is None:
                p.kill()
                p.communicate(timeout=20)
        interrupted = run('intake-inspect', root)
        assert interrupted['integrity']['ok'] and interrupted['balance']['quantity'] == '20'
        applied = phase == 'intake-accept-committed'
        published = acceptance or phase == 'intake-committed'
        assert len(interrupted['proposals']) == int(published)
        assert len(interrupted['rows']) == (2 if applied else 1)
        if not applied:
            assert interrupted['rows'] == baseline['rows'], 'Uncommitted intake changed working rows'
        if published:
            assert step(interrupted, 0)['state'] == 'completed'
            assert interrupted['proposals'][0]['status'] == ('accepted' if applied else 'draft')
        else:
            assert step(interrupted, 0)['state'] == 'claimed' and step(interrupted, 0)['output'] is None
            assert interrupted['events'] == baseline['events']
        copies = run('intake-copies', root)
        assert all(copy == interrupted for copy in copies.values()), 'Copied intake parsed, applied or changed'
        if not published:
            time.sleep(2.1)
            run('intake-late', root, error='workflow_fenced')
        resumed = run('intake-resume', root)
        assert len(resumed['proposals']) == 1 and resumed['integrity']['ok']
        assert run('intake-resume', root) == resumed, 'Committed intake repeated'
        if published:
            assert resumed == interrupted, 'Recovery changed a committed plan or row application'
        waiting = run('intake-review', root)
        if applied:
            assert waiting['run']['state'] == 'completed'
        else:
            assert waiting['run']['state'] == 'waiting_review'
        accepted = run('intake-accept', root)
        assert len(accepted['rows']) == 2 and accepted['rows'][1]['meaning'] == 'estimate'
        assert accepted['rows'][1]['data'] == {'sku': '0014', 'qty': '2'}
        assert accepted['balance']['quantity'] == '20'
        assert run('intake-accept', root) == accepted, 'Exact acceptance retry duplicated rows'
        completed = run('intake-review', root)
        assert completed['run']['state'] == 'completed' and completed['integrity']['ok']
        assert run('intake-review', root) == completed
        evidence['checks'].append({'phase': phase, 'ok': True})
        save()
    evidence['ok'] = True
    save()
    print(json.dumps({'ok': True, 'checks': evidence['checks'], 'output': str(output)}))
except BaseException as error:
    evidence['failure'] = repr(error)
    save()
    raise
