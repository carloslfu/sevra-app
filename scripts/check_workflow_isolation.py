"""Adversarial checks for the preregistered fresh-worker pilot's evidence gate."""
import copy
import json

from check_workflow_performance import results as fixtures
from compare_workflow_performance import ROOT
from probe_workflow_isolation import summarize

protocol = json.loads((ROOT / 'integration/performance/workflow-isolation-pilot.json').read_text())
results = []
for name in protocol['workloads']:
    for prototype in fixtures[:2]:
        result = copy.deepcopy(prototype)
        result['workload'] = name
        result['rows'] = result['rows'][:2]
        for sequence, row in enumerate(result['rows']):
            row.update(id=name, seed=sequence + 1, sequence=sequence, warmup=sequence == 0)
        for job in [result['ready']['prime']] + result['rows']:
            for request in job['trace']['requests']:
                request['metrics'] = {'matchedPromptTokens': 0, 'deduplicatedKVTokens': 0}
        results.append(result)


def passes(rows):
    return summarize(rows, protocol)['isolationPilotPassed']


report = summarize(results, protocol)
assert passes(results) and not report['performanceQualification'] and not report['productionAdoption']
assert not summarize(results, protocol, ['changed-source.py'])['isolationPilotPassed']
assert not passes(results[:-1]) and not passes(results + results[:1])
for name, change in [
    ('missing prime', lambda r: r[0]['ready'].update(prime={})),
    ('invalid prime', lambda r: r[0]['ready']['prime']['errors'].append('wrong answer')),
    ('missing warmup', lambda r: r[0]['rows'].pop(0)),
    ('wrong workload', lambda r: r[0]['rows'][0].update(id='other')),
    ('wrong seed', lambda r: r[0]['rows'][1].update(seed=999)),
    ('wrong order', lambda r: r[0]['rows'][0].update(sequence=1)),
    ('mislabeled warmup', lambda r: r[0]['rows'][0].update(warmup=False)),
    ('failed job', lambda r: r[0]['rows'][1]['errors'].append('wrong formula')),
    ('nonfinite latency', lambda r: r[0]['rows'][1].update(completeSeconds=float('inf'))),
    ('nonfinite prime', lambda r: r[0]['ready']['prime'].update(completeSeconds=float('inf'))),
    ('partial failed worker', lambda r: r[0]['rows'][1].update(trace={}, errors=['crash'])),
    ('different starting workbook', lambda r: r[0]['rows'][1].update(startingItems=['other'])),
    ('different request', lambda r: r[0]['rows'][0]['trace']['requests'][0].update(requestSHA256='other')),
    ('different prompt', lambda r: r[0]['rows'][0]['trace']['requests'][0].update(promptSHA256='other')),
    ('different generated tokens', lambda r: r[0]['rows'][1]['trace']['requests'][0].update(tokens=[4])),
    ('missing initial cache count', lambda r: r[0]['rows'][0]['trace']['requests'][0]['metrics'].pop('matchedPromptTokens')),
    ('missing later reuse count', lambda r: r[0]['rows'][0]['trace']['requests'][0]['metrics'].pop('deduplicatedKVTokens')),
    ('different initial cache count', lambda r: r[0]['rows'][0]['trace']['requests'][0]['metrics'].update(matchedPromptTokens=32)),
    ('different later reuse count', lambda r: r[0]['rows'][0]['trace']['requests'][0]['metrics'].update(deduplicatedKVTokens=32)),
    ('boolean count', lambda r: r[0]['rows'][0]['trace']['requests'][0]['metrics'].update(deduplicatedKVTokens=False)),
    ('mask trace', lambda r: r[0]['rows'][0]['trace']['requests'][0].update(maskTrace=[{'observed': True}])),
    ('delay intervention', lambda r: r[0].update(diagnosticObservation='delay-2ms')),
    ('missing process', lambda r: r[1].update(roles=['host', 'helper'])),
    ('missing process sample', lambda r: r[1]['rows'][0]['memory'].update(roles=['host', 'helper'])),
    ('missing samples', lambda r: r[0]['rows'][0]['memory'].update(sampleCount=0)),
    ('missing sample errors', lambda r: r[0]['rows'][0]['memory'].pop('errors')),
    ('missing footprint', lambda r: r[0]['rows'][0]['memory'].pop('observedPeakSumBytes')),
    ('sample error', lambda r: r[0]['rows'][0]['memory']['errors'].append('process gone')),
    ('lost AC', lambda r: r[0]['after'].update(acPower=False)),
    ('missing environment', lambda r: r[0].pop('after')),
    ('thermal boundary', lambda r: r[0]['after'].update(thermalState=2)),
    ('thermal sample', lambda r: r[0]['rows'][0]['memory'].update(maximumThermalState=2)),
    ('worker failure', lambda r: r[0].update(failure='crash')),
    ('cleanup failure', lambda r: r[0].update(closed={'closed': False})),
    ('nonzero exit', lambda r: r[0].update(returncode=1)),
]:
    changed = copy.deepcopy(results)
    change(changed)
    assert not passes(changed), name

print('PASS isolation pilot requires complete valid jobs, exact requests/tokens/cache counts, full sampling and unchanged sources; never qualifies performance')
