#!/usr/bin/env python3
"""Exercise manual workflow CLI contracts across independent native processes."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cli', type=Path, required=True)
parser.add_argument('--worker', type=Path, required=True)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
cli, worker = args.cli.resolve(strict=True), args.worker.resolve(strict=True)
result = {'ok': False, 'calls': [], 'checks': []}


def j(value):
    return json.dumps(value)


def call(*values, error=None):
    p = subprocess.run([str(cli), *map(str, values)], capture_output=True, text=True, timeout=60)
    reply = json.loads(p.stderr if p.returncode else p.stdout)
    result['calls'].append({'command': values[0], 'returncode': p.returncode, 'reply': reply})
    if error:
        assert p.returncode == 1 and reply['error']['code'] == error, reply
        return None
    assert p.returncode == 0 and reply['ok'], reply
    return reply['result']


try:
    with tempfile.TemporaryDirectory(prefix='sevra-workflow-cli-') as directory:
        root = Path(directory)
        setup = subprocess.run([str(worker), 'setup', str(root)], capture_output=True, text=True, timeout=60)
        assert setup.returncode == 0, setup.stderr
        baseline = json.loads(setup.stdout)
        book = root / 'Workflow.sevra'
        run_id = baseline['run']['id']
        run = call('workflow-read', book, run_id)
        assert run == baseline['run']
        assert call('definition-search', book, 'Receive', j({'kind': 'workflow'}))['hits'][0]['id'] == run['definition_id']
        assert call('workflow-list', book, 'queued')[0]['id'] == run_id
        claim = call('workflow-claim', book, run_id, 'cli-test', 30, 'claim')
        call('workflow-claim', book, run_id, 'competitor', 30, 'competing', error='workflow_busy')
        call('workflow-heartbeat', book, run_id, j(claim), 30, 'heartbeat')
        proposed = call('workflow-finish', book, run_id, j(claim))
        history = call('commits', book, 1000)
        assert call('workflow-finish', book, run_id, j(claim)) == proposed
        assert call('commits', book, 1000) == history
        assert call('workflow-advance', book, run_id)['state'] == 'waiting_review'
        proposal = proposed['steps'][1]['output']['value']['proposals'][0]
        call('accept', book, proposal)
        assert call('workflow-advance', book, run_id)['state'] == 'completed'
        assert call('balance', book, 'bolts')['quantity'] == '25'
        # Delivery occurrence identity still matters across different workflow runs.
        duplicate = call('workflow-start', book, run['definition_id'], j(run['arguments']), 'duplicate')
        call('workflow-advance', book, duplicate['id'])
        call('workflow-advance', book, duplicate['id'], error='duplicate_effect')
        assert call('workflow-read', book, duplicate['id'])['state'] == 'needs_attention'
        call('workflow-retry', book, duplicate['id'], 'retry')
        call('workflow-advance', book, duplicate['id'], error='duplicate_effect')
        call('workflow-cancel', book, duplicate['id'], 'cancel')
        assert call('balance', book, 'bolts')['quantity'] == '25'
        different = dict(run['arguments'], delivery='delivery-two')
        second = call('workflow-start', book, run['definition_id'], j(different), 'second')
        call('workflow-advance', book, second['id'])
        second = call('workflow-advance', book, second['id'])
        call('accept', book, second['steps'][1]['output']['value']['proposals'][0])
        assert call('workflow-advance', book, second['id'])['state'] == 'completed'
        assert call('balance', book, 'bolts')['quantity'] == '30'
        third = call('workflow-start', book, run['definition_id'], j(dict(different, delivery='delivery-three')), 'third')
        stale = call('workflow-claim', book, third['id'], 'stopped-worker', 30, 'third-claim')
        cancelled = call('workflow-cancel', book, third['id'], 'stop')
        call('workflow-finish', book, third['id'], j(stale), error='workflow_fenced')
        assert cancelled['state'] == 'cancelled'
        assert call('balance', book, 'bolts')['quantity'] == '30'
        assert call('verify', book)['ok']
        events = call('workflow-events', book)
        assert events['events'] and isinstance(events['after'], int)
        invalid = dict(run['arguments'], unknown='not declared')
        call('workflow-start', book, run['definition_id'], j(invalid), 'invalid', error='definition_input')
        result['checks'] = ['CLI claim/heartbeat/fenced finish and exact retries',
                            'review wait and canonical business acceptance',
                            'duplicate evidence versus two genuine deliveries',
                            'explicit retry and cancellation preserve completed effects',
                            'bounded discovery, events and validation']
        result['ok'] = True
finally:
    if args.output:
        args.output.write_text(j(result) + '\n')
print(j({'ok': result['ok'], 'checks': result['checks']}))
