"""Replay W1 block 3 after the current-request evidence correction.

Functional regression only, never a replacement for the ten-block speed cohort.
Keeps the original Ready prime, four warmups and first four measured jobs, including
the failed missing-evidence fixture at seed 3005. Both frontends use unchanged pins.
"""
import argparse
import json
from pathlib import Path
import subprocess

from compare_splash_performance import ROOT, save, sha
from compare_workflow_performance import valid_job, worker
from probe_item_references import installed_configuration, validate_configuration
from probe_workflow_observation import compare


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    protocol = json.loads((ROOT / 'integration/performance/workflow-protocol.json').read_text())
    if protocol['workloads'] != ['supplier_space', 'formula_review', 'inventory_evidence', 'missing_evidence']:
        raise ValueError('The original W1 schedule changed; do not silently change this replay')
    config = installed_configuration(args.models_root)
    validate_configuration(config, protocol)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    config['configPath'] = str(output / 'config.json')
    save(output / 'config.json', config)
    paths = sorted(set(
        [str(p.relative_to(ROOT)) for p in (ROOT / 'Sources').rglob('*') if p.is_file()]
        + [str(p.relative_to(ROOT)) for p in (ROOT / 'IntegrationTests/WorkflowPerformance').glob('*.swift')]
        + ['scripts/probe_request_evidence.py', 'scripts/probe_item_references.py',
           'scripts/probe_workflow_observation.py', 'scripts/compare_workflow_performance.py',
           'scripts/compare_splash_performance.py', 'scripts/splash_performance_reference.py',
           'scripts/splash_reference_identity.py', 'integration/performance/workflow-protocol.json',
           '.build/release/sevra-workflow-performance']))
    frozen = {p: sha(ROOT / p) for p in paths}
    for path in [config['engine'], config['grammarLibrary']]:
        frozen[str(Path(path).relative_to(ROOT))] = sha(path)
    save(output / 'identity.json', {
        'scope': __doc__, 'protocol': protocol, 'sourceSHA256': frozen,
        'baseCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)),
        'sourceSnapshot': {p: (ROOT / p).read_text() for p in paths if p.endswith(('.swift', '.py', '.json'))},
    })

    def changed():
        return [p for p, checksum in frozen.items() if not (ROOT / p).is_file() or sha(ROOT / p) != checksum]

    results, problems, comparison = [], [], {}
    order = protocol['workloads'][3:] + protocol['workloads'][:3]
    try:
        for backend in ['reference', 'native']:
            if changed():
                raise RuntimeError('Frozen replay sources changed before worker launch')
            result = worker(backend, 3, order, 1, output / 'config.json', output)
            results.append(result)
            ready = result.get('ready') or {}
            if (result.get('failure') or result.get('returncode') != 0
                    or result.get('closed') != {'closed': True} or ready.get('ready') is not True
                    or not valid_job(ready.get('prime', {}), protocol)):
                problems.append(backend + ': prime/worker/cleanup failure')
            rows = result.get('rows', [])
            if len(rows) != 8:
                problems.append(backend + ': incomplete schedule')
            for index, row in enumerate(rows):
                if (index >= 8 or row.get('id') != order[index % 4]
                        or row.get('seed') != 3001 + index or not valid_job(row, protocol)):
                    problems.append(f'{backend}/{index}: wrong or failed job')
            if result.get('failure'):
                break
        if len(results) == 2 and not problems:
            comparison = compare(results[1], results[0])
            if not comparison['sameRequests'] or not comparison['sameTokens']:
                problems.append('Paired requests or generated tokens differ')
    except Exception as error:
        problems.append(str(error))
        raise
    finally:
        if changed():
            problems.append('Frozen source/binary identities changed')
        summary = {
            'scope': 'Current-request evidence repair; fixed W1 block 3 regression',
            'passed': len(results) == 2 and not problems, 'problems': problems,
            'comparison': comparison, 'performanceQualification': False, 'productionAdoption': False,
            'workers': [{'backend': r['backend'], 'jobs': [{k: j.get(k) for k in
                        ['id', 'seed', 'steps', 'errors', 'validationFailures', 'answer', 'citations']}
                        for j in r.get('rows', [])]} for r in results],
        }
        save(output / 'summary.json', summary)
        print(json.dumps(summary), flush=True)
    if not summary['passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
