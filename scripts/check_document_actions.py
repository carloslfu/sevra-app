#!/usr/bin/env python3
"""Qualify registered prose actions through independent CLI processes and optional local inference."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cli', type=Path, required=True)
parser.add_argument('--model-root', type=Path)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
cli = args.cli.resolve(strict=True)
scratch = None if args.output else tempfile.TemporaryDirectory(prefix='sevra-document-actions-')
root = args.output.resolve() if args.output else Path(scratch.name)
if args.output:
    root.mkdir(parents=True, exist_ok=False)
result = {'ok': False, 'calls': [], 'recordedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'cliSHA256': hashlib.sha256(cli.read_bytes()).hexdigest(),
          'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
          'sourceSHA256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in [*sorted((ROOT / 'Sources').rglob('*.swift')), Path(__file__).resolve()]},
          'limits': ['Synthetic local CLI and optional installed-model job; no visible UI, source-copy fidelity, broad accuracy or performance claim.']}


def save():
    (root / 'result.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')


def j(value):
    return json.dumps(value, ensure_ascii=False)


def call(command, *values):
    started = time.monotonic()
    process = subprocess.run([str(cli), command, *map(str, values)], capture_output=True, text=True, timeout=240)
    entry = {'command': command, 'arguments': list(map(str, values)), 'returncode': process.returncode,
             'seconds': time.monotonic() - started, 'stdout': process.stdout, 'stderr': process.stderr}
    result['calls'].append(entry)
    save()
    assert process.returncode == 0, entry
    envelope = json.loads(process.stdout)
    assert envelope['ok'], envelope
    return envelope['result']


def definition(book, content, token):
    return call('definition-save', book, uuid.uuid4(), j(content), 'new', token)


try:
    book = root / 'Reports.sevra'
    call('create', book, 'Synthetic report workflow')
    original = root / 'Receipt.txt'
    original.write_text('Delivery receipt. Exactly 5 bolts were received into stock on October 28, 2026.\n')
    captured = call('import', book, original, '--role', 'reference', '--token', 'receipt')
    source = captured['source']['id']
    call('opening', book, 'bolts', '20', '2026-10-01', source)
    primitive = next(p for p in call('action-registry', book) if p['id'] == 'records.draftDocument')
    action = definition(book, {
        'kind': 'action', 'title': 'Draft receiving report', 'description': 'New prose for separate review.',
        'parameters': primitive['parameters'], 'payload': {
            'primitive': {'id': primitive['id'], 'version': primitive['version']},
            'arguments': {p['id']: {'parameter': p['id']} for p in primitive['parameters']}}}, 'report-action')
    form = definition(book, call('form-template', book, action['id']), 'report-form')
    state = call('form-draft-new', book, form['id'])
    state['arguments'] = {'title': 'Receiving memo', 'body': 'First line.\nSecond line. 💡',
                          'evidence': source, 'meaning': 'estimate', 'scenario': 'actual'}
    state = call('form-draft-save', book, 'report', j(state), 'null')
    counts = call('inspect', book)
    preview = call('form-draft-preview', book, j(state))
    assert len(preview['documents']) == 1 and preview['movements'] == []
    assert call('inspect', book) == counts, 'Preview wrote business data'
    receipt = call('form-draft-submit', book, j(state), j(preview))
    assert call('form-draft-submit', book, j(state), j(preview)) == receipt
    draft = call('read', book, receipt['proposals'][0])['item']
    assert draft['text'] == state['arguments']['body'] and draft['meaning'] == 'estimate'
    assert draft['status'] == 'draft'
    assert call('balance', book, 'bolts')['quantity'] == '20'
    result['formReceipt'] = receipt
    # One shared action and review path, optionally preceded by real native preparation/interpretation.
    content = {'kind': 'workflow', 'title': 'Receiving report workflow',
               'description': 'Explicitly draft and review a report.', 'parameters': action['parameters'],
               'payload': {'readPolicy': 'latest-at-step', 'steps': [
                   {'id': 'report', 'kind': 'action', 'binding': {'mode': 'exact', 'versionID': action['id']},
                    'arguments': {p['id']: {'parameter': p['id']} for p in action['parameters']}},
                   {'id': 'review', 'kind': 'review', 'review': 'report'}]}}
    arguments = dict(state['arguments'], title='Receiving workflow report')
    if args.model_root:
        item_parameter = {'id': 'evidence', 'label': 'Evidence', 'type': 'item', 'required': True}
        prepare = definition(book, {'kind': 'extraction', 'title': 'Prepare receipt', 'description': 'Included original',
            'parameters': [item_parameter], 'payload': {'parser': 'native-v1', 'file': 'evidence'}}, 'prepare')
        interpret = definition(book, {'kind': 'interpretation', 'title': 'Summarize received delivery',
            'description': 'A short evidence-based receiving summary for review.', 'parameters': [item_parameter],
            'payload': {'instruction': 'Extract the exact quantity of bolts explicitly received as a decimal string containing digits only, such as "5". Write one short summary sentence preserving that count. Supply an exact evidence quotation for each output. If missing or ambiguous return needs_input. This is a draft interpretation of actual receipt evidence, not acceptance.',
                        'evidence': ['evidence'], 'outputs': [{'id': 'summary', 'label': 'Summary', 'type': 'text', 'required': True},
                            {'id': 'quantity', 'label': 'Received count', 'type': 'decimal', 'required': True, 'unit': 'items'}],
                        'meaning': 'actual', 'scenario': 'actual'}}, 'interpret')
        content['parameters'] = [p for p in content['parameters'] if p['id'] != 'body']
        content['payload']['steps'][0]['arguments']['body'] = {'step': 'read', 'field': 'summary'}
        content['payload']['steps'][:0] = [
            {'id': 'prepare', 'kind': 'extract', 'binding': {'mode': 'exact', 'versionID': prepare['id']},
             'arguments': {'evidence': {'parameter': 'evidence'}}},
            {'id': 'read', 'kind': 'interpret', 'binding': {'mode': 'exact', 'versionID': interpret['id']},
             'arguments': {'evidence': {'step': 'prepare', 'field': 'item'}}}]
        movement = next(p for p in call('action-registry', book) if p['id'] == 'inventory.proposeMovement')
        stock_action = definition(book, {'kind': 'action', 'title': 'Propose received bolts',
            'description': 'Received item count for explicit inventory review.', 'parameters': movement['parameters'],
            'payload': {'primitive': {'id': movement['id'], 'version': movement['version']},
                        'arguments': {p['id']: {'parameter': p['id']} for p in movement['parameters']}}}, 'stock-action')
        content['payload']['steps'].insert(2, {'id': 'stock', 'kind': 'action',
            'binding': {'mode': 'exact', 'versionID': stock_action['id']}, 'arguments': {
                'subject': {'literal': 'bolts'}, 'quantity': {'step': 'read', 'field': 'quantity', 'unit': 'items'},
                'occurrence': {'literal': 'receiving-report-1'}, 'effective': {'literal': '2026-10-28'},
                'evidence': {'parameter': 'evidence'}, 'meaning': {'literal': 'actual'}}})
        content['payload']['steps'].append({'id': 'stock_review', 'kind': 'review', 'review': 'stock'})
        arguments.pop('body')
    workflow = definition(book, content, 'workflow')
    queued = call('workflow-start', book, workflow['id'], j(arguments), 'start-report')
    assert queued['state'] == 'queued'
    paused = call('workflow-continue', book, queued['id'], args.model_root or root / 'absent-model')
    assert paused['state'] == 'waiting_review', paused
    action_step = next(s for s in paused['steps'] if s['step_id'] == 'report')
    proposal_id = action_step['output']['value']['proposals'][0]
    proposal = call('read', book, proposal_id)['item']
    assert proposal['status'] == 'draft' and proposal['meaning'] == 'estimate'
    if args.model_root:
        prepared, interpreted = paused['steps'][:2]
        value = interpreted['output']['value']
        assert value['request']['evidence'][0]['extractionInputID'] == prepared['output']['value']['extractionInputID']
        assert proposal['text'] == value['response']['values']['summary']
        assert value['response']['values']['quantity'] == '5'
        assert '5' in proposal['text'] and 'bolts' in proposal['text'].lower()
        lineage = call('lineage', book, proposal_id)
        assert any(edge['parent'] == value['recordID'] for edge in lineage)
    assert call('balance', book, 'bolts')['quantity'] == '20'
    accepted = call('accept', book, proposal_id, 'explicit-synthetic-human-review')
    assert accepted['meaning'] == 'estimate'
    assert call('balance', book, 'bolts')['quantity'] == '20'
    if args.model_root:
        stock = next(s for s in paused['steps'] if s['step_id'] == 'stock')['output']['value']['proposals'][0]
        waiting_stock = call('workflow-continue', book, queued['id'], root / 'absent-model')
        assert waiting_stock['state'] == 'waiting_review'
        call('accept', book, stock, 'explicit-synthetic-inventory-review')
    completed = call('workflow-continue', book, queued['id'], root / 'absent-model')
    assert completed['state'] == 'completed'
    copy = root / 'Reconstructed.sevra'
    assert call('reconstruct', book, copy)['execution'] == 'inert'
    assert call('workflow-read', copy, queued['id']) == completed
    assert call('read', copy, accepted['id'])['item']['text'] == proposal['text']
    assert call('balance', copy, 'bolts')['quantity'] == ('25' if args.model_root else '20')
    assert call('verify', copy)['ok'] and call('verify', book)['ok']
    result.update(ok=True, actualModel=bool(args.model_root), waitingReview=paused, completed=completed,
                  proposalID=proposal_id, checks=['registry discovery', 'recoverable native form inputs and exact retry',
                    'multiline Unicode prose', 'explicit workflow continuation', 'exact proposal review',
                    'meaning preserved on acceptance', 'report acceptance leaves stock unchanged',
                    'actual stock25 only after inventory review' if args.model_root else 'stock20 unchanged',
                    'inert reconstruction', 'original and copy integrity'])
    save()
    print(j({'ok': True, 'actualModel': result['actualModel'], 'output': str(args.output or '')}))
except BaseException as error:
    result['failure'] = repr(error)
    save()
    raise
