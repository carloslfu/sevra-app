"""Compare observed grammar masks at shared prefixes of matched W1 requests.

Diagnostic only. Hashes cover every UInt32 little-endian mask word, including
padding. Keep multiple observations of the same prefix; never select a match
and discard a disagreement. Timing from instrumented runs cannot qualify W1.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct


def token_hash(tokens):
    return hashlib.sha256(struct.pack('<' + 'I' * len(tokens), *tokens)).hexdigest()


def mask_index(request):
    rows = request.get('maskTrace') or []
    problems, masks = [], {}
    if not rows:
        problems.append('Missing mask trace')
    for row in rows:
        if 'error' in row:
            problems.append(row['error'])
            continue
        committed = row.get('committedCount')
        simulation = row.get('simulationTokens')
        if (not isinstance(committed, int) or isinstance(committed, bool)
                or not 0 <= committed <= len(request['tokens']) or not isinstance(simulation, list)
                or any(not isinstance(t, int) or isinstance(t, bool) or not 0 <= t < 2**32 for t in simulation)):
            problems.append('Invalid recorded prefix dimensions')
            continue
        prefix = request['tokens'][:committed] + simulation
        if row.get('tokenCount') != len(prefix) or row.get('prefixSHA256') != token_hash(prefix):
            problems.append('Recorded prefix hash does not match committed and simulated tokens')
            continue
        mask = row.get('maskSHA256', '')
        if len(mask) != 64 or any(c not in '0123456789abcdef' for c in mask):
            problems.append('Invalid mask hash')
            continue
        masks.setdefault((len(prefix), row['prefixSHA256']), set()).add(mask)
    inconsistent = [{'tokenCount': count, 'prefixSHA256': checksum, 'maskHashes': sorted(values)}
                    for (count, checksum), values in masks.items() if len(values) != 1]
    return masks, sorted(set(problems)), inconsistent


def compare_request(left, right):
    a, b = left['tokens'], right['tokens']
    same_tokens = a == b
    first = next((i for i, (u, v) in enumerate(zip(a, b)) if u != v), min(len(a), len(b)))
    x, xp, xi = mask_index(left)
    y, yp, yi = mask_index(right)
    shared = x.keys() & y.keys()
    different = [{'tokenCount': k[0], 'prefixSHA256': k[1],
                  'nativeMasks': sorted(x[k]), 'referenceMasks': sorted(y[k])}
                 for k in sorted(shared) if x[k] != y[k]]
    generated_prefixes, missing, mismatched = [], [], []
    # A complete equal output needs no next-token mask after its terminal token.
    # A divergent output still needs observation at the first different position.
    for offset in range(first if same_tokens else first + 1):
        key = (offset, token_hash(a[:offset]))
        if key not in x or key not in y:
            missing.append(offset)
        elif x[key] != y[key] or len(x[key]) != 1 or len(y[key]) != 1:
            mismatched.append(offset)
        else:
            generated_prefixes.append(offset)
    key = (first, token_hash(a[:first]))
    return {
        'sameRequest': left['requestSHA256'] == right['requestSHA256'],
        'sameGrammarText': left.get('grammarSHA256') == right.get('grammarSHA256'),
        'sameGeneratedTokens': same_tokens,
        'firstDifferentToken': None if same_tokens else first,
        'nativeTokens': len(a), 'referenceTokens': len(b),
        'nativeMatchedPrefix': left['metrics']['matchedPromptTokens'],
        'referenceMatchedPrefix': right['metrics']['matchedPromptTokens'],
        'nativeMaskRows': len(left.get('maskTrace') or []),
        'referenceMaskRows': len(right.get('maskTrace') or []),
        'problems': {'native': xp, 'reference': yp},
        'inconsistentPrefixes': {'native': xi, 'reference': yi},
        'sharedPrefixes': len(shared), 'differentMasks': different,
        'sharedGeneratedPrefixMaskMatches': len(generated_prefixes),
        'missingGeneratedPrefixOffsets': missing,
        'differentGeneratedPrefixOffsets': mismatched,
        'divergenceMaskObservedBoth': not same_tokens and key in x and key in y,
        'divergenceMaskMatches': not same_tokens and key in x and key in y and x[key] == y[key]
                                 and len(x[key]) == 1,
    }


def analyze(folder):
    config = json.loads((folder / 'config.json').read_text())
    if not config.get('diagnosticMasks'):
        raise ValueError('This run did not record diagnostic masks')
    sides = [json.loads((folder / f'0-{backend}.json').read_text()) for backend in ['native', 'reference']]
    problems, pairs = [], []
    jobs = []
    for backend, result in zip(['native', 'reference'], sides):
        if result['failure'] or result['returncode'] != 0 or result['closed'] != {'closed': True}:
            problems.append(backend + ': worker or cleanup failure')
        rows = [result['ready']['prime']] + result['rows']
        for row in rows:
            if row.get('errors'):
                problems.append(backend + ': failed job ' + row['id'])
            for request in row['trace']['requests']:
                checksum = request.get('grammarSHA256')
                if not checksum:
                    raise ValueError('Missing actual grammar')
                grammar = json.loads((folder / (checksum + '.grammar.json')).read_text())
                if hashlib.sha256(grammar.encode()).hexdigest() != checksum:
                    raise ValueError('Changed actual grammar')
        jobs.append(rows)
    if len(jobs[0]) != 9 or len(jobs[1]) != 9:
        problems.append('Incomplete pilot schedule')
    for left, right in zip(*jobs):
        if left['id'] != right['id'] or left['seed'] != right['seed']:
            problems.append('Unpaired job identity')
            continue
        x, y = left['trace']['requests'], right['trace']['requests']
        if len(x) != len(y):
            problems.append(left['id'] + ': differing request count')
        for i, (a, b) in enumerate(zip(x, y)):
            report = compare_request(a, b)
            report.update(job=left['id'], seed=left['seed'], step=i + 1)
            pairs.append(report)
    matched = [p for p in pairs if p['sameRequest']]
    divergent = [p for p in matched if not p['sameGeneratedTokens']]
    return {
        'scope': 'Observed-mask diagnostic only; no performance or adoption qualification',
        'problems': problems, 'pairedRequestPositions': len(pairs),
        'sameWireRequests': len(matched), 'sameWireDifferentTokens': len(divergent),
        'divergentWithSameObservedMask': sum(p['divergenceMaskMatches'] for p in divergent),
        'divergentWithDifferentObservedMask': sum(p['divergenceMaskObservedBoth'] and not p['divergenceMaskMatches'] for p in divergent),
        'divergentWithoutMaskEvidence': sum(not p['divergenceMaskObservedBoth'] for p in divergent),
        'pairs': pairs, 'performanceQualification': False, 'productionAdoption': False,
        'limits': 'Comparison covers observed shared prefixes, including hypothetical speculative prefixes. Missing rows are gaps, not matches. Equal masks at a divergent token do not establish the cause of generation differences or exclude differences at unshared speculative prefixes, other commands, timing or cache state.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = analyze(args.run)
    report['analysisSourceSHA256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    report['inputSHA256'] = {name: hashlib.sha256((args.run / name).read_bytes()).hexdigest()
                            for name in ['identity.json', 'config.json', '0-native.json', '0-reference.json']}
    with args.output.open('x') as output:
        json.dump(report, output, indent=2)
        output.write('\n')
    print(json.dumps({k: v for k, v in report.items() if k != 'pairs'}))


if __name__ == '__main__':
    main()
