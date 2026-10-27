"""Adversarial checks for the complete-workbook performance evidence gate."""
import copy
import json

from compare_workflow_performance import ROOT, process_roles, summarize

protocol = json.loads((ROOT / 'integration/performance/workflow-protocol.json').read_text())


def job(name, seed):
    return {'id': name, 'seed': seed, 'errors': [], 'completeSeconds': 1,
            'startingItems': ['same fixture'], 'validationFailures': 0,
            'trace': {'requests': [{'promptSHA256': 'same', 'promptTokenCount': 42, 'requestSHA256': 'same-parameters',
                                    'generationTokens': 3, 'tokens': [1, 2, 3]}],
                      'responses': [{'calls': ['finish']}]}}


results = []
for block in range(protocol['blocks']):
    order = protocol['workloads']
    order = order[block % len(order):] + order[:block % len(order)]
    for backend in ['native', 'reference']:
        roles = ['host', 'helper'] + (['reference'] if backend == 'reference' else [])
        rows = []
        schedule = [(True, name) for name in order] + [
            (False, name) for _ in range(protocol['repetitionsPerWorkloadPerBlock']) for name in order]
        for sequence, (warmup, name) in enumerate(schedule):
            row = job(name, block * 1000 + sequence + 1)
            row.update(backend=backend, block=block, warmup=warmup, sequence=sequence,
                       memory={'roles': roles, 'errors': [], 'sampleCount': 5,
                               'observedPeakSumBytes': 100, 'maximumThermalState': 0})
            rows.append(row)
        results.append({'block': block, 'backend': backend, 'rows': rows, 'roles': roles,
                        'ready': {'ready': True, 'prime': job('prime', 0)},
                        'closed': {'closed': True}, 'returncode': 0, 'failure': None,
                        'before': {'acPower': True, 'thermalState': 0},
                        'after': {'acPower': True, 'thermalState': 0}})


def passes(rows, pilot=False):
    return summarize(rows, protocol, pilot)['workflowGatePassed']


assert passes(results)
assert not passes(results, True)
assert not passes(results[:-1])
assert not passes(results + results[:1])
for name, change in [
    ('missing warmup', lambda r: r[0]['rows'].pop(0)),
    ('failed warmup', lambda r: r[0]['rows'][0]['errors'].append('wrong answer')),
    ('failed measured job', lambda r: r[0]['rows'][4]['errors'].append('missing chart')),
    ('failed priming', lambda r: r[0]['ready']['prime']['errors'].append('wrong request')),
    ('priming prompt mismatch', lambda r: r[0]['ready']['prime']['trace']['requests'][0].update(promptSHA256='other')),
    ('warmup prompt mismatch', lambda r: r[0]['rows'][0]['trace']['requests'][0].update(promptSHA256='other')),
    ('different generated tokens', lambda r: r[0]['rows'][4]['trace']['requests'][0].update(tokens=[4])),
    ('different wire parameter', lambda r: r[0]['rows'][4]['trace']['requests'][0].update(requestSHA256='other')),
    ('different prefix', lambda r: r[0]['rows'][4]['trace']['requests'][0].update(generationTokens=4)),
    ('different starting fixture', lambda r: r[0]['rows'][4].update(startingItems=['different'])),
    ('missing observed request', lambda r: r[0]['rows'][4]['trace'].update(requests=[])),
    ('missing observed response', lambda r: r[0]['rows'][4]['trace'].update(responses=[])),
    ('oversized prompt', lambda r: r[0]['rows'][4]['trace']['requests'][0].update(promptTokenCount=24001)),
    ('wrong seed', lambda r: r[0]['rows'][4].update(seed=999)),
    ('wrong order', lambda r: r[0]['rows'][4].update(sequence=6)),
    ('missing reference footprint', lambda r: r[1].update(roles=['host', 'helper'])),
    ('incomplete sampling', lambda r: r[1]['rows'][4]['memory'].update(roles=['host', 'helper'])),
    ('zero samples', lambda r: r[0]['rows'][4]['memory'].update(sampleCount=0)),
    ('failed sample', lambda r: r[0]['rows'][4]['memory']['errors'].append('process gone')),
    ('lost power', lambda r: r[0]['after'].update(acPower=False)),
    ('thermal exclusion', lambda r: r[0]['rows'][4]['memory'].update(maximumThermalState=2)),
    ('worker failure', lambda r: r[0].update(failure='crashed')),
    ('failed cleanup', lambda r: r[0].update(closed={'closed': False})),
    ('nonzero exit', lambda r: r[0].update(returncode=1)),
]:
    changed = copy.deepcopy(results)
    change(changed)
    assert not passes(changed), name

# Corrected model errors remain in the timed successful job. Recovery itself is
# allowed, but a >5% median cost cannot be removed from complete job latency.
recovered = copy.deepcopy(results)
for result in recovered:
    for row in result['rows']:
        row['validationFailures'] = 1
assert passes(recovered)
report = summarize(recovered, protocol, False)
assert report['comparisons'][0]['stats']['native']['validationFailures'] == 20
for result in recovered:
    if result['backend'] == 'native':
        for row in result['rows']:
            row['completeSeconds'] = 1.06
assert not passes(recovered)

# A tail-only regression fails independently of the median threshold.
tail = copy.deepcopy(results)
for result in tail:
    if result['backend'] == 'native' and result['block'] == 0:
        for row in result['rows']:
            row['completeSeconds'] = 1.11
assert not passes(tail)

tree = [{'pid': 1, 'command': '/test/sevra-workflow-performance'},
        {'pid': 2, 'command': '/test/Python'}, {'pid': 3, 'command': '/test/splash'}]
assert process_roles(tree, 1, 'reference') == ['host', 'reference', 'helper']
try:
    process_roles(tree[:2], 1, 'reference')
    raise AssertionError('Missing helper was accepted')
except RuntimeError:
    pass
print('PASS complete-workbook gate rejects missing, divergent, failed, unsampled, overheated and slower evidence')
