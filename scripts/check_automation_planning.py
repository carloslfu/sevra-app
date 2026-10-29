#!/usr/bin/env python3
"""Check saved preparation state through installed CLI processes, without execution."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cli', required=True, type=Path)
    parser.add_argument('--checks', default=Path('.build/debug/sevra-checks'), type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    output = args.output or Path(tempfile.mkdtemp(prefix='sevra-automation-planning-'))
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    cli, checks = args.cli.resolve(), args.checks.resolve()
    result = {'ok': False, 'cliSHA256': hashlib.sha256(cli.read_bytes()).hexdigest(),
              'checksSHA256': hashlib.sha256(checks.read_bytes()).hexdigest(), 'calls': []}

    def call(*values, error=None):
        process = subprocess.run([str(cli), *map(str, values)], capture_output=True, text=True, timeout=60)
        result['calls'].append({'arguments': list(map(str, values)), 'returncode': process.returncode,
                                'stdout': process.stdout, 'stderr': process.stderr})
        if error:
            assert process.returncode != 0, result['calls'][-1]
            assert json.loads(process.stderr)['error']['code'] == error, result['calls'][-1]
            return
        assert process.returncode == 0, result['calls'][-1]
        return json.loads(process.stdout)['result']

    try:
        book = output / 'Prepared.sevra'
        fixture = subprocess.run([str(checks), '--automation-planning-fixture', str(book)],
                                 capture_output=True, text=True, timeout=90)
        result['fixture'] = {'returncode': fixture.returncode, 'stdout': fixture.stdout, 'stderr': fixture.stderr}
        assert fixture.returncode == 0, result['fixture']
        identity = json.loads(fixture.stdout)
        activation = identity['activationID']
        armed = call('automation-activation', book, activation)
        assert armed['state'] == 'armed' and armed['sessionRequired'] and armed['execution'] == 'preparation-only'
        assert armed['definition_id'] == identity['definitionID'] and armed['generation'] == 1
        commits, counts = call('commits', book), call('inspect', book)
        discovered = call('automation-list', book, '-', 1)
        assert discovered['activations'] == [armed] and not discovered['hasMore']
        assert call('automation-list', book, activation)['activations'] == []
        call('automation-list', book, '-', 51, error='automation_limit')
        page = call('automation-occurrences', book, activation, '-', 2)
        assert page['hasMore'] and len(page['occurrences']) == 2
        next_page = call('automation-occurrences', book, activation, page['nextCursor'], 2)
        assert not next_page['hasMore'] and len(next_page['occurrences']) == 2
        assert [row['detail'] for row in page['occurrences'] + next_page['occurrences']] == [
            'late', 'late', 'coalesced', 'awaiting_dispatch']
        event = call('automation-events', book, 0, 1)
        assert event['hasMore'] and event['events'][0]['kind'] == 'authorized'
        assert call('automation-events', book, event['after'])['events'][0]['kind'] == 'planned'
        assert call('workflow-list', book) == []
        call('automation-occurrences', book, activation, '-', 51, error='automation_limit')
        call('automation-occurrences', book, activation, 'unrelated', 2, error='automation_cursor')
        call('automation-events', book, -1, error='automation_limit')
        call('automation-activation', book, 'unrelated', error='automation_not_found')
        assert call('commits', book) == commits and call('inspect', book) == counts
        paused = call('automation-pause', book, activation, 1, 'pause')
        assert paused['state'] == 'paused' and paused['generation'] == 2
        assert paused['actor']['kind'] == 'programmatic' and paused['actor']['component'] == 'SevraCLI.automation-pause'
        assert call('automation-pause', book, activation, 1, 'pause') == paused
        call('automation-pause', book, activation, 1, 'stale', error='stale_automation')
        call('automation-pause', book, activation, 0, 'invalid', error='automation_generation')
        assert call('automation-occurrences', book, activation)['occurrences'][-1]['detail'] == 'paused'
        assert [row['kind'] for row in call('automation-events', book)['events']] == ['authorized', 'planned', 'paused']
        assert call('verify', book)['ok']
        restored = output / 'Inert.sevra'
        assert call('reconstruct', book, restored)['execution'] == 'inert'
        assert call('automation-activation', restored, activation) == paused
        assert call('automation-occurrences', restored, activation) == call('automation-occurrences', book, activation)
        assert call('automation-events', restored) == call('automation-events', book)
        assert call('workflow-list', restored) == [] and call('workflow-events', restored)['events'] == []
        assert call('verify', restored)['ok']
        result['ok'] = True
    finally:
        (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'ok': result['ok'], 'calls': len(result['calls']), 'output': str(output)}))


if __name__ == '__main__':
    main()
