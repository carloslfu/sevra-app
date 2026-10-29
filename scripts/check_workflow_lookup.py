#!/usr/bin/env python3
"""Qualify exact catalog lookup, repair and reviewed receiving in independent CLI processes."""
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
root = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='sevra-workflow-lookup-'))
if args.output:
    root.mkdir(parents=True, exist_ok=False)
result = {'ok': False, 'calls': [], 'recordedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'cliSHA256': hashlib.sha256(cli.read_bytes()).hexdigest(),
          'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
          'sourceSHA256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in [*sorted((ROOT / 'Sources').rglob('*.swift')), Path(__file__).resolve()]},
          'integrationPins': {name: json.loads((ROOT / name).read_text()) for name in [
              'integration/splash.json', 'integration/llguidance.json',
              'Sources/SevraSplash/Resources/selected-model.json']},
          'installedRuntimeSHA256': {name: hashlib.sha256((cli.parent / name).read_bytes()).hexdigest()
              for name in ['native-runtime.json', 'NativeRuntime/engine/splash',
                           'NativeRuntime/engine/splash.metallib', 'NativeRuntime/libllguidance.dylib']
              if (cli.parent / name).is_file()},
          'limits': ['Synthetic exact single-table match with explicit repair/review. No fuzzy matching, '
                     'inline human answers, visible UI, broad model accuracy or throughput qualification.']}


def save():
    (root / 'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')


def j(value):
    return json.dumps(value, ensure_ascii=False)


def call(command, *values, error=None):
    started = time.monotonic()
    process = subprocess.run([str(cli), command, *map(str, values)], capture_output=True, text=True, timeout=240)
    entry = {'command': command, 'arguments': list(map(str, values)), 'returncode': process.returncode,
             'seconds': time.monotonic() - started, 'stdout': process.stdout, 'stderr': process.stderr}
    result['calls'].append(entry)
    save()
    if error:
        assert process.returncode != 0, entry
        envelope = json.loads(process.stderr.strip().splitlines()[-1])
        assert not envelope['ok'] and envelope['error']['code'] == error, envelope
        return envelope
    assert process.returncode == 0, entry
    envelope = json.loads(process.stdout)
    assert envelope['ok'], envelope
    return envelope['result']


def definition(book, content, token):
    return call('definition-save', book, uuid.uuid4(), j(content), 'new', token)


def action(book, registry, primitive_id, title):
    primitive = next(p for p in registry if p['id'] == primitive_id)
    return definition(book, {'kind': 'action', 'title': title, 'description': 'Explicit synthetic review.',
        'parameters': primitive['parameters'], 'payload': {
            'primitive': {'id': primitive['id'], 'version': primitive['version']},
            'arguments': {p['id']: {'parameter': p['id']} for p in primitive['parameters']}}}, primitive_id)


def step(run, name):
    return next(s for s in run['steps'] if s['step_id'] == name)


try:
    result['productVersion'] = call('version')
    book = root / 'Receiving.sevra'
    call('create', book, 'Synthetic catalog receiving')
    catalog = root / 'Catalog.csv'
    catalog.write_text('code,subject\nunmapped,bolts\n')
    imported = call('import', book, catalog, '--role', 'values', '--token', 'catalog')
    dataset = imported['intake']['datasetIDs'][0]
    schema = call('table-schema', book, dataset)
    call('opening', book, 'bolts', '20', '2026-10-01', imported['source']['id'])
    delivery = root / 'Delivery.txt'
    delivery.write_text('Delivery D7 on 2026-10-29: received 5 units of supplier code 0007.\n')
    evidence = call('import', book, delivery, '--role', 'reference', '--token', 'delivery')['source']['id']
    parameter = {'id': 'file', 'label': 'Delivery evidence', 'type': 'item', 'required': True}
    query = definition(book, {'kind': 'query', 'title': 'Find exact supplier code',
        'description': 'One explicit catalog key, with no fuzzy selection.',
        'parameters': [{'id': 'code', 'label': 'Supplier code', 'type': 'text', 'required': True}],
        'payload': {'dataMode': 'exact', 'query': {
            'sources': [{'datasetID': dataset, 'definitionID': schema['definitionID']}],
            'select': [{'id': 'subject', 'column': {'source': 0, 'column': 'subject'}}],
            'filters': [{'column': {'source': 0, 'column': 'code'}, 'op': 'eq',
                         'value': {'parameter': 'code'}}], 'limit': 10}}}, 'query')
    registry = call('action-registry', book)
    movement = action(book, registry, 'inventory.proposeMovement', 'Draft matched receipt')
    steps = [{'id': 'match', 'kind': 'evaluate', 'binding': {'mode': 'exact', 'versionID': query['id']},
              'arguments': {'code': {'literal': '0007'}}},
             {'id': 'stock', 'kind': 'action', 'binding': {'mode': 'exact', 'versionID': movement['id']},
              'arguments': {'subject': {'step': 'match', 'field': 'subject'},
                            'quantity': {'literal': '5', 'unit': 'items'},
                            'occurrence': {'literal': 'delivery-d7'},
                            'effective': {'literal': '2026-10-29'},
                            'evidence': {'parameter': 'file'}, 'meaning': {'literal': 'actual'}}},
             {'id': 'stock_review', 'kind': 'review', 'review': 'stock'}]
    if args.model_root:
        extraction = definition(book, {'kind': 'extraction', 'title': 'Prepare delivery',
            'description': 'Bounded included original.', 'parameters': [parameter],
            'payload': {'parser': 'native-v1', 'file': 'file'}}, 'prepare')
        interpretation = definition(book, {'kind': 'interpretation', 'title': 'Read supplier delivery',
            'description': 'Evidence-bound code and received count.', 'parameters': [parameter],
            'payload': {'instruction': 'Extract the exact supplier code as text, preserving every leading zero. '
                'Extract the explicitly received unit count as a decimal string containing digits only. '
                'Write one short summary preserving that code and count. Quote exact source text for each output. '
                'If anything is missing or ambiguous return needs_input. Do not select a catalog product or accept stock.',
                'evidence': ['file'], 'outputs': [
                    {'id': 'code', 'label': 'Supplier code', 'type': 'text', 'required': True},
                    {'id': 'quantity', 'label': 'Received count', 'type': 'decimal', 'unit': 'items', 'required': True},
                    {'id': 'summary', 'label': 'Summary', 'type': 'text', 'required': True}],
                'meaning': 'actual', 'scenario': 'actual'}}, 'read')
        steps[0]['arguments']['code'] = {'step': 'read', 'field': 'code'}
        steps[1]['arguments']['quantity'] = {'step': 'read', 'field': 'quantity', 'unit': 'items'}
        steps[:0] = [{'id': 'prepare', 'kind': 'extract',
                     'binding': {'mode': 'exact', 'versionID': extraction['id']},
                     'arguments': {'file': {'parameter': 'file'}}},
                    {'id': 'read', 'kind': 'interpret',
                     'binding': {'mode': 'exact', 'versionID': interpretation['id']},
                     'arguments': {'file': {'step': 'prepare', 'field': 'item'}}}]
        report = action(book, registry, 'records.draftDocument', 'Draft receiving report')
        steps.extend([{'id': 'report', 'kind': 'action',
            'binding': {'mode': 'exact', 'versionID': report['id']}, 'arguments': {
                'title': {'literal': 'Delivery receiving report'}, 'body': {'step': 'read', 'field': 'summary'},
                'evidence': {'parameter': 'file'}, 'meaning': {'literal': 'estimate'},
                'scenario': {'literal': 'actual'}}},
            {'id': 'report_review', 'kind': 'review', 'review': 'report'}])
    workflow = definition(book, {'kind': 'workflow', 'title': 'Receive by supplier code',
        'description': 'Prepare, match, repair if needed, propose and explicitly review.',
        'parameters': [parameter], 'payload': {'readPolicy': 'latest-at-step', 'steps': steps}}, 'workflow')
    queued = call('workflow-start', book, workflow['id'], j({'file': evidence}), 'start')
    assert queued['state'] == 'queued'
    run_id = queued['id']
    call('workflow-continue', book, run_id, args.model_root or root / 'absent-model', error='workflow_lookup')
    paused = call('workflow-read', book, run_id)
    assert paused['state'] == 'needs_attention' and step(paused, 'match')['output'] is None
    assert step(paused, 'stock')['output'] is None
    assert call('balance', book, 'bolts')['quantity'] == '20'
    if args.model_root:
        interpreted = step(paused, 'read')['output']['value']
        assert interpreted['response']['values']['code'] == '0007'
        assert interpreted['response']['values']['quantity'] == '5'
        assert step(paused, 'prepare')['state'] == 'completed'
        result['interpretation'] = interpreted
    rows = call('rows', book, dataset)
    assert len(rows) == 1
    call('edit-row', book, rows[0]['id'], j(dict(rows[0]['data'], code='0007')))
    repaired = call('rows', book, dataset)[0]
    call('workflow-retry', book, run_id, 'catalog-repaired')
    waiting = call('workflow-continue', book, run_id, root / 'absent-model')
    assert waiting['state'] == 'waiting_review'
    if args.model_root:
        for name in ['prepare', 'read']:
            assert step(waiting, name)['output'] == step(paused, name)['output'], 'Repeated completed AI prefix'
    match = step(waiting, 'match')['output']['value']
    assert len(match['result']['rows']) == 1
    assert match['result']['rows'][0]['values']['subject'] == 'bolts'
    assert match['result']['rows'][0]['inputs'][0]['versionID'] == repaired['id']
    stock = step(waiting, 'stock')['output']['value']
    parents = {edge['parent'] for edge in call('lineage', book, stock['sourceID'])}
    assert {query['sourceID'], repaired['id']}.issubset(parents)
    proposal = stock['proposals'][0]
    assert call('read', book, proposal)['item']['status'] == 'draft'
    assert call('balance', book, 'bolts')['quantity'] == '20'
    accepted = call('accept', book, proposal, 'explicit-synthetic-stock-review')
    assert call('accept', book, proposal, 'explicit-synthetic-stock-review') == accepted
    assert call('balance', book, 'bolts')['quantity'] == '25'
    completed = call('workflow-continue', book, run_id, root / 'absent-model')
    if args.model_root:
        assert completed['state'] == 'waiting_review'
        report_id = step(completed, 'report')['output']['value']['proposals'][0]
        report_item = call('read', book, report_id)['item']
        assert report_item['text'] == interpreted['response']['values']['summary']
        assert report_item['meaning'] == 'estimate'
        call('accept', book, report_id, 'explicit-synthetic-report-review')
        assert call('balance', book, 'bolts')['quantity'] == '25'
        completed = call('workflow-continue', book, run_id, root / 'absent-model')
    assert completed['state'] == 'completed'
    assert call('workflow-continue', book, run_id, root / 'absent-model') == completed
    copy = root / 'Reconstructed.sevra'
    assert call('reconstruct', book, copy)['execution'] == 'inert'
    assert call('workflow-read', copy, run_id) == completed
    assert call('balance', copy, 'bolts')['quantity'] == '25'
    assert call('verify', copy)['ok'] and call('verify', book)['ok']
    result.update(ok=True, actualModel=bool(args.model_root), paused=paused, waitingReview=waiting,
                  completed=completed, checks=['zero-match attention before query checkpoint',
                    'catalog repair and explicit same-run retry', 'completed extraction/AI prefix preserved',
                    'lexical leading-zero code', 'exact query and selected row lineage',
                    'stock20 before review and25 after exact review once', 'report preserves estimate meaning',
                    'completed retry stable', 'inert reconstruction', 'original/copy integrity'])
    save()
    print(j({'ok': True, 'actualModel': result['actualModel'], 'calls': len(result['calls']), 'output': str(root)}))
except BaseException as error:
    result['failure'] = repr(error)
    save()
    raise
