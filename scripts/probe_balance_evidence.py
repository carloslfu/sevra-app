"""Replay the I1 inventory schedule after clarifying calculation references.

This is a functional regression probe, not a paired performance comparison.
Both frontends must complete the original jobs without confusing workbook item
references with conversation IDs or inventing count-receipt requirements.
"""
import argparse
import json
from pathlib import Path
import subprocess

from compare_splash_performance import ROOT, save, sha
from compare_workflow_performance import valid_job, worker


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True,
                        help='The inventory_evidence directory from I1')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    old = json.loads((args.baseline / 'identity.json').read_text())
    config = json.loads((args.baseline / 'config.json').read_text())
    protocol = old['protocol']
    allowed = {'Sources/SevraCore/Tools.swift', 'Sources/SevraAI/WorkbookAgent.swift',
               '.build/release/sevra-workflow-performance'}
    changes = [p for p, checksum in old['sourceSHA256'].items() if sha(ROOT / p) != checksum]
    if not set(changes).issubset(allowed):
        raise ValueError('Unexpected source/build change from I1: ' + ', '.join(changes))
    if sha(config['engine']) != old['engineSHA256'] or sha(config['grammarLibrary']) != old['grammarSHA256']:
        raise ValueError('Helper or grammar differs from I1')
    if config.get('diagnosticMasks') or config.get('diagnosticMaskDelaySeconds', 0):
        raise ValueError('Recovery must be uninstrumented')
    sources = list(old['sourceSHA256']) + ['scripts/probe_balance_evidence.py']
    frozen = {p: sha(ROOT / p) for p in sources}
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    config['configPath'] = str(output / 'config.json')
    save(output / 'config.json', config)
    identity = {'scope': 'Balance reference recovery only; not performance qualification',
                'baseCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'baselineIdentity': old, 'changedFiles': changes, 'sourceSHA256': frozen,
                'workerSHA256': sha(ROOT / '.build/release/sevra-workflow-performance'),
                'schedule': 'Native then reference; each fresh worker runs Ready, inventory warmup seed 1, inventory measured seed 2.',
                'acceptance': 'Every original job assertion passes; no rejected finishes, history_read, history_search or count_records calls. Retain sampling, cleanup, power and thermal failures.',
                'performanceQualification': False, 'productionAdoption': False}
    save(output / 'identity.json', identity)
    problems, results = [], []
    try:
        for backend in ['native', 'reference']:
            if any(sha(ROOT / p) != checksum for p, checksum in frozen.items()):
                raise RuntimeError('Measured source changed during recovery probe')
            result = worker(backend, 0, ['inventory_evidence'], 1, output / 'config.json', output)
            results.append(result)
            jobs = [(result.get('ready') or {}).get('prime', {})] + result['rows']
            if (result['failure'] or result['returncode'] != 0 or result['closed'] != {'closed': True}
                    or len(jobs) != 3 or not all(valid_job(j, protocol) for j in jobs)):
                problems.append(backend + ': failed job or cleanup')
            roles = ['helper', 'host'] + (['reference'] if backend == 'reference' else [])
            if sorted(result['roles']) != roles:
                problems.append(backend + ': missing process')
            for job in result['rows']:
                calls = [c['name'] for r in job['trace']['responses'] for c in r['calls']]
                if job['validationFailures'] or set(calls) & {'history_read', 'history_search', 'count_records'}:
                    problems.append(backend + ': repeated evidence confusion')
                memory = job['memory']
                if (memory['errors'] or not memory['sampleCount'] or memory['maximumThermalState'] >= 2
                        or memory['observedPeakSumBytes'] <= 0 or sorted(memory['roles']) != roles):
                    problems.append(backend + ': sampling/thermal failure')
            if any(not result[side]['acPower'] or result[side]['thermalState'] >= 2 for side in ['before', 'after']):
                problems.append(backend + ': power/thermal boundary')
    except Exception as error:
        problems.append('Probe exception: ' + str(error))
        raise
    finally:
        changed = [p for p, checksum in frozen.items() if sha(ROOT / p) != checksum]
        if changed:
            problems.append('Measured source changed: ' + ', '.join(changed))
        report = {'scope': identity['scope'], 'problems': problems,
                  'recoveryPassed': len(results) == 2 and not problems,
                  'workers': [{'backend': r['backend'], 'jobs': [
                      {k: j.get(k) for k in ['id', 'seed', 'steps', 'completeSeconds', 'validationFailures', 'errors']}
                      for j in r['rows']]} for r in results],
                  'performanceQualification': False, 'productionAdoption': False}
        save(output / 'summary.json', report)
        print(json.dumps(report), flush=True)
    if not report['recoveryPassed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
