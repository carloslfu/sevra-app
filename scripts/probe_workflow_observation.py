"""Isolate observation work from its response payload, without modifying Splash.

Development-only diagnostic. Each independent reference process completes Ready
and the four W1 warmups in the original order. The first previously divergent
request is in that prefix of the schedule. This is not a performance cohort.
"""
import argparse
import json
from pathlib import Path
import subprocess

from compare_splash_performance import ROOT, save, sha
from compare_workflow_performance import paired_jobs, valid_job, worker


def compare(left, right):
    pairs = []
    a = [left['ready']['prime']] + left['rows']
    b = [right['ready']['prime']] + right['rows']
    if [(j['id'], j['seed']) for j in a] != [(j['id'], j['seed']) for j in b]:
        raise ValueError('Different job schedules')
    for x, y in zip(a, b):
        xr, yr = x['trace']['requests'], y['trace']['requests']
        for i, (u, v) in enumerate(zip(xr, yr)):
            first = next((n for n, (p, q) in enumerate(zip(u['tokens'], v['tokens'])) if p != q),
                         min(len(u['tokens']), len(v['tokens'])))
            pairs.append({'job': x['id'], 'seed': x['seed'], 'step': i + 1,
                          'sameRequest': u['requestSHA256'] == v['requestSHA256'],
                          'sameTokens': u['tokens'] == v['tokens'],
                          'firstDifference': None if u['tokens'] == v['tokens'] else first,
                          'leftMatchedPrefix': u['metrics']['matchedPromptTokens'],
                          'rightMatchedPrefix': v['metrics']['matchedPromptTokens']})
    return {'sameRequests': all(paired_jobs(x, y) for x, y in zip(a, b)),
            'sameTokens': all([r['tokens'] for r in x['trace']['requests']]
                              == [r['tokens'] for r in y['trace']['requests']] for x, y in zip(a, b)),
            'pairs': pairs}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--modes', nargs='+', choices=['none', 'hash-no-payload', 'delay-2ms'],
                        default=['none', 'hash-no-payload', 'delay-2ms'])
    args = parser.parse_args()
    if len(set(args.modes)) != len(args.modes):
        parser.error('Each diagnostic mode must be unique')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    baseline = args.baseline.resolve()
    original_identity = json.loads((baseline / 'identity.json').read_text())
    original_config = json.loads((baseline / 'config.json').read_text())
    protocol = original_identity['protocol']
    if original_config.get('diagnosticMasks') is not True:
        raise ValueError('Choose a traced baseline for this observation comparison')
    # The unchanged native build is a fixed control. The reference observer is
    # the deliberate intervention, with its new source identity retained.
    if sha(ROOT / '.build/release/sevra-workflow-performance') != original_identity['workerSHA256']:
        raise ValueError('Worker build differs from the diagnostic baseline')
    for name, checksum in original_identity['sourceSHA256'].items():
        if name.startswith(('Sources/', 'IntegrationTests/WorkflowPerformance/')) and sha(ROOT / name) != checksum:
            raise ValueError('Native source differs: ' + name)
    if sha(original_config['engine']) != original_identity['engineSHA256']:
        raise ValueError('Engine binary differs')
    if sha(original_config['grammarLibrary']) != original_identity['grammarSHA256']:
        raise ValueError('Grammar binary differs')
    if sha(ROOT / 'Sources/SevraSplash/Resources/selected-model.json') != original_identity['modelManifestSHA256']:
        raise ValueError('Selected model manifest differs')
    expected = protocol['workloads']
    reference = json.loads((baseline / '0-reference.json').read_text())
    reference['rows'] = reference['rows'][:len(expected)]
    if reference['failure'] or not all(valid_job(row, protocol) for row in [reference['ready']['prime']] + reference['rows']):
        raise ValueError('Choose a baseline whose jobs completed successfully')
    identity = {'scope': 'Controlled observation diagnostic, not W1 qualification',
                'baseCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'baselineIdentitySHA256': sha(baseline / 'identity.json'),
                'baselineIdentity': original_identity,
                'sourceSHA256': {name: sha(ROOT / name) for name in [
                    'scripts/probe_workflow_observation.py', 'scripts/splash_performance_reference.py',
                    'scripts/compare_workflow_performance.py']},
                'modes': args.modes, 'schedule': 'Ready, then the four W1 warmups; no measured repetition',
                'limits': 'Same source, helper and worker except the named observer interventions. OS file caches and run time differ. All timings are unqualified.'}
    save(output / 'identity.json', identity)
    completed, comparisons, problems = {}, {}, []
    for mode in args.modes:
        folder = output / mode
        folder.mkdir()
        config = dict(original_config)
        config.update(diagnosticMasks=mode != 'none', diagnosticMaskMode='delay' if mode == 'delay-2ms' else 'hash',
                      diagnosticEmitMasks=False, diagnosticMaskDelaySeconds=.002 if mode == 'delay-2ms' else 0,
                      configPath=str(folder / 'config.json'))
        save(folder / 'config.json', config)
        save(folder / 'identity.json', identity)
        result = worker('reference', 0, expected, 0, folder / 'config.json', folder)
        result['diagnosticObservation'] = mode
        save(folder / '0-reference.json', result)
        rows = [(result.get('ready') or {}).get('prime', {})] + result['rows']
        if result['failure'] or result['returncode'] != 0 or result['closed'] != {'closed': True}:
            problems.append(mode + ': worker/cleanup failure')
        if len(rows) != 5 or not all(valid_job(j, protocol) for j in rows):
            problems.append(mode + ': incomplete/invalid jobs')
        if max(result['before']['thermalState'], result['after']['thermalState']) >= 2:
            problems.append(mode + ': serious/critical thermal boundary')
        if not result['before']['acPower'] or not result['after']['acPower']:
            problems.append(mode + ': lost AC power')
        for row in result['rows']:
            memory = row['memory']
            if (memory['errors'] or not memory['sampleCount']
                    or sorted(memory['roles']) != ['helper', 'host', 'reference']
                    or memory['maximumThermalState'] >= 2):
                problems.append(mode + ': incomplete sampling/thermal exclusion')
        comparison = compare(reference, result) if len(rows) == 5 and rows[0].get('trace') else None
        comparisons[mode] = comparison
        report = {'scope': 'Observation intervention, not performance or adoption qualification',
                  'mode': mode, 'problems': [p for p in problems if p.startswith(mode + ':')],
                  'comparisonAgainstTracedBaseline': comparison,
                  'performanceQualification': False, 'productionAdoption': False}
        save(folder / 'summary.json', report)
        completed[mode] = result
        save(output / 'summary.json', {'scope': identity['scope'], 'problems': problems,
             'comparisonsAgainstTracedBaseline': comparisons,
             'performanceQualification': False, 'productionAdoption': False})
        print(json.dumps({'mode': mode, 'problems': report['problems'],
                          'sameTracedTokens': comparison and comparison['sameTokens']}), flush=True)
        if problems:
            raise RuntimeError('Diagnostic failed; all partial evidence retained')
    if 'none' in completed:
        save(output / 'within-run-comparisons.json', {
            mode: compare(completed['none'], result) for mode, result in completed.items() if mode != 'none'})


if __name__ == '__main__':
    main()
