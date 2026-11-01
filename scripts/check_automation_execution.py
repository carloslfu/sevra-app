#!/usr/bin/env python3
"""Check deliberate foreground draft execution through installed CLI processes."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', required=True, type=Path)
    parser.add_argument('--checks', default=ROOT / '.build/debug/sevra-checks', type=Path)
    parser.add_argument('--worker', default=ROOT / '.build/debug/sevra-automation-durability', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    scratch = None if args.output else tempfile.TemporaryDirectory(prefix='sevra-automation-execution-')
    output = args.output or Path(scratch.name)
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    cli, checks, worker = args.cli.resolve(strict=True), args.checks.resolve(strict=True), args.worker.resolve(strict=True)
    result = {'ok': False, 'cliSHA256': hashlib.sha256(cli.read_bytes()).hexdigest(), 'checksSHA256': hashlib.sha256(checks.read_bytes()).hexdigest(),
              'workerSHA256': hashlib.sha256(worker.read_bytes()).hexdigest(), 'calls': [], 'fixtures': [],
              'limits': ['Independent CLI processes, synthetic deterministic foreground runs, denied AI scope and inert reconstruction.',
                         'No actual model inference, installed timer, persistent device permission, visible interaction or release proof.']}

    def call(*values, error=None):
        p = subprocess.run([str(cli), *map(str, values)], capture_output=True, text=True, timeout=60)
        saved = {'arguments': list(map(str, values)), 'returncode': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr}
        result['calls'].append(saved)
        if error:
            assert p.returncode != 0 and json.loads(p.stderr)['error']['code'] == error, saved
            return
        assert p.returncode == 0, saved
        return json.loads(p.stdout)['result']

    def fixture(flag, name):
        book = output / name
        p = subprocess.run([str(checks), flag, str(book)], capture_output=True, text=True, timeout=90)
        result['fixtures'].append({'arguments': [flag, str(book)], 'returncode': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr})
        assert p.returncode == 0, result['fixtures'][-1]
        return book, json.loads(p.stdout)

    start, due, tomorrow = '2026-10-01T08:00:00Z', '2026-10-01T09:00:00Z', '2026-10-02T09:00:00Z'
    try:
        book, identity = fixture('--automation-execution-fixture', 'Execute.sevra')
        exact = identity['definitionID']
        baseline = call('commits', book)
        for generation in [-1, 'wrong', 1000000000]:
            call('automation-run-once', book, exact, generation, start, due, 'invalid-generation', error='automation_generation')
        call('automation-run-once', book, exact, 0, start, due, 'unknown-option', '--everything', error='usage')
        call('automation-run-once', book, exact, 0, start, due, '', error='workflow_token')
        call('automation-run-once', book, exact, 0, start, due, 'x' * 241, error='workflow_token')
        call('automation-run-once', book, exact, 0, due, start, 'reverse', error='automation_time')
        call('automation-run-once', book, 'unrelated', 0, start, due, 'unrelated', error='definition_not_found')
        assert call('commits', book) == baseline
        first = call('automation-run-once', book, exact, 0, start, due, 'first')
        assert first['permission'] == 'this-process-only' and not first['timerInstalled']
        assert first['dispatch']['status'] == 'queued' and first['run']['state'] == 'completed'
        assert first['run']['policy'] == 'automation-drafts-v1' and first['run']['steps'][0]['output']['value']['result'] == '3'
        source = call('workflow-inspect', book, first['run']['id'])['invocation']
        origin = call('automation-causality', book, first['run']['id'])
        assert origin['origin'] == source['origin']['causality']
        assert origin['origin']['parents'] == [] and origin['origin']['depth'] == 1
        assert origin['rootCharges'][0]['admittedRuns'] == 1 and origin['enabled'] is False
        assert source['origin']['automationID'] == exact and source['actor']['kind'] == 'programmatic'
        assert 'scheduled' in source['description'] and 'manual workflow' not in source['description']
        call('read', book, first['run']['source_id'], error='item_scope')
        after = call('commits', book)
        assert call('automation-run-once', book, exact, 0, start, due, 'first') == first
        assert call('commits', book) == after
        activation = call('automation-activation', book, first['activationID'])
        assert activation['sessionRequired'] and activation['execution'] == 'session-required' and not activation['allowAI']
        assert call('automation-list', book)['execution'] == 'none'
        assert len(call('workflow-list', book)) == 1
        next_run = call('automation-run-once', book, exact, 1, due, tomorrow, 'next')
        assert next_run['generation'] == 2 and next_run['run']['id'] != first['run']['id'] and next_run['run']['state'] == 'completed'
        assert len(call('workflow-list', book)) == 2
        next_origin = call('automation-causality', book, next_run['run']['id'])
        assert next_origin['origin']['roots'] != origin['origin']['roots'] and next_origin['origin']['depth'] == 1
        call('automation-run-once', book, exact, 0, start, due, 'first', error='stale_automation')
        paused = call('automation-pause', book, first['activationID'], 2, 'pause')
        assert paused['state'] == 'paused' and paused['generation'] == 3
        call('automation-run-once', book, exact, 1, due, tomorrow, 'next', error='stale_automation')
        restored = output / 'Inert.sevra'
        assert call('reconstruct', book, restored)['execution'] == 'inert'
        assert call('automation-activation', restored, first['activationID']) == paused
        assert call('workflow-list', restored) == call('workflow-list', book)
        assert call('automation-causality', restored, first['run']['id']) == origin
        assert call('verify', restored)['ok'] and call('verify', book)['ok']
        ai_book, ai_identity = fixture('--automation-ai-fixture', 'AI.sevra')
        initial = call('commits', ai_book)
        call('automation-run-once', ai_book, ai_identity['definitionID'], 0, start, due, 'denied', error='automation_ai_scope')
        assert call('commits', ai_book) == initial and call('automation-list', ai_book)['activations'] == []
        assert call('verify', ai_book)['ok']
        manual_root = output / 'manual'
        manual_root.mkdir()
        for operation in ['setup', 'dispatch']:
            p = subprocess.run([str(worker), operation, str(manual_root)], capture_output=True, text=True, timeout=60)
            result['fixtures'].append({'operation': operation, 'returncode': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr})
            assert p.returncode == 0, result['fixtures'][-1]
        manual_book = manual_root / 'Automation.sevra'
        queued = json.loads(result['fixtures'][-1]['stdout'])
        run_id, activation_id = queued['runs'][0]['id'], queued['activation']['id']
        claim = call('workflow-claim', manual_book, run_id, 'manual-cli', 60, 'claim')
        authorization = call('workflow-inspect', manual_book, run_id)['steps'][0]['attempt']['authorization']
        assert authorization['kind'] == 'workflow_authorization' and authorization['actor']['kind'] == 'programmatic'
        call('read', manual_book, claim['authorization_source'], error='item_scope')
        call('automation-pause', manual_book, activation_id, 1, 'pause')
        assert call('workflow-read', manual_book, run_id)['state'] == 'running'
        heartbeat = call('workflow-heartbeat', manual_book, run_id, json.dumps(claim), 60, 'heartbeat')
        assert heartbeat['authorization_source'] == claim['authorization_source']
        completed = call('workflow-finish', manual_book, run_id, json.dumps(heartbeat))
        assert completed['state'] == 'completed' and completed['policy'] == 'automation-drafts-v1'
        assert call('automation-activation', manual_book, activation_id)['state'] == 'paused'
        assert call('verify', manual_book)['ok']
        result['ok'] = True
    finally:
        (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'ok': result['ok'], 'calls': len(result['calls']), 'output': str(args.output or '')}))


if __name__ == '__main__':
    main()
