#!/usr/bin/env python3
"""Check the installed inert condition-preview contract, including bounded file I/O."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


def run(cli: Path, output: Path) -> dict:
    calls = []

    def call(arguments, error=None):
        result = subprocess.run(
            [str(cli), 'condition-preview', *arguments],
            capture_output=True, text=True, timeout=10,
        )
        calls.append({
            'arguments': arguments, 'returncode': result.returncode,
            'stdout': result.stdout, 'stderr': result.stderr,
        })
        if error is not None:
            assert result.returncode != 0 and not result.stdout, result
            payload = json.loads(result.stderr)
            assert payload['ok'] is False, payload
            if error != '*':
                assert payload['error']['code'] == error, payload
            return payload
        assert result.returncode == 0 and not result.stderr, result
        payload = json.loads(result.stdout)
        assert payload['ok'] is True, payload
        value = payload['result']
        assert value['businessEvidence'] is False and value['enabled'] is False, value
        assert value['execution'] == 'inert' and value['scope'] == 'fixture-observations', value
        return value

    def encoded(value):
        return json.dumps(value, ensure_ascii=False, separators=(',', ':'))

    rule = {'policy': 'native-condition-v1', 'scope': 'stock:bolts', 'operator': '<', 'threshold': '10'}
    values = [{'id': str(i), 'value': value} for i, value in enumerate(['20', '5', '4', '20', '5'])]
    text = encoded(rule)
    observed = encoded(values)
    first = call([text, observed])
    assert first['transitionCount'] == 2 and first['uniqueCount'] == 5
    assert call([text, observed]) == first
    equivalent = {**rule, 'threshold': '+0010.000'}
    assert call([encoded(equivalent), observed]) == first
    call([], 'usage')
    call([text], 'usage')
    call([text, observed, '--enable'], 'usage')
    call(['{', observed], '*')
    call([encoded({**rule, 'extra': True}), observed], 'condition')
    call([encoded({**rule, 'threshold': 10}), observed], 'condition')
    call([encoded({**rule, 'operator': '<; run'}), observed], 'condition')
    call([text, encoded([{'id': 'a', 'value': 5}])], 'condition')
    call([text, encoded([{'id': 'a', 'value': None}])], 'condition')
    call([text, encoded([{'id': 'a', 'value': '1e3'}])], 'number')
    call([text, encoded([{'id': 'a', 'value': '1' * 39}])], 'precision')
    call([text, encoded([{'id': 'a', 'value': '20'}, {'id': 'a', 'value': '5'}])], 'condition_identity')
    many = [{'id': str(i), 'value': '5'} for i in range(101)]
    call([text, encoded(many)], 'condition_limit')
    call([' ' * 65537, observed], 'condition_limit')
    duplicate = [values[0], values[1], values[3], values[1], values[4]]
    assert call([text, encoded(duplicate)])['transitionCount'] == 2
    unknown = {'id': 'unknown', 'value': None, 'reason': 'Incomplete extraction.'}
    across_gap = call([text, encoded([values[0], unknown, values[1]])])
    assert across_gap['transitions'][0]['coverageGap'] is True
    assert call([text, encoded([values[1], unknown, values[4]])])['transitionCount'] == 0
    assert call([text, '[]'])['lastCertainTruth'] is None
    with tempfile.TemporaryDirectory(prefix='sevra-condition-cli-') as temporary:
        folder = Path(temporary)
        rule_file, input_file = folder / 'rule.json', folder / 'observations.json'
        rule_file.write_text(text)
        input_file.write_text(observed)
        assert call(['@' + str(rule_file), '@' + str(input_file)]) == first
        link = folder / 'linked.json'
        link.symlink_to(rule_file)
        call(['@' + str(link), observed], 'condition_file')
        pipe = folder / 'pending.json'
        os.mkfifo(pipe)
        call(['@' + str(pipe), observed], 'condition_file')
        call(['@' + str(folder), observed], 'condition_file')
        call(['@' + str(folder / 'missing.json'), observed], 'condition_file')
        call(['@', observed], 'condition')
        invalid = folder / 'invalid.json'
        invalid.write_bytes(b'\xff\xfe')
        call(['@' + str(invalid), observed], 'condition')
        oversized = folder / 'large.json'
        oversized.write_bytes(b' ' * 65537)
        call([text, '@' + str(oversized)], 'condition_limit')
        large = [{'id': str(i) + 'x' * 200, 'value': None, 'reason': 'r' * 512} for i in range(100)]
        call([text, encoded(large)], 'condition_limit')
        # Both individual file inputs and aggregate decoded observation bytes are bounded.
        many_unicode = [{'id': 'unicode', 'value': None, 'reason': '\U0001f340' * 129}]
        call([text, encoded(many_unicode)], 'condition_limit')
        raw = json.dumps(calls).replace(str(folder), '<temporary>')
        calls = json.loads(raw)
    result = {
        'ok': True, 'cliSHA256': hashlib.sha256(cli.read_bytes()).hexdigest(),
        'callCount': len(calls), 'calls': calls,
        'limits': [
            'Supplied fixture observations only; no workbook, semantic event feed, persisted cursor or workflow execution.',
            'No actual model, visible native UI, OS lifecycle, hardware throughput or release proof.',
        ],
    }
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return {'ok': True, 'callCount': len(calls), 'output': str(output)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.output is not None:
        args.output.mkdir(parents=True, exist_ok=False)
        print(json.dumps(run(args.cli.resolve(), args.output)))
    else:
        with tempfile.TemporaryDirectory(prefix='sevra-condition-result-') as destination:
            print(json.dumps(run(args.cli.resolve(), Path(destination))))
