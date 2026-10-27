"""Fixed R2 functional cohort for exact item references, not speed qualification."""
import argparse
import json
import math
from pathlib import Path
import subprocess

from compare_splash_performance import ROOT, save, sha
from compare_workflow_performance import valid_job, worker


def installed_configuration(models_root):
    pin = json.loads((ROOT / 'integration/splash.json').read_text())
    model = json.loads((ROOT / 'Sources/SevraSplash/Resources/selected-model.json').read_text())
    grammar = json.loads((ROOT / '.build/llguidance-receipt.json').read_text())
    engine = ROOT / '.build/upstream' / ('splash-native-' + pin['release']) / 'engine/splash'
    return {'engine': str(engine), 'assembly': str((models_root / model['name']).resolve(strict=True)),
            'engineFiles': {Path(k).name: v for k, v in pin['runtime']['files'].items() if k.startswith('engine/')},
            'grammarLibrary': str(ROOT / grammar['library']), 'grammarSHA256': grammar['librarySHA256'],
            'contextTokens': 32768, 'memoryBytes': 12884901888, 'cases': [],
            'workflowQualification': True, 'diagnosticMasks': False,
            'modelsRoot': str(models_root.resolve()), 'python': str(ROOT / '.build/splash-reference/bin/python'),
            'referenceScript': str(ROOT / 'scripts/splash_performance_reference.py')}


def validate_configuration(config, protocol):
    pin = json.loads((ROOT / 'integration/splash.json').read_text())
    grammar = json.loads((ROOT / '.build/llguidance-receipt.json').read_text())
    expected = {Path(k).name: v for k, v in pin['runtime']['files'].items() if k.startswith('engine/')}
    if (config.get('diagnosticMasks') or config.get('diagnosticMaskDelaySeconds', 0)
            or config.get('contextTokens') != protocol['contextTokens']
            or config.get('memoryBytes') != protocol['memoryBytes']
            or config.get('engineFiles') != expected):
        raise ValueError('R2 requires the unchanged uninstrumented 32K configuration')
    for name, checksum in expected.items():
        if sha(Path(config['engine']).parent / name) != checksum:
            raise ValueError('R2 engine resource differs from the pin: ' + name)
    if (config.get('grammarSHA256') != grammar['librarySHA256']
            or sha(config['grammarLibrary']) != grammar['librarySHA256']):
        raise ValueError('R2 grammar library differs from the verified receipt')


def problems_for(result, protocol):
    problems = []
    label = result['backend']
    ready = result.get('ready') or {}
    if (result.get('failure') or result.get('returncode') != 0
            or result.get('closed') != {'closed': True} or ready.get('ready') is not True
            or not valid_job(ready.get('prime', {}), protocol)):
        problems.append(label + ': prime/worker/cleanup failure')
    rows = result.get('rows', [])
    if len(rows) != len(protocol['prompts']):
        problems.append(label + ': incomplete fixed schedule')
    roles = ['helper', 'host'] + (['reference'] if label == 'reference' else [])
    if sorted(result.get('roles', [])) != sorted(roles):
        problems.append(label + ': missing process')
    for index, row in enumerate(rows):
        tag = label + '/' + str(index + 1)
        if (index >= len(protocol['prompts']) or row.get('seed') != index + 1
                or row.get('id') != 'inventory_evidence'
                or row.get('prompt') != protocol['prompts'][index]):
            problems.append(tag + ': wrong fixture or prompt')
        steps = row.get('steps')
        if (not valid_job(row, protocol) or not math.isfinite(row.get('completeSeconds', float('nan')))
                or type(steps) is not int or not 1 <= steps <= 6 or row.get('validationFailures') != 0):
            problems.append(tag + ': failed, excessive or corrected job')
        calls = [c['name'] for r in row.get('trace', {}).get('responses', []) for c in r.get('calls', [])]
        if set(calls) & {'history_read', 'history_search', 'count_records'}:
            problems.append(tag + ': reference detour')
        for message in row.get('messages', []):
            if message.get('role') != 'tool':
                continue
            receipt = json.loads(message['body'])
            result_body = receipt.get('result')
            if receipt.get('validation') or (isinstance(result_body, dict) and result_body.get('error')):
                problems.append(tag + ': refused tool or finish')
        memory = row.get('memory', {})
        if (memory.get('errors', ['missing']) or memory.get('sampleCount', 0) <= 0
                or memory.get('maximumThermalState', 3) >= 2 or memory.get('observedPeakSumBytes', 0) <= 0
                or sorted(memory.get('roles', [])) != sorted(roles)):
            problems.append(tag + ': incomplete sampling or thermal limit')
    if not all(result.get(side, {}).get('acPower') is True
               and result.get(side, {}).get('thermalState', 3) < 2 for side in ['before', 'after']):
        problems.append(label + ': power/thermal boundary')
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    configuration = parser.add_mutually_exclusive_group(required=True)
    configuration.add_argument('--config', type=Path, help='Existing installed-layout workflow configuration')
    configuration.add_argument('--models-root', type=Path, help='Native setup root; builds configuration from repository pins')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    protocol = json.loads((ROOT / 'integration/performance/item-reference-probe.json').read_text())
    config = json.loads(args.config.read_text()) if args.config else installed_configuration(args.models_root)
    validate_configuration(config, protocol)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    config.update(inventoryPrompts=protocol['prompts'], configPath=str(output / 'config.json'))
    save(output / 'config.json', config)
    sources = sorted(set([str(p.relative_to(ROOT)) for p in (ROOT / 'Sources').rglob('*') if p.is_file()]
              + [str(p.relative_to(ROOT)) for p in (ROOT / 'IntegrationTests/WorkflowPerformance').glob('*.swift')]
              + ['scripts/probe_item_references.py', 'scripts/compare_workflow_performance.py',
                 'scripts/compare_splash_performance.py', 'scripts/splash_performance_reference.py',
                 'scripts/splash_reference_identity.py', 'integration/performance/item-reference-probe.json',
                 '.build/release/sevra-workflow-performance']))
    frozen = {p: sha(ROOT / p) for p in sources}
    for path in [config['engine'], config['grammarLibrary']]:
        frozen[str(Path(path).relative_to(ROOT))] = sha(path)
    save(output / 'identity.json', {'protocol': protocol, 'sourceSHA256': frozen,
         'baseCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
         'engineSHA256': sha(config['engine']), 'grammarSHA256': sha(config['grammarLibrary']),
         'sourceSnapshot': {p: (ROOT / p).read_text() for p in sources if p.endswith(('.swift', '.py', '.json'))}})
    def changed():
        return [p for p, checksum in frozen.items() if sha(ROOT / p) != checksum]
    results, problems = [], []
    try:
        for backend in ['native', 'reference']:
            if changed():
                raise RuntimeError('Measured source changed before worker launch')
            result = worker(backend, 0, ['inventory_evidence'], 5, output / 'config.json', output)
            results.append(result)
            problems.extend(problems_for(result, protocol))
    except Exception as error:
        problems.append(str(error))
        raise
    finally:
        if changed():
            problems.append('Measured source changed: ' + ', '.join(changed()))
        summary = {'scope': protocol['name'], 'passed': len(results) == 2 and not problems,
                   'problems': problems, 'performanceQualification': False, 'productionAdoption': False,
                   'workers': [{'backend': r['backend'], 'jobs': [{k: j.get(k) for k in
                       ['seed', 'prompt', 'steps', 'completeSeconds', 'errors', 'validationFailures']}
                       for j in r.get('rows', [])]} for r in results]}
        save(output / 'summary.json', summary)
        print(json.dumps(summary), flush=True)
    if not summary['passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
