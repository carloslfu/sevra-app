"""Check that incomplete or invalid benchmark evidence cannot pass its gate."""
import copy
import json
from pathlib import Path

from compare_splash_performance import summarize
from splash_performance_reference import workbook_grammar

ROOT = Path(__file__).resolve().parents[1]
protocol = json.loads((ROOT / 'integration/performance/protocol.json').read_text())
config = {'cases': [{'id': 'fixture'}]}
results = []
for block in range(protocol['blocks']):
    for backend in ['native', 'reference']:
        rows = []
        for warmup in [True, False, False]:
            rows.append({'backend': backend, 'block': block, 'warmup': warmup, 'case': 0,
                'completeSeconds': 1, 'promptSHA256': 'identical', 'generationTokens': 3,
                'tokens': [1, 2, 3], 'errors': [], 'memory': {'observedPeakSumBytes': 12,
                    'maximumThermalState': 0, 'errors': [], 'sampleCount': 5}})
        results.append({'block': block, 'rows': rows, 'failure': None,
            'before': {'acPower': True, 'thermalState': 0},
            'after': {'acPower': True, 'thermalState': 0}})


def passes(value, pilot=False):
    return summarize(value, config, protocol, pilot)['requestGatePassed']


assert passes(results)
assert not passes(results, pilot=True)
assert not passes(results[:-1])
for label, change in [
    ('warmup failure', lambda r: r[0]['rows'][0]['errors'].append('wrong answer')),
    ('measured failure', lambda r: r[0]['rows'][1]['errors'].append('wrong answer')),
    ('prompt mismatch', lambda r: r[0]['rows'][1].update(promptSHA256='different')),
    ('generation prefix mismatch', lambda r: r[0]['rows'][1].update(generationTokens=4)),
    ('worker failure', lambda r: r[0].update(failure='crashed')),
    ('lost AC', lambda r: r[0]['after'].update(acPower=False)),
    ('thermal pressure', lambda r: r[0]['rows'][1]['memory'].update(maximumThermalState=2)),
    ('sample failure', lambda r: r[0]['rows'][1]['memory']['errors'].append('sample failed')),
    ('no samples', lambda r: r[0]['rows'][1]['memory'].update(sampleCount=0)),
]:
    mutated = copy.deepcopy(results)
    change(mutated)
    assert not passes(mutated), label

# A latency regression fails even when all generated outputs match.
slower = copy.deepcopy(results)
for result in slower:
    if result['rows'][0]['backend'] == 'native':
        for row in result['rows']:
            row['completeSeconds'] = 1.06
assert not passes(slower)

# Valid semantic output may tokenize differently, but the difference is retained.
different_tokens = copy.deepcopy(results)
different_tokens[0]['rows'][1]['tokens'] = [5, 6, 7]
report = summarize(different_tokens, config, protocol, False)
assert report['requestGatePassed']
assert not report['comparisons'][0]['identicalGeneratedTokens']

# Tool grammars wrap Lark text in JSON. Normalization must reach nested schemas
# without reordering the request that was rendered into the model prompt.
schema = {'type':'object','properties':{'formula':{'type':'string'},'id':{'type':'string'}},'required':['id']}
wrapped = json.dumps({'grammars':[{'name':'test','lark_grammar':'value: (%json '+json.dumps(schema)+') END\n'}]})
normalized = json.loads(workbook_grammar(wrapped))['grammars'][0]['lark_grammar']
parsed, _ = json.JSONDecoder().raw_decode(normalized.split('%json ',1)[1])
assert list(parsed['properties']) == ['id','formula']
assert normalized.endswith(') END\n')
print('PASS: performance gate rejects pilot, incomplete, mismatched, failed, overheated and slower evidence')
