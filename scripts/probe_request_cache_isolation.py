"""I2 supplier diagnostic: matched shared-cache and request-isolated arms.

All timings are descriptive. This never qualifies adoption or performance.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import time

from compare_splash_performance import ROOT, footprint, save, sha
from compare_workflow_performance import worker
from probe_workflow_isolation import cache_counts, summarize as summarize_jobs

SALT_HIGH = 0x5345565241493200
# Pinned protocol 11: 16-byte frame header followed by the 114-byte request.
REQUEST = struct.Struct('<QBBQQIIIffIffffQIIIQQIII')


def verify_salts(result, directory, isolated):
    problems, salts = [], []
    jobs = [(result.get('ready') or {}).get('prime', {})] + result.get('rows', [])
    for job in jobs:
        for request in job.get('trace', {}).get('requests', []):
            try:
                checksum = request['requestSHA256']
                if len(checksum) != 64 or any(c not in '0123456789abcdef' for c in checksum):
                    raise ValueError('Invalid request hash')
                frame = base64.b64decode(json.loads((directory / (checksum + '.request.json')).read_text())['base64'], validate=True)
                if hashlib.sha256(frame).hexdigest() != checksum:
                    raise ValueError('Request frame hash differs')
                magic, version, kind, length = struct.unpack_from('<4sHHQ', frame)
                if magic != b'SPLH' or version != 11 or kind != 1 or length != len(frame) - 16:
                    raise ValueError('Invalid request frame header')
                fields = REQUEST.unpack_from(frame, 16)
                low, high = fields[19:21]
                salts.append([low, high])
                expected = [len(salts), SALT_HIGH] if isolated else [0, 0]
                if salts[-1] != expected:
                    raise ValueError('Wrong or reused cache salt')
                if request.get('metrics', {}).get('diagnosticRequestCacheIsolation') is not isolated:
                    raise ValueError('Missing or contradictory isolation identity')
                if isolated and cache_counts(request) != [0, 0]:
                    raise ValueError('Isolated request reused cached tokens')
            except (KeyError, ValueError, OSError, struct.error, TypeError) as error:
                problems.append(str(error))
    if not salts:
        problems.append('No request salt evidence')
    return {'problems': sorted(set(problems)), 'salts': salts}


def summarize(results, protocol, directories, source_changes=None):
    arms = {}
    for arm in protocol['arms']:
        rows = [r for r in results if r.get('cacheArm') == arm]
        report = summarize_jobs(rows, protocol, source_changes)
        checks = [verify_salts(r, directories[arm], arm == 'isolated') for r in rows]
        report['scope'] = 'I2 ' + arm + ' arm; diagnostic only'
        report['saltEvidence'] = checks
        report['armPassed'] = report.pop('isolationPilotPassed') and all(not c['problems'] for c in checks)
        arms[arm] = report
    return {'scope': protocol['name'], 'arms': arms,
            'completeComparison': len(results) == 4 and all(len(arms[a]['saltEvidence']) == 2 for a in protocol['arms']),
            'performanceQualification': False, 'productionAdoption': False,
            'limits': protocol['limits']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    protocol = json.loads((ROOT / 'integration/performance/request-cache-isolation-pilot.json').read_text())
    pin = json.loads((ROOT / 'integration/splash.json').read_text())
    model = json.loads((ROOT / 'Sources/SevraSplash/Resources/selected-model.json').read_text())
    grammar = json.loads((ROOT / '.build/llguidance-receipt.json').read_text())
    engine = ROOT / '.build/upstream' / ('splash-native-' + pin['release']) / 'engine/splash'
    for name, checksum in pin['runtime']['files'].items():
        if sha(engine.parent.parent / name) != checksum:
            raise ValueError('Changed pinned engine resource: ' + name)
    if sha(ROOT / grammar['library']) != grammar['librarySHA256'] or footprint(os.getpid())['bytes'] <= 0:
        raise ValueError('Grammar identity or footprint sampling failed')
    sources = [str(p.relative_to(ROOT)) for folder in ['Sources', 'IntegrationTests/WorkflowPerformance']
               for p in (ROOT / folder).rglob('*') if p.is_file()]
    sources += ['scripts/' + name + '.py' for name in [
        'probe_request_cache_isolation', 'probe_workflow_isolation', 'probe_workflow_observation',
        'compare_workflow_performance', 'compare_splash_performance',
        'splash_performance_reference', 'splash_reference_identity']]
    sources += ['integration/performance/request-cache-isolation-pilot.json', '.build/release/sevra-workflow-performance']
    frozen = {name: sha(ROOT / name) for name in sources}
    def changed():
        return [name for name, checksum in frozen.items() if not (ROOT / name).is_file() or sha(ROOT / name) != checksum]
    config = {'engine': str(engine), 'assembly': str((args.models_root / model['name']).resolve(strict=True)),
              'engineFiles': {Path(k).name: v for k, v in pin['runtime']['files'].items() if k.startswith('engine/')},
              'grammarLibrary': str(ROOT / grammar['library']), 'grammarSHA256': grammar['librarySHA256'],
              'contextTokens': protocol['contextTokens'], 'memoryBytes': protocol['memoryBytes'],
              'cases': [], 'workflowQualification': True, 'diagnosticMasks': False,
              'modelsRoot': str(args.models_root.resolve()), 'python': str(ROOT / '.build/splash-reference/bin/python'),
              'referenceScript': str(ROOT / 'scripts/splash_performance_reference.py')}
    identity = {'scope': protocol['name'], 'protocol': protocol, 'sourceSHA256': frozen,
                'baseCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'engineSHA256': sha(engine), 'grammarSHA256': grammar['librarySHA256'],
                'workerSHA256': frozen['.build/release/sevra-workflow-performance'],
                'machine': subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip(),
                'memoryBytes': int(subprocess.check_output(['sysctl', '-n', 'hw.memsize'], text=True)),
                'os': subprocess.check_output(['sw_vers'], text=True),
                'referenceDependencies': subprocess.check_output([config['python'], '-m', 'pip', 'freeze'], text=True),
                'startedUTC': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}
    save(output / 'identity.json', identity)
    results, directories = [], {arm: output / arm for arm in protocol['arms']}
    try:
        for arm, folder in directories.items():
            folder.mkdir()
            scoped = dict(config, diagnosticRequestCacheIsolation=arm == 'isolated', configPath=str(folder / 'config.json'))
            save(folder / 'config.json', scoped)
            save(folder / 'identity.json', identity)
            for backend in (['native', 'reference'] if arm == 'shared' else ['reference', 'native']):
                if changed():
                    raise RuntimeError('Measured sources changed; refusing another worker')
                result = worker(backend, 0, protocol['workloads'], 1, folder / 'config.json', folder)
                result.update(workload='supplier_space', cacheArm=arm)
                save(folder / f'0-{backend}.json', result)
                results.append(result)
                save(output / 'summary.json', summarize(results, protocol, directories, changed()))
                if result['failure']:
                    raise RuntimeError(result['failure'])
    finally:
        report = summarize(results, protocol, directories, changed())
        save(output / 'summary.json', report)
        for arm, detail in report['arms'].items():
            if directories[arm].exists():
                save(directories[arm] / 'summary.json', detail)
        print(json.dumps(report), flush=True)
    if not report['completeComparison'] or not all(a['armPassed'] for a in report['arms'].values()):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
