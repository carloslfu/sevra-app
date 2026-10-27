"""Replay one frontend of a successful W1 pilot with its exact recorded build.

Diagnostic only: separates within-frontend repeatability from cross-frontend
comparison. A repeatability result is not a performance or adoption gate.
"""
import argparse
import json
from pathlib import Path
import subprocess

from compare_workflow_performance import ROOT, paired_jobs, valid_job, worker
from compare_splash_performance import environment, save, sha


def compare(baseline, replay, protocol):
    problems, comparisons = [], []
    backend = baseline['backend']
    if backend not in ['native', 'reference'] or replay['backend'] != backend:
        problems.append('Mismatched frontend')
    expected_roles = ['helper', 'host'] + (['reference'] if backend == 'reference' else [])
    for label, result in [('baseline', baseline), ('replay', replay)]:
        ready = result.get('ready') or {}
        if (result.get('failure') or result.get('returncode') != 0
                or result.get('closed') != {'closed': True} or not ready.get('ready')):
            problems.append(label + ': worker or cleanup failure')
        for row in [ready.get('prime', {})] + result.get('rows', []):
            if not valid_job(row, protocol):
                problems.append(label + ': invalid job ' + str(row.get('id')))
        if not result['before']['acPower'] or not result['after']['acPower']:
            problems.append(label + ': AC supply changed')
        states = [result['before']['thermalState'], result['after']['thermalState']]
        for row in result['rows']:
            memory = row['memory']
            states.append(memory['maximumThermalState'])
            if memory['errors'] or not memory['sampleCount'] or sorted(memory['roles']) != sorted(expected_roles):
                problems.append(label + ': incomplete process sampling')
        if max(states) >= 2:
            problems.append(label + ': serious/critical thermal pressure')
    left = [baseline['ready']['prime']] + baseline['rows']
    right = [replay['ready']['prime']] + replay['rows']
    expected = 1 + 2 * len(protocol['workloads'])
    if len(left) != expected or len(right) != expected:
        problems.append('Incomplete frontend replay schedule')
    for before, after in zip(left, right):
        identity = before['id'] == after['id'] and before['seed'] == after['seed']
        a, b = before['trace']['requests'], after['trace']['requests']
        differences = []
        for index, (x, y) in enumerate(zip(a, b)):
            if x['tokens'] != y['tokens']:
                offset = next((i for i, (u, v) in enumerate(zip(x['tokens'], y['tokens'])) if u != v),
                              min(len(x['tokens']), len(y['tokens'])))
                differences.append({'step': index + 1, 'firstDifferentToken': offset,
                                    'sameRequestFrame': x['requestSHA256'] == y['requestSHA256'],
                                    'baselineTokens': len(x['tokens']), 'replayTokens': len(y['tokens']),
                                    'baselineMatchedPrefix': x['metrics']['matchedPromptTokens'],
                                    'replayMatchedPrefix': y['metrics']['matchedPromptTokens']})
        equal_tokens = bool(a) and [r['tokens'] for r in a] == [r['tokens'] for r in b]
        comparisons.append({'id': before['id'], 'seed': before['seed'], 'sameJob': identity,
                            'sameRequests': identity and paired_jobs(before, after),
                            'sameGeneratedTokens': equal_tokens,
                            'baselineRequests': len(a), 'replayRequests': len(b),
                            'differences': differences})
    exact = not problems and all(r['sameRequests'] and r['sameGeneratedTokens'] for r in comparisons)
    return {'scope': f'Same-{backend} diagnostic replay, not performance or adoption qualification',
            'problems': problems, 'jobs': comparisons,
            'exactReplay': exact, **({'exactNativeReplay': exact} if backend == 'native' else {}),
            'performanceQualification': False, 'productionAdoption': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--backend', choices=['native', 'reference'], default='native')
    parser.add_argument('--disable-mask-tracing', action='store_true', help='Controlled diagnostic: disable observation only, retaining the exact build and schedule')
    args = parser.parse_args()
    baseline = args.baseline.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    identity = json.loads((baseline / 'identity.json').read_text())
    protocol = identity['protocol']
    original = json.loads((baseline / f'0-{args.backend}.json').read_text())
    if sha(ROOT / '.build/release/sevra-workflow-performance') != identity['workerSHA256']:
        raise RuntimeError('Worker binary differs from the recorded pilot; use a matching build')
    for name, checksum in identity['sourceSHA256'].items():
        relevant = name.startswith(('Sources/', 'IntegrationTests/WorkflowPerformance/')) or (args.backend == 'reference' and name == 'scripts/splash_performance_reference.py')
        if relevant and sha(ROOT / name) != checksum:
            raise RuntimeError('Frontend source differs from recorded pilot: ' + name)
    if original['failure'] or any(r['errors'] for r in original['rows']):
        raise RuntimeError('Choose a frontend pilot whose jobs completed successfully')
    config = json.loads((baseline / 'config.json').read_text())
    if sha(Path(config['engine'])) != identity['engineSHA256'] or sha(Path(config['grammarLibrary'])) != identity['grammarSHA256']:
        raise RuntimeError('Engine or grammar binary differs from the recorded pilot')
    if sha(ROOT / 'Sources/SevraSplash/Resources/selected-model.json') != identity['modelManifestSHA256']:
        raise RuntimeError('Selected model manifest differs from the recorded pilot')
    if args.disable_mask_tracing:
        if not config.get('diagnosticMasks'):
            raise RuntimeError('The baseline did not trace masks; there is no observation change to test')
        config['diagnosticMasks'] = False
    config_path = output / 'config.json'
    config['configPath'] = str(config_path)
    save(config_path, config)
    save(output / 'identity.json', {
        'scope': 'Replay the exact frontend build, fixture seeds and cache-history schedule',
        'backend': args.backend, 'maskTracingDisabled': args.disable_mask_tracing,
        'baseCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'workerSHA256': identity['workerSHA256'], 'baselineIdentitySHA256': sha(baseline / 'identity.json'),
        'baselineResultSHA256': sha(baseline / f'0-{args.backend}.json'), 'baselineIdentity': identity,
        'controllerSHA256': sha(__file__), 'sharedControllerSHA256': sha(ROOT / 'scripts/compare_workflow_performance.py'),
        'conditions': environment(),
        'limits': 'Same hardware, helper, weights, foreground priority and full declared W1 schedule. OS file caches and time differ. Do not attribute a difference to the engine or grammar without isolating it.'})
    result = worker(args.backend, 0, protocol['workloads'], 1, config_path, output)
    report = compare(original, result, protocol)
    report['maskTracingDisabled'] = args.disable_mask_tracing
    save(output / 'summary.json', report)
    print(json.dumps(report), flush=True)
    if not report['exactReplay']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
