"""Inspect initial/later cache reuse without mistaking counts for byte identity."""
import argparse
import hashlib
import json
from pathlib import Path

from compare_splash_performance import digest, sha


def longest_prefix(tokens, earlier):
    return max((next((i for i, (a, b) in enumerate(zip(tokens, previous)) if a != b),
                     min(len(tokens), len(previous))) for previous in earlier), default=0)


def inspect(folder, backend):
    result = json.loads((folder / f'0-{backend}.json').read_text())
    if result['failure'] or result['closed'] != {'closed': True} or result['returncode'] != 0:
        raise ValueError('Incomplete worker; do not infer full preceding cache history')
    earlier, rows = [], []
    for job in [result['ready']['prime']] + result['rows']:
        for step, request in enumerate(job['trace']['requests'], 1):
            prompt = json.loads((folder / (request['promptSHA256'] + '.prompt.json')).read_text())
            if digest(prompt) != request['promptSHA256']:
                raise ValueError('Changed prompt array')
            matched = request['metrics'].get('matchedPromptTokens')
            reused = request['metrics'].get('deduplicatedKVTokens')
            if any(not isinstance(n, int) or isinstance(n, bool) or n < 0 for n in [matched, reused]):
                raise ValueError('Missing or invalid cache counters')
            tokens = prompt + request['tokens']
            prefix = longest_prefix(tokens, earlier)
            rows.append({'job': job['id'], 'seed': job['seed'], 'step': step,
                         'requestSHA256': request['requestSHA256'], 'promptTokens': len(prompt),
                         'initialMatchedTokens': matched, 'laterDeduplicatedTokens': reused,
                         'longestPriorPrefix': prefix, 'priorRequestCount': len(earlier),
                         'priorReuseCannotReachGeneration': prefix < len(prompt)})
            earlier.append(tokens)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    sides = {backend: inspect(args.run, backend) for backend in ['native', 'reference']}
    paired = []
    right = {(r['job'], r['seed'], r['step']): r for r in sides['reference']}
    for left in sides['native']:
        identity = (left['job'], left['seed'], left['step'])
        if identity not in right:
            continue
        other = right[identity]
        paired.append({'job': left['job'], 'seed': left['seed'], 'step': left['step'],
                       'sameRequest': left['requestSHA256'] == other['requestSHA256'],
                       'sameInitialCount': left['initialMatchedTokens'] == other['initialMatchedTokens'],
                       'sameLaterCount': left['laterDeduplicatedTokens'] == other['laterDeduplicatedTokens']})
    report = {'scope': 'Count and prior-prefix diagnostic only; not cached-byte identity or qualification',
              'sourceSHA256': sha(__file__),
              'inputSHA256': {name: sha(args.run / name) for name in ['identity.json', '0-native.json', '0-reference.json']},
              'sides': sides, 'pairedPositions': paired,
              'assumptions': 'Fresh sequential workers, all requests captured and persistent cache disabled. Inspect identity/configuration receipts before relying on the prior-prefix bound.',
              'limits': 'Counts do not identify cached bytes, state capture boundaries or a cause. Unpaired positions remain in sides, never silently qualify as matched.',
              'performanceQualification': False, 'productionAdoption': False}
    with args.output.open('x') as output:
        json.dump(report, output, indent=2)
        output.write('\n')
    print(json.dumps({'pairedPositions': len(paired),
                      'sameWireDifferentLaterReuse': sum(r['sameRequest'] and not r['sameLaterCount'] for r in paired)}))


if __name__ == '__main__':
    main()
