"""D9: replay the exact prefix before W1's block-9 token divergence.

Uses the preserved measured worker, never a rebuild with newer application code.
Token variation is the observation; all validity and provenance gates stay strict.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from compare_splash_performance import ROOT, save, sha
from compare_workflow_performance import valid_job, worker
from probe_workflow_observation import compare


def resource_files(binary):
    root = binary.resolve().parent
    names = {
        'Sevra_SevraSplash.bundle/selected-model.json': 'Sources/SevraSplash/Resources/selected-model.json',
        'Sevra_SevraSplashText.bundle/template-patch.json': 'Sources/SevraSplashText/Resources/template-patch.json',
        'Sevra_SevraSplashGrammar.bundle/json-slices.json': 'Sources/SevraSplashGrammar/Resources/json-slices.json',
    }
    resources = {root / name: source for name, source in names.items()}
    for file in resources:
        if not file.is_file():
            raise ValueError('Preserved worker is missing an adjacent resource: ' + file.name)
    return resources


def audit(result, protocol):
    errors = []
    backend = result.get('backend')
    if backend not in ['native', 'reference']:
        errors.append('Unexpected frontend')
    if result.get('failure') or result.get('returncode') != 0 or result.get('closed') != {'closed': True}:
        errors.append('Worker/cleanup failed')
    ready = result.get('ready') or {}
    prime = ready.get('prime', {})
    rows = result.get('rows', [])
    if ready.get('ready') is not True or prime.get('id') != 'prime' or prime.get('seed') != 0:
        errors.append('Missing Ready prime')
    if [(r.get('id'), r.get('seed')) for r in rows] != [('formula_review', 9001), ('inventory_evidence', 9002)]:
        errors.append('Wrong prefix schedule')
    jobs = [prime] + rows
    if not all(valid_job(j, protocol) for j in jobs):
        errors.append('Invalid workbook job')
    expected_roles = ['helper', 'host'] + (['reference'] if backend == 'reference' else [])
    if sorted(result.get('roles', [])) != sorted(expected_roles):
        errors.append('Missing worker process roles')
    for side in ['before', 'after']:
        condition = result.get(side, {})
        if condition.get('acPower') is not True or condition.get('thermalState', 3) >= 2:
            errors.append('Power/thermal condition changed')
    for index, row in enumerate(rows):
        if row.get('warmup') is not True or row.get('block') != 9 or row.get('sequence') != index or row.get('backend') != backend:
            errors.append('Wrong prefix identity')
        memory = row.get('memory', {})
        if (memory.get('errors', ['missing']) or memory.get('sampleCount', 0) <= 0
                or memory.get('observedPeakSumBytes', 0) <= 0
                or sorted(memory.get('roles', [])) != sorted(expected_roles)
                or memory.get('maximumThermalState', 3) >= 2):
            errors.append('Incomplete memory/thermal sampling')
    for job in jobs:
        for request in job.get('trace', {}).get('requests', []):
            if request.get('maskTrace') or request.get('metrics', {}).get('diagnosticRequestCacheIsolation'):
                errors.append('Unexpected diagnostic intervention')
            for key in ['matchedPromptTokens', 'deduplicatedKVTokens']:
                value = request.get('metrics', {}).get(key)
                if not isinstance(value, int) or isinstance(value, bool) or value < 0:
                    errors.append('Missing cache counter')
    return sorted(set(errors))


def report(results, original, protocol, source_changes=()):
    order = ['reference', 'native', 'native', 'reference']
    problems = ['Diagnostic inputs changed: ' + ', '.join(source_changes)] if source_changes else []
    if [r.get('backend') for r in results] != order:
        problems.append('Incomplete or reordered frontend repeats')
    comparisons = []
    for index, result in enumerate(results):
        errors = audit(result, protocol)
        problems += [str(index) + ': ' + e for e in errors]
        if not errors:
            comparisons.append({'run': index, 'backend': result['backend'],
                                'againstHistoricalNative': compare(original['native'], result),
                                'againstHistoricalReference': compare(original['reference'], result)})
    within, cross = {}, []
    if not problems:
        within = {'native': compare(results[1], results[2]), 'reference': compare(results[0], results[3])}
        cross = [compare(results[0], results[1]), compare(results[3], results[2])]
    exact = lambda item: item['sameRequests'] and item['sameTokens']
    return {'scope': 'D9 fixed-prefix repeatability diagnostic, not performance qualification',
            'problems': problems, 'historicalComparisons': comparisons,
            'withinFrontend': within, 'crossFrontend': cross,
            'allJobsAndConditionsValid': not problems,
            'sameFrontendRepeatsMatch': bool(within) and all(exact(c) for c in within.values()),
            'newFrontendPairsMatch': bool(cross) and all(exact(c) for c in cross),
            'performanceQualification': False, 'productionAdoption': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--worker', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    baseline = args.baseline.resolve(strict=True)
    binary = args.worker.resolve(strict=True)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    plan_path = ROOT / 'integration/performance/workflow-prefix-repeatability.json'
    plan = json.loads(plan_path.read_text())
    identity = json.loads((baseline / 'identity.json').read_text())
    config = json.loads((baseline / 'config.json').read_text())
    if identity['baseCommit'] != plan['baselineCommit'] or identity['dirty']:
        raise ValueError('Use the recorded clean W1 baseline')
    if sha(binary) != identity['workerSHA256']:
        raise ValueError('The preserved worker differs from W1')
    resources = resource_files(binary)
    for file, source in resources.items():
        content = subprocess.check_output(['git', 'show', identity['baseCommit'] + ':' + source], cwd=ROOT)
        if sha(file) != hashlib.sha256(content).hexdigest():
            raise ValueError('Preserved worker resource differs from its recorded source: ' + source)
    # Application sources may now be newer. Bind the old executable to its
    # recorded committed tree, rather than pretending it was rebuilt from HEAD.
    for name, checksum in identity['sourceSHA256'].items():
        if name.startswith('.build/'):
            continue
        content = subprocess.check_output(['git', 'show', identity['baseCommit'] + ':' + name], cwd=ROOT)
        if hashlib.sha256(content).hexdigest() != checksum:
            raise ValueError('Baseline source provenance differs: ' + name)
    for key, value in [('engine', 'engineSHA256'), ('grammarLibrary', 'grammarSHA256')]:
        if sha(Path(config[key])) != identity[value]:
            raise ValueError('A measured native library differs: ' + key)
    if sha(ROOT / 'Sources/SevraSplash/Resources/selected-model.json') != identity['modelManifestSHA256']:
        raise ValueError('Model manifest differs')
    reference = ROOT / 'scripts/splash_performance_reference.py'
    if reference.resolve() != Path(config['referenceScript']).resolve() or sha(reference) != identity['sourceSHA256'][str(reference.relative_to(ROOT))]:
        raise ValueError('Reference runtime script differs')
    if config.get('diagnosticMasks') or config.get('diagnosticRequestCacheIsolation'):
        raise ValueError('The baseline includes a diagnostic intervention')
    if subprocess.check_output([config['python'], '-m', 'pip', 'freeze'], text=True) != identity['referenceDependencies']:
        raise ValueError('Reference dependencies differ')
    original = {}
    for backend in ['native', 'reference']:
        original[backend] = json.loads((baseline / ('9-' + backend + '.json')).read_text())
        original[backend]['rows'] = original[backend]['rows'][:2]
        errors = audit(original[backend], identity['protocol'])
        if errors:
            raise ValueError('Invalid historical prefix: ' + str(errors))
    files = [Path(__file__), plan_path, ROOT / 'scripts/compare_workflow_performance.py',
             ROOT / 'scripts/compare_splash_performance.py', ROOT / 'scripts/probe_workflow_observation.py',
             reference, binary, Path(config['engine']), Path(config['grammarLibrary']),
             ROOT / 'Sources/SevraSplash/Resources/selected-model.json'] + list(resources)
    frozen = {str(p): sha(p) for p in files}
    def changed():
        return [p for p, checksum in frozen.items() if not Path(p).is_file() or sha(Path(p)) != checksum]
    meta = {'plan': plan, 'baselineIdentity': identity,
            'baselineIdentitySHA256': sha(baseline / 'identity.json'),
            'baselineResultsSHA256': {b: sha(baseline / ('9-' + b + '.json')) for b in original},
            'controllerCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
            'frozenFiles': [{'name': str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else p.name,
                             'sha256': frozen[str(p)]} for p in files],
            'historicalSourceTreeVerified': True,
            'limits': plan['limits'], 'conditions': plan['conditions']}
    save(output / 'identity.json', meta)
    completed = []
    try:
        for index, backend in enumerate(plan['frontendOrder']):
            if changed():
                raise RuntimeError('Frozen diagnostic inputs changed')
            folder = output / (str(index) + '-' + backend)
            folder.mkdir()
            config_path = folder / 'config.json'
            current = dict(config, configPath=str(config_path))
            save(config_path, current)
            save(folder / 'identity.json', meta)
            result = worker(backend, 9, plan['workloads'], 0, config_path, folder, binary=binary)
            completed.append(result)
            errors = audit(result, identity['protocol'])
            save(folder / 'summary.json', {'problems': errors, 'performanceQualification': False, 'productionAdoption': False})
            summary = report(completed, original, identity['protocol'], changed())
            save(output / 'summary.json', summary)
            print(json.dumps({'run': index, 'backend': backend, 'problems': errors,
                              'againstHistorical': summary['historicalComparisons'][-1] if not errors else None}), flush=True)
            if errors:
                raise RuntimeError('Invalid diagnostic worker; evidence retained')
    finally:
        save(output / 'summary.json', report(completed, original, identity['protocol'], changed()))
    if report(completed, original, identity['protocol'], changed())['problems']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
