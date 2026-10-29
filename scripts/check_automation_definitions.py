#!/usr/bin/env python3
"""Qualify inert exact-bound automation definitions through independent CLI processes."""
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    cli = args.cli.resolve(strict=True)
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='sevra-automation-'))
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    result = {'ok': False, 'calls': [],
              'recordedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'cliSHA256': hashlib.sha256(cli.read_bytes()).hexdigest(),
              'sourceSHA256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in [*sorted((ROOT / 'Sources').rglob('*.swift')), Path(__file__).resolve()]},
              'limits': ['Synthetic metadata and schedule preview only. No automation activation, '
                         'trigger dispatch, model inference, background work, native configuration or release qualification.']}

    def save():
        (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')

    def j(value):
        return json.dumps(value)

    def call(command, *values, error=None):
        started = time.monotonic()
        p = subprocess.run([str(cli), command, *map(str, values)], capture_output=True, text=True, timeout=60)
        result['calls'].append({'command': command, 'arguments': list(map(str, values)),
                                'expectedError': error, 'returncode': p.returncode,
                                'seconds': time.monotonic() - started, 'stdout': p.stdout, 'stderr': p.stderr})
        save()
        if error:
            assert p.returncode != 0, result['calls'][-1]
            envelope = json.loads(p.stderr.strip().splitlines()[-1])
            assert not envelope['ok'] and envelope['error']['code'] == error, envelope
            return envelope
        assert p.returncode == 0, result['calls'][-1]
        envelope = json.loads(p.stdout)
        assert envelope['ok'], envelope
        return envelope['result']

    book = output / 'Synthetic.sevra'
    try:
        call('create', book, 'Synthetic inert calendar intentions')
        first = call('add', book, j({'category': 'source', 'kind': 'observation', 'title': 'Observed count'}))
        second = call('add', book, j({'category': 'source', 'kind': 'note', 'title': 'Supporting attachment'}))
        parameters = [
            {'id': 'quantity', 'label': 'Count', 'type': 'decimal', 'required': True, 'unit': 'items'},
            {'id': 'evidence', 'label': 'Evidence', 'type': 'item', 'required': True},
            {'id': 'entries', 'label': 'Entries', 'type': 'entries', 'required': True, 'maxEntries': 3,
             'fields': [{'id': 'attachment', 'label': 'Attachment', 'type': 'item', 'required': True}]},
        ]
        function = call('definition-save', book, uuid.uuid4(), j({
            'kind': 'function', 'title': 'Double count', 'description': 'Synthetic pure calculation',
            'parameters': parameters, 'payload': {'expression': 'quantity*2', 'unit': 'items'}}), 'new', 'function')
        workflow_content = {'kind': 'workflow', 'title': 'Explicit calculation workflow',
                            'description': 'Saved metadata does not run it.', 'parameters': parameters,
                            'payload': {'readPolicy': 'latest-at-step', 'steps': [{
                                'id': 'calculate', 'kind': 'evaluate',
                                'binding': {'mode': 'exact', 'versionID': function['id']},
                                'arguments': {p['id']: {'parameter': p['id']} for p in parameters}}]}}
        workflow_logical = str(uuid.uuid4())
        workflow = call('definition-save', book, workflow_logical, j(workflow_content), 'new', 'workflow')
        content = {'kind': 'automation', 'title': 'Weekday inventory summary',
                   'description': 'A portable inert intention, never an activation grant.', 'parameters': [],
                   'payload': {'policy': 'calendar-drafts-v1',
                               'workflow': {'mode': 'exact', 'versionID': workflow['id']},
                               'arguments': {'quantity': '5.00', 'evidence': first['id'],
                                             'entries': [{'attachment': second['id']}]},
                               'schedule': {'policy': 'native-calendar-v1', 'timeZone': 'America/Bogota',
                                            'hour': 9, 'minute': 0,
                                            'recurrence': {'kind': 'weekly', 'weekdays': [1, 2, 3, 4, 5]}}}}
        logical = str(uuid.uuid4())
        saved = call('definition-save', book, logical, j(content), 'new', 'automation')
        assert call('definition-save', book, logical, j(content), 'new', 'automation') == saved
        history = call('commits', book)
        counts = call('inspect', book)
        preview = call('automation-preview', book, saved['id'], '2026-10-29T12:00:00Z', 2)
        assert preview['execution'] == 'inert' and not preview['enabled']
        assert preview['workflowID'] == workflow['id'] and preview['arguments']['quantity'] == '5'
        assert saved['payload']['arguments']['quantity'] == '5.00'
        assert preview['calendar']['occurrences'][0]['due'] == '2026-10-29T14:00:00.000Z'
        parents = {r['parent'] for r in call('lineage', book, saved['sourceID'])}
        assert {first['id'], second['id'], workflow['sourceID']} <= parents
        assert call('definition-dependencies', book, saved['id'])[0]['target_version'] == workflow['id']
        hits = call('definition-search', book, 'weekday', j({'kind': 'automation'}))['hits']
        assert len(hits) == 1 and hits[0]['id'] == saved['id']
        assert call('inspect', book) == counts and call('commits', book) == history
        assert call('workflow-list', book) == []
        call('automation-preview', book, logical, '2026-10-29T12:00:00Z', error='automation_binding')
        call('automation-preview', book, saved['id'], '2026-10-29', error='date')
        call('workflow-start', book, saved['id'], '{}', 'no-activation', error='workflow_definition')
        call('definition-evaluate', book, saved['id'], '{}', error='definition_kind')
        rejected = json.loads(j(content))
        rejected['payload']['enabled'] = True
        call('definition-save', book, uuid.uuid4(), j(rejected), 'new', 'not-enabled', error='automation_definition')
        rejected = json.loads(j(content))
        rejected['payload']['arguments']['quantity'] = 5
        call('definition-save', book, uuid.uuid4(), j(rejected), 'new', 'wrong-type', error='definition_input')
        assert call('inspect', book) == counts and call('commits', book) == history
        workflow_content['title'] = 'Later workflow version'
        new_workflow = call('definition-save', book, workflow_logical, j(workflow_content), workflow['id'], 'workflow-v2')
        assert call('automation-preview', book, saved['id'], '2026-10-29T12:00:00Z', 2) == preview
        content['payload']['workflow']['versionID'] = new_workflow['id']
        updated = call('definition-save', book, logical, j(content), saved['id'], 'automation-v2')
        assert updated['version'] == 2 and updated['previousID'] == saved['id']
        call('definition-save', book, logical, j(content), saved['id'], 'stale-edit', error='stale_definition')
        call('definition-save', book, logical, j(content), 'new', 'automation', error='idempotency')
        restored_definition = call('definition-restore', book, logical, saved['id'], updated['id'], 'restore')
        assert restored_definition['version'] == 3 and restored_definition['payload'] == saved['payload']
        assert call('verify', book)['ok']
        copy = output / 'Inert.sevra'
        assert call('reconstruct', book, copy)['execution'] == 'inert'
        assert call('automation-preview', copy, saved['id'], '2026-10-29T12:00:00Z', 2) == preview
        assert call('workflow-list', copy) == [] and call('workflow-events', copy)['events'] == []
        assert call('verify', copy)['ok']
        result['ok'] = True
    finally:
        save()
    print(json.dumps({'ok': result['ok'], 'calls': len(result['calls']), 'output': str(output)}))


if __name__ == '__main__':
    main()
