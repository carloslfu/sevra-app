#!/usr/bin/env python3
"""Actual packaged local-model preparation; synthetic paused input and no submission."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, required=True)
    parser.add_argument('--worker', type=Path, required=True)
    parser.add_argument('--model-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    cli, worker = args.cli.resolve(strict=True), args.worker.resolve(strict=True)
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    result = {'ok': False, 'recordedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'sourceSHA256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in [*sorted((ROOT / 'Sources').rglob('*.swift')), Path(__file__).resolve()]},
              'products': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [cli, worker]},
              'pins': {str(p.relative_to(ROOT)): json.loads(p.read_text()) for p in
                       [ROOT / 'integration/splash.json', ROOT / 'integration/llguidance.json']},
              'calls': [], 'cases': [],
              'limits': ['Synthetic paused model response; actual packaged inference prepares unsent inputs only.',
                         'No real human submission, voice/visible UI, throughput or broad accuracy qualification.']}

    def save():
        (root / 'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')

    def call(command, *values):
        p = subprocess.run([str(cli), command, *map(str, values)], capture_output=True, text=True, timeout=360)
        result['calls'].append({'command': command, 'arguments': list(map(str, values)),
                                'returncode': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr})
        save()
        assert p.returncode == 0, result['calls'][-1]
        response = json.loads(p.stdout)
        assert response['ok'], response
        return response['result']

    def j(value):
        return json.dumps(value, ensure_ascii=False)

    def draft(book, run_id):
        with sqlite3.connect(f'file:{book / "workbook.sqlite"}?mode=ro', uri=True) as db:
            row = db.execute('SELECT value FROM meta WHERE key=?', ('workflow-clarification-draft:' + run_id,)).fetchone()
            return json.loads(row[0]) if row else None

    def fixture(folder):
        folder.mkdir()
        book = folder / 'Clarification.sevra'
        call('create', book, 'Synthetic conversation answer')
        source = call('add', book, j({'category': 'source', 'kind': 'observation', 'title': 'Delivery D9',
                                    'text': 'Bolts arrived; the received count was not recorded.'}))
        call('opening', book, 'bolts', '20', '2026-10-01', source['id'])
        parameter = {'id': 'evidence', 'label': 'Evidence', 'type': 'item', 'required': True}
        def definition(content):
            return call('definition-save', book, uuid.uuid4(), j(content), 'new', uuid.uuid4())
        interpretation = definition({'kind': 'interpretation', 'title': 'Read received count',
            'description': 'Synthetic missing information.', 'parameters': [parameter],
            'payload': {'instruction': 'Extract only the explicitly stated received count; ask when missing.',
                        'evidence': ['evidence'], 'outputs': [{'id': 'quantity', 'label': 'Received count',
                         'type': 'decimal', 'unit': 'items', 'required': True}], 'meaning': 'actual', 'scenario': 'actual'}})
        function = definition({'kind': 'function', 'title': 'Double count', 'description': 'Synthetic',
            'parameters': [{'id': 'quantity', 'label': 'Count', 'type': 'decimal', 'unit': 'items', 'required': True}],
            'payload': {'expression': 'quantity*2', 'unit': 'items'}})
        workflow = definition({'kind': 'workflow', 'title': 'Read and double', 'description': 'Synthetic',
            'parameters': [parameter], 'payload': {'readPolicy': 'latest-at-step', 'steps': [
                {'id': 'read', 'kind': 'interpret', 'binding': {'mode': 'exact', 'versionID': interpretation['id']},
                 'arguments': {'evidence': {'parameter': 'evidence'}}},
                {'id': 'double', 'kind': 'evaluate', 'binding': {'mode': 'exact', 'versionID': function['id']},
                 'arguments': {'quantity': {'step': 'read', 'field': 'quantity', 'unit': 'items'}}}]}})
        run_id = call('workflow-start', book, workflow['id'], j({'evidence': source['id']}), uuid.uuid4())['id']
        (folder / 'plan.json').write_text(j({'runID': run_id}))
        p = subprocess.run([str(worker), 'clarify-pause', str(folder)], capture_output=True, text=True, timeout=60)
        result['calls'].append({'worker': 'clarify-pause', 'returncode': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr})
        save()
        assert p.returncode == 0, result['calls'][-1]
        original = json.loads(p.stdout)['run']
        assert original['state'] == 'needs_attention'
        return book, run_id, original

    try:
        for read_only in [False, True]:
            folder = root / ('read-only' if read_only else 'supplied')
            book, run_id, original = fixture(folder)
            prompt = ('What information is missing from this workflow? Explain only. Do not change anything.' if read_only else
                      'I counted 5 received bolts. Prepare my answer for the missing count, leaving it unsent for me to preview and confirm. '
                      'Do not continue the workflow or accept inventory.') + ' Workflow run: ' + run_id
            response = call('ask', book, prompt, args.model_root)
            saved = draft(book, run_id)
            current = call('workflow-read', book, run_id)
            assert current == original, 'Answer preparation changed the paused workflow'
            assert call('balance', book, 'bolts')['quantity'] == '20'
            if read_only:
                assert saved is None, 'Read-only question prepared input'
            else:
                assert saved and saved['entry']['values'] == {'quantity': '5'}, saved
                assert saved['entry'].get('receipt') is None
                preparation = saved['entry']['preparation']
                assert preparation['values'] == {'quantity': '5'}
                assert set(preparation['quotes']) == {'quantity'}
                assert preparation['quotes']['quantity'].encode() in prompt.encode()
                with sqlite3.connect(f'file:{book / "workbook.sqlite"}?mode=ro', uri=True) as db:
                    source = db.execute('SELECT body FROM items WHERE id=?', (preparation['requestSourceID'],)).fetchone()
                    assert source and source[0] == prompt, source
                assert 'unsent' in response['answer'].lower(), response
            copy = folder / 'InertCopy.sevra'
            assert call('reconstruct', book, copy)['execution'] == 'inert'
            assert draft(copy, run_id) == saved
            assert call('workflow-read', copy, run_id) == original
            assert call('verify', book)['ok'] and call('verify', copy)['ok']
            result['cases'].append({'readOnly': read_only, 'response': response, 'draft': saved, 'runUnchanged': True})
            save()
        result['ok'] = True
        save()
        print(j({'ok': True, 'calls': len(result['calls']), 'output': str(root)}))
    except BaseException as error:
        result['failure'] = repr(error)
        save()
        raise


if __name__ == '__main__':
    main()
