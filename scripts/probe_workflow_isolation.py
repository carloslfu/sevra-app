"""I1: run each unchanged workbook workload in its own fresh frontend/helper.

Preregistered diagnostic pilot only. This does not replace W1, qualify latency,
or modify the product's caching policy. Source/build identities stay frozen for
the entire run; edits to measured code stop subsequent workers.
"""
import argparse
import json
import math
import os
from pathlib import Path
import subprocess
import time

from compare_splash_performance import ROOT, footprint, save, sha
from compare_workflow_performance import BACKENDS, valid_job, worker
from probe_workflow_observation import compare


def cache_counts(request):
    values = [request.get('metrics', {}).get(key)
              for key in ['matchedPromptTokens', 'deduplicatedKVTokens']]
    if any(not isinstance(v, int) or isinstance(v, bool) or v < 0 for v in values):
        return None
    return values


def summarize(results, protocol, source_changes=None):
    problems, comparisons = [], []
    if source_changes:
        problems.append('Measured sources or binary changed: ' + ', '.join(source_changes))
    expected = {(name, backend) for name in protocol['workloads'] for backend in BACKENDS}
    indexed = {(r['workload'], r['backend']): r for r in results}
    if len(indexed) != len(results) or set(indexed) != expected:
        problems.append('Missing or duplicate workload/frontend worker')
    for result in results:
        label = result['workload'] + '/' + result['backend']
        ready = result.get('ready') or {}
        if (result.get('failure') or result.get('returncode') != 0
                or result.get('closed') != {'closed': True} or not ready.get('ready')):
            problems.append(label + ': startup/worker/cleanup failure')
        prime = ready.get('prime', {})
        if (prime.get('id') != 'prime' or prime.get('seed') != 0 or not valid_job(prime, protocol)
                or not math.isfinite(prime.get('completeSeconds', float('nan')))):
            problems.append(label + ': invalid Ready prime')
        rows = result.get('rows', [])
        if len(rows) != 2:
            problems.append(label + ': expected one warmup and one measured job')
        for sequence, row in enumerate(rows):
            if (row.get('id') != result['workload'] or row.get('seed') != sequence + 1
                    or row.get('sequence') != sequence or row.get('warmup') is not (sequence == 0)
                    or row.get('backend') != result['backend'] or row.get('block') != 0):
                problems.append(label + ': wrong job schedule')
            if not valid_job(row, protocol) or not math.isfinite(row.get('completeSeconds', float('nan'))):
                problems.append(label + ': failed or unmeasured job')
        roles = ['helper', 'host'] + (['reference'] if result['backend'] == 'reference' else [])
        if sorted(result.get('roles', [])) != sorted(roles):
            problems.append(label + ': incomplete process tree')
        states = [result.get(side, {}).get('thermalState', 3) for side in ['before', 'after']]
        if not all(result.get(side, {}).get('acPower') is True for side in ['before', 'after']):
            problems.append(label + ': lost AC power')
        for row in rows:
            memory = row.get('memory', {})
            if (memory.get('errors', ['missing errors']) or memory.get('sampleCount', 0) <= 0
                    or memory.get('observedPeakSumBytes', 0) <= 0
                    or sorted(memory.get('roles', [])) != sorted(roles)):
                problems.append(label + ': incomplete footprint sampling')
            states.append(memory.get('maximumThermalState', 3))
        if max(states) >= 2:
            problems.append(label + ': serious/critical thermal pressure')
        for job in [prime] + rows:
            for request in job.get('trace', {}).get('requests', []):
                if cache_counts(request) is None:
                    problems.append(label + ': missing cache counters')
                if request.get('maskTrace'):
                    problems.append(label + ': mask instrumentation is forbidden')
        if result.get('diagnosticObservation'):
            problems.append(label + ': observation intervention is forbidden')
    for name in protocol['workloads']:
        a, b = indexed.get((name, 'native')), indexed.get((name, 'reference'))
        if a is None or b is None or not (a.get('ready') or {}).get('prime') or not (b.get('ready') or {}).get('prime'):
            continue
        left = [a['ready']['prime']] + a['rows']
        right = [b['ready']['prime']] + b['rows']
        jobs_match = [(j.get('id'), j.get('seed')) for j in left] == [(j.get('id'), j.get('seed')) for j in right]
        comparable = jobs_match and all(valid_job(j, protocol) and all(
            cache_counts(r) is not None for r in j['trace']['requests']) for j in left + right)
        detail = compare(a, b) if comparable else {'sameRequests': False, 'sameTokens': False, 'pairs': []}
        counts_match = jobs_match and len(left) == len(right)
        counter_pairs = []
        for x, y in zip(left, right):
            xr, yr = x.get('trace', {}).get('requests', []), y.get('trace', {}).get('requests', [])
            counts_match = counts_match and bool(xr) and len(xr) == len(yr)
            for step, (u, v) in enumerate(zip(xr, yr), 1):
                n, r = cache_counts(u), cache_counts(v)
                match = n is not None and n == r
                counts_match = counts_match and match
                counter_pairs.append({'job': x.get('id'), 'seed': x.get('seed'), 'step': step,
                                      'native': n, 'reference': r, 'match': match})
        comparisons.append({'workload': name, **detail, 'sameCacheCounts': counts_match,
                            'cachePairs': counter_pairs,
                            'measuredCompleteSeconds': {side['backend']: side['rows'][-1].get('completeSeconds')
                                for side in [a, b] if len(side['rows']) == 2}})
    matched = len(comparisons) == len(protocol['workloads']) and all(
        c['sameRequests'] and c['sameTokens'] and c['sameCacheCounts'] for c in comparisons)
    return {'scope': 'I1 fresh-worker isolation pilot; not performance or adoption qualification',
            'problems': sorted(set(problems)), 'comparisons': comparisons,
            'isolationPilotPassed': not problems and matched,
            'performanceQualification': False, 'productionAdoption': False,
            'limits': 'Equal cache counts do not establish byte-identical cached state. One measured observation cannot qualify latency. W1 mixed-workload evidence remains separate and preserved.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    protocol_path = ROOT / 'integration/performance/workflow-isolation-pilot.json'
    protocol = json.loads(protocol_path.read_text())
    pin = json.loads((ROOT / 'integration/splash.json').read_text())
    model = json.loads((ROOT / 'Sources/SevraSplash/Resources/selected-model.json').read_text())
    grammar = json.loads((ROOT / '.build/llguidance-receipt.json').read_text())
    engine = ROOT / '.build/upstream' / ('splash-native-' + pin['release']) / 'engine/splash'
    for relative, checksum in pin['runtime']['files'].items():
        if sha(engine.parent.parent / relative) != checksum:
            raise ValueError('Changed pinned engine resource: ' + relative)
    if sha(ROOT / grammar['library']) != grammar['librarySHA256']:
        raise ValueError('Changed grammar library')
    if footprint(os.getpid())['bytes'] <= 0:
        raise ValueError('Footprint sampling is unavailable')
    config = {'engine': str(engine), 'assembly': str((args.models_root / model['name']).resolve(strict=True)),
              'engineFiles': {Path(k).name: v for k, v in pin['runtime']['files'].items() if k.startswith('engine/')},
              'grammarLibrary': str(ROOT / grammar['library']), 'grammarSHA256': grammar['librarySHA256'],
              'contextTokens': protocol['contextTokens'], 'memoryBytes': protocol['memoryBytes'],
              'cases': [], 'workflowQualification': True, 'diagnosticMasks': False,
              'modelsRoot': str(args.models_root.resolve()), 'python': str(ROOT / '.build/splash-reference/bin/python'),
              'referenceScript': str(ROOT / 'scripts/splash_performance_reference.py')}
    sources = sorted(set([str(p.relative_to(ROOT)) for p in (ROOT / 'Sources').rglob('*') if p.is_file()]
              + [str(p.relative_to(ROOT)) for p in (ROOT / 'IntegrationTests/WorkflowPerformance').glob('*.swift')]
              + ['scripts/probe_workflow_isolation.py', 'scripts/probe_workflow_observation.py',
                 'scripts/compare_workflow_performance.py', 'scripts/compare_splash_performance.py',
                 'scripts/splash_performance_reference.py', 'scripts/splash_reference_identity.py',
                 'integration/performance/workflow-isolation-pilot.json']))
    frozen = {name: sha(ROOT / name) for name in sources}
    frozen['.build/release/sevra-workflow-performance'] = sha(ROOT / '.build/release/sevra-workflow-performance')
    def changed():
        return [name for name, checksum in frozen.items() if not (ROOT / name).is_file() or sha(ROOT / name) != checksum]
    identity = {'scope': 'I1 diagnostic pilot', 'protocol': protocol, 'sourceSHA256': frozen,
                'baseCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'engineSHA256': sha(engine), 'grammarSHA256': grammar['librarySHA256'],
                'workerSHA256': frozen['.build/release/sevra-workflow-performance'],
                'machine': subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip(),
                'memoryBytes': int(subprocess.check_output(['sysctl', '-n', 'hw.memsize'], text=True)),
                'os': subprocess.check_output(['sw_vers'], text=True),
                'referenceDependencies': subprocess.check_output([config['python'], '-m', 'pip', 'freeze'], text=True),
                'startedUTC': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}
    save(output / 'identity.json', identity)
    results = []
    try:
        for i, name in enumerate(protocol['workloads']):
            folder = output / name
            folder.mkdir()
            scoped = dict(config, configPath=str(folder / 'config.json'))
            save(folder / 'config.json', scoped)
            save(folder / 'identity.json', identity)
            for backend in BACKENDS if i % 2 == 0 else reversed(BACKENDS):
                if changed():
                    raise RuntimeError('Measured sources changed; do not launch another worker')
                result = worker(backend, 0, [name], 1, folder / 'config.json', folder)
                result['workload'] = name
                save(folder / f'0-{backend}.json', result)
                results.append(result)
                save(output / 'summary.json', summarize(results, protocol, changed()))
                if result['failure']:
                    raise RuntimeError(result['failure'])
    finally:
        report = summarize(results, protocol, changed())
        save(output / 'summary.json', report)
        print(json.dumps(report), flush=True)
    if not report['isolationPilotPassed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
