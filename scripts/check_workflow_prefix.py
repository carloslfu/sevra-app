"""D9 refuses incomplete provenance and preserves same-frontend variation."""
import copy
from pathlib import Path
import tempfile

from check_workflow_performance import results, protocol
from probe_workflow_prefix import audit, report, resource_files

with tempfile.TemporaryDirectory(prefix='sevra-prefix-resources-') as folder:
    binary = Path(folder) / 'frozen-worker'
    binary.touch()
    try:
        resource_files(binary)
        raise AssertionError('An executable without native resources was admitted')
    except ValueError:
        pass
    for name in ['Sevra_SevraSplash.bundle/selected-model.json',
                 'Sevra_SevraSplashText.bundle/template-patch.json',
                 'Sevra_SevraSplashGrammar.bundle/json-slices.json']:
        file = Path(folder) / name
        file.parent.mkdir()
        file.write_text('{}')
    assert len(resource_files(binary)) == 3


def prefix(backend):
    value = copy.deepcopy(next(r for r in results if r['backend'] == backend))
    value['block'] = 9
    value['rows'] = value['rows'][:2]
    for index, row in enumerate(value['rows']):
        row.update(id=['formula_review', 'inventory_evidence'][index], seed=9001 + index,
                   block=9, sequence=index, warmup=True, backend=backend)
    for job in [value['ready']['prime']] + value['rows']:
        for request in job['trace']['requests']:
            request['metrics'] = {'matchedPromptTokens': 0, 'deduplicatedKVTokens': 10}
    return value


original = {backend: prefix(backend) for backend in ['native', 'reference']}
replays = [copy.deepcopy(original[b]) for b in ['reference', 'native', 'native', 'reference']]
good = report(replays, original, protocol)
assert good['allJobsAndConditionsValid'] and good['sameFrontendRepeatsMatch'] and good['newFrontendPairsMatch']
assert not good['performanceQualification'] and not good['productionAdoption']

# Identical serialized requests with different generated tokens remain valid
# diagnostic evidence, but cannot masquerade as within-frontend repeatability.
different = copy.deepcopy(replays)
different[2]['rows'][1]['trace']['requests'][0]['tokens'] = [99]
changed = report(different, original, protocol)
assert changed['allJobsAndConditionsValid'] and not changed['sameFrontendRepeatsMatch']
assert not changed['newFrontendPairsMatch']
assert changed['withinFrontend']['native']['pairs'][-1]['sameRequest']
assert not changed['withinFrontend']['native']['pairs'][-1]['sameTokens']
assert not report(replays, original, protocol, ['controller'])['allJobsAndConditionsValid']
assert not report(replays[:-1], original, protocol)['allJobsAndConditionsValid']
assert not report(list(reversed(replays[:2])) + replays[2:], original, protocol)['allJobsAndConditionsValid']

for mutate in [
    lambda r: r['rows'].pop(),
    lambda r: r['rows'][0].update(seed=1),
    lambda r: r['rows'][0].update(warmup=False),
    lambda r: r['ready']['prime']['errors'].append('invalid prime'),
    lambda r: r['rows'][1]['errors'].append('wrong answer'),
    lambda r: r['rows'][0]['memory'].update(sampleCount=0),
    lambda r: r['rows'][0]['memory'].update(roles=['host']),
    lambda r: r['rows'][0]['memory'].update(maximumThermalState=2),
    lambda r: r['rows'][0]['trace']['requests'][0]['metrics'].pop('deduplicatedKVTokens'),
    lambda r: r['rows'][0]['trace']['requests'][0].update(maskTrace=[{'observed': True}]),
    lambda r: r['rows'][0]['trace']['requests'][0]['metrics'].update(diagnosticRequestCacheIsolation=True),
    lambda r: r.update(closed={'closed': False}),
    lambda r: r.update(returncode=1),
    lambda r: r.update(roles=['host']),
    lambda r: r['before'].update(acPower=False),
]:
    invalid = copy.deepcopy(original['reference'])
    mutate(invalid)
    assert audit(invalid, protocol)

print('PASS D9 requires complete identical-prefix schedules, valid jobs/counters/conditions and shutdown; token variation remains evidence, never qualification')
