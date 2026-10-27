"""Fail-closed checks for native replay and observed-mask diagnostic reports."""
import copy

from analyze_workflow_masks import compare_request, mask_index, token_hash
from compare_workflow_performance import summarize
from check_workflow_performance import results, protocol
from check_workflow_repeatability import compare as compare_replay
from probe_workflow_observation import compare as compare_observation
from splash_performance_reference import diagnostic_settings
from analyze_workflow_cache import longest_prefix

# Reuse can extend into generated tokens when an earlier complete sequence
# matches. Looking only at earlier prompt lengths would miss that distinction.
assert longest_prefix([1, 2, 3, 4], [[1, 2, 3, 4, 5]]) == 4
assert longest_prefix([1, 2, 3, 4], [[1, 2, 9], [1, 8, 3]]) == 2
assert longest_prefix([1, 2], []) == 0

# Even a complete otherwise passing cohort cannot qualify with tracing enabled.
report = summarize(results, protocol, False, diagnostic_masks=True)
assert not report['workflowGatePassed'] and not report['timingsEligibleForQualification']
forgotten_flag = copy.deepcopy(results)
forgotten_flag[0]['rows'][0]['trace']['requests'][0]['maskTrace'] = [{'observed': True}]
report = summarize(forgotten_flag, protocol, False)
assert report['diagnosticMasks'] and not report['workflowGatePassed']
forgotten_mode = copy.deepcopy(results)
forgotten_mode[0]['diagnosticObservation'] = 'delay-2ms'
report = summarize(forgotten_mode, protocol, False)
assert report['diagnosticObservation'] and not report['workflowGatePassed']
assert not report['timingsEligibleForQualification']

assert diagnostic_settings({}) == ('hash', 0)
assert diagnostic_settings({'diagnosticMasks': True, 'diagnosticMaskMode': 'delay',
                            'diagnosticMaskDelaySeconds': .002}) == ('delay', .002)
for config in [
    {'diagnosticMaskMode': 'unknown'},
    {'diagnosticMaskDelaySeconds': -.001},
    {'diagnosticMaskDelaySeconds': float('nan')},
    {'diagnosticMaskDelaySeconds': float('inf')},
    {'diagnosticMaskDelaySeconds': True},
    {'diagnosticMaskDelaySeconds': .02},
    {'diagnosticMaskDelaySeconds': .002},
    {'diagnosticMaskMode': 'delay', 'diagnosticMaskDelaySeconds': .002},
    {'diagnosticMasks': True, 'diagnosticMaskMode': 'delay', 'diagnosticMaskDelaySeconds': 0},
]:
    try:
        diagnostic_settings(config)
        raise AssertionError('Invalid observation mode was accepted')
    except ValueError:
        pass

pilot = copy.deepcopy(results[0])
pilot['rows'] = pilot['rows'][:8]
for job in [pilot['ready']['prime']] + pilot['rows']:
    for req in job['trace']['requests']:
        req['metrics'] = {'matchedPromptTokens': 0}
assert compare_replay(pilot, pilot, protocol)['exactNativeReplay']
assert compare_observation(pilot, pilot)['sameTokens']
different = copy.deepcopy(pilot)
different['rows'][0]['trace']['requests'][0]['tokens'] = [99]
assert not compare_observation(pilot, different)['sameTokens']
assert compare_observation(pilot, different)['sameRequests']
different['rows'][0]['seed'] = 999
try:
    compare_observation(pilot, different)
    raise AssertionError('Different observer job schedules were compared')
except ValueError:
    pass
for mutate in [
    lambda r: r['rows'].pop(),
    lambda r: r['rows'][0].update(seed=999),
    lambda r: r['rows'][0]['trace']['requests'][0].update(tokens=[99]),
    lambda r: r['rows'][0]['trace']['requests'][0].update(requestSHA256='different'),
    lambda r: r['rows'][0]['trace']['requests'][0].update(generationTokens=99),
    lambda r: r['rows'][0]['errors'].append('invalid answer'),
    lambda r: r['ready']['prime']['errors'].append('invalid prime'),
    lambda r: r['rows'][0]['memory'].update(sampleCount=0),
    lambda r: r['rows'][0]['memory'].update(maximumThermalState=2),
    lambda r: r.update(closed={'closed': False}),
    lambda r: r.update(returncode=1),
    lambda r: r['before'].update(acPower=False),
]:
    changed = copy.deepcopy(pilot)
    mutate(changed)
    assert not compare_replay(pilot, changed, protocol)['exactNativeReplay']

reference_pilot = copy.deepcopy(pilot)
reference_pilot['backend'] = 'reference'
for job in reference_pilot['rows']:
    job['memory']['roles'] = ['host', 'reference', 'helper']
assert compare_replay(reference_pilot, reference_pilot, protocol)['exactReplay']
incomplete = copy.deepcopy(reference_pilot)
incomplete['rows'][0]['memory']['roles'] = ['host', 'helper']
assert not compare_replay(reference_pilot, incomplete, protocol)['exactReplay']


def row(committed, simulation, tokens, mask='a' * 64):
    prefix = tokens[:committed] + simulation
    return {'committedCount': committed, 'simulationTokens': simulation,
            'tokenCount': len(prefix), 'prefixSHA256': token_hash(prefix), 'maskSHA256': mask}


def request(tokens):
    return {'tokens': tokens, 'maskTrace': [row(i, [], tokens) for i in range(len(tokens) + 1)],
            'requestSHA256': 'frame', 'grammarSHA256': 'grammar',
            'metrics': {'matchedPromptTokens': 0}}


a, b = request([1, 2, 3]), request([1, 2, 4])
r = compare_request(a, b)
assert r['firstDifferentToken'] == 2 and r['divergenceMaskMatches']
assert not r['missingGeneratedPrefixOffsets'] and not r['differentGeneratedPrefixOffsets']
assert not compare_request(a, a)['divergenceMaskMatches']  # No divergence is not a proof at divergence.

terminal = request([1, 2, 3])
terminal['maskTrace'].pop()  # No mask is required after an already complete output.
assert not compare_request(terminal, terminal)['missingGeneratedPrefixOffsets']

b['maskTrace'][2]['maskSHA256'] = 'b' * 64
r = compare_request(a, b)
assert r['differentGeneratedPrefixOffsets'] == [2] and not r['divergenceMaskMatches']
assert r['divergenceMaskObservedBoth'] and len(r['differentMasks']) == 1

b['maskTrace'].pop(2)
r = compare_request(a, b)
assert not r['divergenceMaskObservedBoth'] and r['missingGeneratedPrefixOffsets'] == [2]

# A conflicting observation is retained even when another observation matches.
b = request([1, 2, 4])
b['maskTrace'].append(row(2, [], b['tokens'], 'b' * 64))
r = compare_request(a, b)
assert len(r['inconsistentPrefixes']['reference']) == 1 and not r['divergenceMaskMatches']

# Hypothetical speculative prefixes are compared independently of actual output.
a['maskTrace'].append(row(1, [99, 100], a['tokens']))
b = copy.deepcopy(a)
b['maskTrace'][-1]['maskSHA256'] = 'b' * 64
r = compare_request(a, b)
assert len(r['differentMasks']) == 1 and not r['differentGeneratedPrefixOffsets']
assert r['sameGeneratedTokens']

for mutate in [
    lambda r: r['maskTrace'].clear(),
    lambda r: r['maskTrace'][0].update(prefixSHA256='wrong'),
    lambda r: r['maskTrace'][0].update(committedCount=1000),
    lambda r: r['maskTrace'][0].update(committedCount=True),
    lambda r: r['maskTrace'][0].update(simulationTokens=[2**32]),
    lambda r: r['maskTrace'][0].update(tokenCount=999),
    lambda r: r['maskTrace'][0].update(maskSHA256='wrong'),
    lambda r: r['maskTrace'].append({'error': 'Unexpected diagnostic dimensions'}),
]:
    bad = copy.deepcopy(a)
    mutate(bad)
    assert mask_index(bad)[1]

print('PASS diagnostic masks retain mismatches, missing evidence and conflicting observations; tracing cannot qualify performance')
