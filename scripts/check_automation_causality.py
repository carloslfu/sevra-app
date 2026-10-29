#!/usr/bin/env python3
"""Inspect retained origins and race nine trusted synthetic successor writers."""
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
    parser.add_argument('--checks', type=Path, default=ROOT / '.build/debug/sevra-checks')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    cli, checks = args.cli.resolve(strict=True), args.checks.resolve(strict=True)
    output = args.output or Path(tempfile.mkdtemp(prefix='sevra-automation-causality-'))
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    evidence = {
        'ok': False, 'cliSHA256': hashlib.sha256(cli.read_bytes()).hexdigest(),
        'checksSHA256': hashlib.sha256(checks.read_bytes()).hexdigest(), 'calls': [], 'workers': [],
        'limits': ['Synthetic trusted inherited admissions share the real captured dispatch transaction.',
                   'Nine independent processes contend for eight direct-successor slots.',
                   'Production calendar origins and installed inspection are qualified separately.',
                   'No condition business-cause discovery, automatic condition dispatch, inference or release claim.'],
    }

    def save():
        (output / 'result.json').write_text(json.dumps(evidence, indent=2) + '\n')

    def call(*arguments, error=None):
        p = subprocess.run([str(cli), *map(str, arguments)], capture_output=True, text=True, timeout=90)
        saved = {'arguments': list(map(str, arguments)), 'returncode': p.returncode,
                 'stdout': p.stdout, 'stderr': p.stderr}
        evidence['calls'].append(saved)
        save()
        if error:
            assert p.returncode != 0 and json.loads(p.stderr)['error']['code'] == error, saved
            return
        assert p.returncode == 0, saved
        return json.loads(p.stdout)['result']

    try:
        book = output / 'Concurrent.sevra'
        p = subprocess.run([str(checks), '--automation-causality-fixture', str(book)],
                           capture_output=True, text=True, timeout=90)
        evidence['fixture'] = {'returncode': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr}
        assert p.returncode == 0, evidence['fixture']
        fixture = json.loads(p.stdout)
        run = fixture['runID']
        initial = call('automation-causality', book, run)
        assert initial == fixture['origin'] and initial['rootCharges'][0]['admittedRuns'] == 1
        assert initial['enabled'] is False and initial['dispatchEligibility'] == 'not-evaluated'
        before = call('commits', book)
        for invalid, code in [('', 'causal_input'), ('x' * 257, 'causal_input'), ('missing', 'causal_origin')]:
            call('automation-causality', book, invalid, error=code)
        call('automation-causality', book, run, 'unexpected', error='usage')
        assert call('commits', book) == before
        workers = []
        try:
            for definition in fixture['children']:
                workers.append((definition, subprocess.Popen(
                    [str(checks), '--automation-causality-worker', str(book), definition, run],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)))
            for definition, worker in workers:
                stdout, stderr = worker.communicate(timeout=90)
                evidence['workers'].append({'definitionID': definition, 'returncode': worker.returncode,
                                            'stdout': stdout, 'stderr': stderr})
                save()
        finally:
            for _, worker in workers:
                if worker.poll() is None:
                    worker.kill()
                    worker.communicate(timeout=20)
        successes = [item for item in evidence['workers'] if item['returncode'] == 0]
        failures = [item for item in evidence['workers'] if item['returncode'] != 0]
        assert len(successes) == 8 and len(failures) == 1, evidence['workers']
        assert json.loads(failures[0]['stderr'])['code'] == 'causal_fanout', failures
        trace = call('automation-causality', book, run)
        assert trace['directSuccessors'] == 8 and trace['rootCharges'][0]['admittedRuns'] == 9
        for item in successes:
            child = json.loads(item['stdout'])['runID']
            origin = call('automation-causality', book, child)
            assert origin['origin']['parents'] == [run] and origin['origin']['depth'] == 2
            assert origin['origin']['roots'] == trace['origin']['roots']
        assert len(call('workflow-list', book)) == 9
        assert call('verify', book)['ok']
        restored = output / 'Inert.sevra'
        assert call('reconstruct', book, restored)['execution'] == 'inert'
        assert call('automation-causality', restored, run) == trace
        assert call('verify', restored)['ok']
        evidence['ok'] = True
    finally:
        save()
    print(json.dumps({'ok': evidence['ok'], 'calls': len(evidence['calls']),
                      'writers': len(evidence['workers']), 'output': str(output)}))


if __name__ == '__main__':
    main()
