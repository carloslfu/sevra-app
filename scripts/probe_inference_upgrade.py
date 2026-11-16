"""Bounded current-agent prerequisite for the frozen Splash upgrade.

This is not a replay of historical D9 prompts and cannot qualify performance.
Run the complete R/N/N/R prefix once; retain every failed job and divergent token.
"""
import argparse
import json
from pathlib import Path
import subprocess

from compare_splash_performance import ROOT, save, sha
from compare_workflow_performance import worker
from probe_workflow_prefix import audit, resource_files
from probe_workflow_observation import compare


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--models-root', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    pin = json.loads((ROOT / 'integration/splash.json').read_text())
    grammar = json.loads((ROOT / '.build/llguidance-receipt.json').read_text())
    pack = json.loads((ROOT / 'Sources/SevraSplash/Resources/selected-model.json').read_text())
    engine = ROOT / '.build/upstream' / ('splash-native-' + pin['release']) / 'engine/splash'
    binary = ROOT / '.build/debug/sevra-workflow-performance'
    for name, checksum in pin['runtime']['files'].items():
        if sha(engine.parent.parent / name) != checksum:
            raise ValueError('Engine component identity differs: ' + name)
    config = {'engine': str(engine), 'assembly': str(args.models_root.resolve() / pack['name']),
        'engineFiles': {Path(k).name:v for k,v in pin['runtime']['files'].items() if k.startswith('engine/')},
        'grammarLibrary': str(ROOT / grammar['library']), 'grammarSHA256': grammar['librarySHA256'],
        'contextTokens': 32768, 'memoryBytes': 12 * 1024**3, 'activations': 'bf16',
        'cases': [], 'workflowQualification': True, 'modelsRoot': str(args.models_root.resolve()),
        'python': str(ROOT / '.build/splash-reference-1.6.1-release/bin/python3'),
        'referenceScript': str(ROOT / 'scripts/splash_performance_reference.py')}
    paths = list((ROOT / 'Sources').rglob('*.swift')) + list((ROOT / 'IntegrationTests/WorkflowPerformance').glob('*.swift'))
    paths += list(resource_files(binary)) + [binary, engine, ROOT / grammar['library'],
        Path(__file__), ROOT / 'scripts/splash_performance_reference.py',
        ROOT / 'scripts/compare_workflow_performance.py', ROOT / 'scripts/compare_splash_performance.py',
        ROOT / 'integration/splash.json', ROOT / 'integration/performance/inference-upgrade-protocol.json']
    frozen = {str(p): sha(p) for p in paths}
    protocol = json.loads((ROOT / 'integration/performance/workflow-protocol.json').read_text())
    identity = {'scope': 'Current-agent R/N/N/R prerequisite; no historical-prompt or timing claim',
        'commit': subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
        'frozenFiles': frozen, 'pin': pin, 'config': config,
        'order': ['reference','native','native','reference'], 'seeds': [9001,9002]}
    save(output / 'identity.json', identity)
    results = []
    for index, backend in enumerate(identity['order']):
        if any(sha(Path(p)) != h for p,h in frozen.items()):
            raise RuntimeError('Frozen source changed')
        folder = output / (str(index) + '-' + backend)
        folder.mkdir()
        config_path = folder / 'config.json'
        save(config_path, dict(config, configPath=str(config_path)))
        result = worker(backend, 9, ['formula_review','inventory_evidence'], 0, config_path, folder, binary)
        results.append(result)
        problems = {str(i): audit(r,protocol) for i,r in enumerate(results)}
        summary = {'problems': problems, 'performanceQualification': False, 'productionAdoption': False}
        if len(results) == 4 and not any(problems.values()):
            summary.update(withinNative=compare(results[1],results[2]), withinReference=compare(results[0],results[3]),
                paired=[compare(results[0],results[1]),compare(results[3],results[2])])
        save(output / 'summary.json', summary)
        print(json.dumps({'run':index,'backend':backend,'problems':problems[str(index)]}),flush=True)
        if result.get('failure'):
            raise RuntimeError('Worker failed; fix the identified harness/engine defect before replay')
    if any(sha(Path(p)) != h for p,h in frozen.items()):
        raise RuntimeError('Frozen source changed')


if __name__ == '__main__':
    main()
