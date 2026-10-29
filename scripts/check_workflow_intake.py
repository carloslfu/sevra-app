#!/usr/bin/env python3
"""Independent-process reviewed CSV/TSV workflow, optionally using installed local inference."""
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
root = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='sevra-workflow-intake-'))
if args.output:
    root.mkdir(parents=True, exist_ok=False)
result = {'ok': False, 'calls': [], 'recordedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'cliSHA256': hashlib.sha256(cli.read_bytes()).hexdigest(),
          'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
          'sourceSHA256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in [*sorted((ROOT / 'Sources').rglob('*.swift')), Path(__file__).resolve()]},
          'limits': ['Synthetic included CSV/TSV job, explicit mappings and optional installed local model. No visible UI, Excel continuity, broad accuracy or throughput qualification.']}


def save():
    (root / 'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')


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
    book = root / 'Parts.sevra'
    call('create', book, 'Synthetic reviewed parts update')
    base = root / 'Starting.csv'
    base.write_text('sku,quantity\n0012,4\n0013,5\n')
    initial = call('import', book, base, '--role', 'values', '--token', 'starting')
    dataset = initial['intake']['datasetIDs'][0]
    schema = call('table-schema', book, dataset)
    call('opening', book, 'stock', '20', '2026-10-01', initial['source']['id'])
    incoming = root / 'Incoming.tsv'
    incoming.write_text('code\tamount\tignore\n0012\t7\tnote\n0013\t5\tnote\n0014\t2\tnote\n')
    source = call('import', book, incoming, '--role', 'reference', '--token', 'incoming')['source']['id']
    parameter = {'id': 'file', 'label': 'Incoming file', 'type': 'item', 'required': True}
    intake = definition(book, {
        'kind': 'intake', 'title': 'Update parts', 'description': 'Explicit merge, full stored mapping.',
        'parameters': [parameter], 'payload': {
            'parser': 'native-v1', 'file': 'file', 'datasetID': dataset, 'definitionID': schema['definitionID'],
            'mode': 'merge', 'headerRow': 1, 'mapping': [{'position': 0, 'target': 'sku'},
                {'position': 1, 'target': 'quantity'}, {'position': 2, 'target': None}],
            'keys': ['sku'], 'newRowMeaning': 'estimate', 'newRowScenario': 'actual'}}, 'intake')
    steps = [{'id': 'import_rows', 'kind': 'intake',
              'binding': {'mode': 'exact', 'versionID': intake['id']},
              'arguments': {'file': {'parameter': 'file'}}},
             {'id': 'table_review', 'kind': 'review', 'review': 'import_rows'}]
    if args.model_root:
        extraction = definition(book, {'kind': 'extraction', 'title': 'Prepare incoming file',
            'description': 'Included original', 'parameters': [parameter],
            'payload': {'parser': 'native-v1', 'file': 'file'}}, 'extraction')
        interpretation = definition(book, {'kind': 'interpretation', 'title': 'Explain incoming quantities',
            'description': 'Evidence-bound draft explanation.', 'parameters': [parameter], 'payload': {
                'instruction': 'Read this incoming parts table. Extract the exact amount in the row whose code is 0014 as a decimal string containing digits only. Write one short summary sentence preserving the code 0014 and its amount. Quote exact source text for each output. If ambiguous return needs_input. Do not infer any inventory movement or accepted fact.',
                'evidence': ['file'], 'outputs': [{'id': 'quantity', 'label': 'Amount for 0014',
                    'type': 'decimal', 'unit': 'items', 'required': True},
                    {'id': 'summary', 'label': 'Incoming summary', 'type': 'text', 'required': True}],
                'meaning': 'estimate', 'scenario': 'actual'}}, 'interpretation')
        primitive = next(p for p in call('action-registry', book) if p['id'] == 'records.draftDocument')
        report = definition(book, {'kind': 'action', 'title': 'Draft parts update report',
            'description': 'New explanatory prose for review.', 'parameters': primitive['parameters'],
            'payload': {'primitive': {'id': primitive['id'], 'version': primitive['version']},
                        'arguments': {p['id']: {'parameter': p['id']} for p in primitive['parameters']}}}, 'report')
        steps[0]['arguments']['file'] = {'step': 'prepare', 'field': 'item'}
        steps[:0] = [{'id': 'prepare', 'kind': 'extract',
                     'binding': {'mode': 'exact', 'versionID': extraction['id']},
                     'arguments': {'file': {'parameter': 'file'}}},
                    {'id': 'read', 'kind': 'interpret',
                     'binding': {'mode': 'exact', 'versionID': interpretation['id']},
                     'arguments': {'file': {'step': 'prepare', 'field': 'item'}}}]
        steps.extend([{'id': 'report', 'kind': 'action',
            'binding': {'mode': 'exact', 'versionID': report['id']}, 'arguments': {
                'title': {'literal': 'Incoming parts report'}, 'body': {'step': 'read', 'field': 'summary'},
                'evidence': {'parameter': 'file'}, 'meaning': {'literal': 'estimate'},
                'scenario': {'literal': 'actual'}}},
            {'id': 'report_review', 'kind': 'review', 'review': 'report'}])
    workflow = definition(book, {'kind': 'workflow', 'title': 'Update and review parts',
        'description': 'Explicit foreground intake and exact review.', 'parameters': [parameter],
        'payload': {'readPolicy': 'latest-at-step', 'steps': steps}}, 'workflow')
    form = definition(book, call('form-template', book, workflow['id']), 'form')
    state = call('form-draft-new', book, form['id'])
    state['arguments'] = {'file': source}
    state = call('form-draft-save', book, 'parts', j(state), 'null')
    before = call('rows', book, dataset)
    preview = call('form-draft-preview', book, j(state))
    receipt = call('form-draft-submit', book, j(state), j(preview))
    assert call('form-draft-submit', book, j(state), j(preview)) == receipt
    run_id = receipt['workflowRunID']
    assert call('workflow-read', book, run_id)['state'] == 'queued'
    assert call('rows', book, dataset) == before, 'Form submission applied rows'
    waiting = call('workflow-continue', book, run_id, args.model_root or root / 'absent-model')
    assert waiting['state'] == 'waiting_review'
    step = next(s for s in waiting['steps'] if s['step_id'] == 'import_rows')
    summary = step['output']['value']['summary']
    assert (summary['added'], summary['changed'], summary['unchanged'], summary['removed']) == (1, 1, 1, 0)
    draft_id = step['output']['value']['proposals'][0]
    draft = call('read', book, draft_id)['item']
    assert draft['status'] == 'draft' and len(draft['data']['incoming']) == 3
    assert draft['data']['incoming'][0]['sku'] == '0012'
    assert draft['data']['additionRecords'] == [4]
    assert call('rows', book, dataset) == before, 'Preparation applied rows'
    if args.model_root:
        interpretation = next(s for s in waiting['steps'] if s['step_id'] == 'read')['output']['value']
        assert interpretation['response']['values']['quantity'] == '2'
        assert '0014' in interpretation['response']['values']['summary']
        result['interpretation'] = interpretation
    accepted = call('accept', book, draft_id, 'review-table-once')
    assert call('accept', book, draft_id, 'review-table-once') == accepted
    rows = call('rows', book, dataset)
    assert [r['data'] for r in rows] == [{'sku': '0012', 'quantity': '7'},
        {'sku': '0013', 'quantity': '5'}, {'sku': '0014', 'quantity': '2'}]
    assert [r['meaning'] for r in rows] == ['actual', 'actual', 'estimate']
    assert call('balance', book, 'stock')['quantity'] == '20'
    completed = call('workflow-continue', book, run_id, root / 'absent-model')
    if args.model_root:
        assert completed['state'] == 'waiting_review'
        report_id = next(s for s in completed['steps'] if s['step_id'] == 'report')['output']['value']['proposals'][0]
        report_item = call('read', book, report_id)['item']
        assert report_item['text'] == interpretation['response']['values']['summary']
        assert report_item['meaning'] == 'estimate'
        call('accept', book, report_id, 'review-report-once')
        completed = call('workflow-continue', book, run_id, root / 'absent-model')
    assert completed['state'] == 'completed'
    assert call('workflow-continue', book, run_id, root / 'absent-model') == completed
    copy = root / 'Reconstructed.sevra'
    assert call('reconstruct', book, copy)['execution'] == 'inert'
    assert call('workflow-read', copy, run_id) == completed
    assert call('rows', copy, dataset) == rows
    assert call('verify', copy)['ok'] and call('verify', book)['ok']
    result.update(ok=True, actualModel=bool(args.model_root), waitingReview=waiting, completed=completed,
                  proposalID=draft_id, checks=['recoverable form queues without parsing or applying',
                    'native isolated TSV parser', 'full explicit mapping and lexical SKU preservation',
                    'changed/added/unchanged counts', 'exact row coordinates and retained plan',
                    'exact acceptance retry', 'new row estimate preserved', 'stock20 unchanged',
                    'completed steps not repeated', 'inert reconstruction', 'original/copy integrity'])
    save()
    print(j({'ok': True, 'actualModel': result['actualModel'], 'calls': len(result['calls']), 'output': str(root)}))
except BaseException as error:
    result['failure'] = repr(error)
    save()
    raise
