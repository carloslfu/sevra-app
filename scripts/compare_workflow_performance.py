"""W1: compare complete, validated workbook jobs through two matched frontends.

Development tooling only. The same Swift WorkbookAgent owns both sides; Python
is a private reference subprocess, never an installed product dependency.
"""
import argparse
import base64
import hashlib
import fcntl
import json
import math
import os
from pathlib import Path
import signal
import statistics
import subprocess
import time

from compare_splash_performance import ROOT, Sampler, digest, environment, footprint, line, save, sha

BACKENDS = ('native', 'reference')


def descendants(pid):
    processes = {}
    for row in subprocess.check_output(['ps', '-axo', 'pid=,ppid=,comm='], text=True).splitlines():
        child, parent, command = row.strip().split(None, 2)
        processes[int(child)] = {'pid': int(child), 'parent': int(parent), 'command': command}
    selected = {pid}
    while True:
        expanded = selected | {p for p, info in processes.items() if info['parent'] in selected}
        if expanded == selected:
            return [processes[p] for p in sorted(selected) if p in processes]
        selected = expanded


def process_roles(processes, pid, backend):
    roles = []
    for info in processes:
        name = Path(info['command']).name.lower()
        roles.append('host' if info['pid'] == pid else 'helper' if name == 'splash'
                     else 'reference' if name.startswith('python') else 'unexpected')
    expected = ['helper', 'host'] + (['reference'] if backend == 'reference' else [])
    if sorted(roles) != sorted(expected):
        raise RuntimeError(f'Incomplete or unexpected sampled process tree: {roles}')
    return roles


def preserve_prompts(job, output):
    for request in job.get('trace', {}).get('requests', []):
        frame = base64.b64decode(request.pop('requestFrame'), validate=True)
        request['requestSHA256'] = hashlib.sha256(frame).hexdigest()
        frame_path = output / (request['requestSHA256'] + '.request.json')
        if not frame_path.exists():
            save(frame_path, {'base64': base64.b64encode(frame).decode('ascii')})
        tokens = request.pop('promptTokens')
        checksum = digest(tokens)
        request.update(promptTokenCount=len(tokens), promptSHA256=checksum)
        path = output / (checksum + '.prompt.json')
        if not path.exists():
            save(path, tokens)


def assert_available():
    # Workers own the real product lease. Holding it in this coordinator would
    # make every actual WorkbookAgent fail admission. Refuse existing activity.
    path = Path.home() / 'Library/Application Support/Sevra/inference.lock'
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    finally:
        os.close(fd)


def worker(backend, block, order, repetitions, config_path, output):
    assert_available()
    before = environment()
    if not before['acPower']:
        raise RuntimeError('AC power required before starting a worker')
    command = [str(ROOT / '.build/release/sevra-workflow-performance'), str(config_path), backend]
    rows, ready, processes, roles = [], None, [], []
    failure, closed = None, None
    raw = output / f'{block}-{backend}.json'
    started = time.monotonic()
    stderr = (output / f'{block}-{backend}.stderr').open('w')
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=stderr, start_new_session=True,
                               env=dict(os.environ, HF_HUB_OFFLINE='1', TOKENIZERS_PARALLELISM='false'))
    def snapshot():
        return {'backend': backend, 'block': block, 'ready': ready, 'before': before,
                'rows': rows, 'processes': processes, 'roles': roles, 'failure': failure,
                'closed': closed, 'returncode': process.poll()}
    try:
        ready = line(process, timeout=660)
        ready['launchToReadySeconds'] = time.monotonic() - started
        preserve_prompts(ready.get('prime', {}), output)
        save(raw, snapshot())
        if not ready.get('ready'):
            raise RuntimeError('Priming failed; see retained ready/prime evidence')
        processes = descendants(process.pid)
        roles = process_roles(processes, process.pid, backend)
        schedule = [(True, name) for name in order] + [
            (False, name) for _ in range(repetitions) for name in order]
        for sequence, (warmup, name) in enumerate(schedule):
            seed = block * 1000 + sequence + 1
            sampler = Sampler([p['pid'] for p in processes])
            sampler.thread.start()
            try:
                command = {'id': name, 'seed': seed}
                process.stdin.write((json.dumps(command) + '\n').encode())
                process.stdin.flush()
                row = line(process, timeout=660)
            except Exception as error:
                row = {'id': name, 'seed': seed, 'errors': [str(error)], 'error': str(error)}
            finally:
                memory = sampler.stop()
                memory_path = f'{block}-{backend}-{sequence}.memory.json'
                save(output / memory_path, sampler.samples)
                memory['trace'] = memory_path
                memory['roles'] = roles
            if row.get('id') != name or row.get('seed') != seed:
                row.setdefault('errors', []).append('Worker returned the wrong job identity')
            row.update(backend=backend, block=block, warmup=warmup, sequence=sequence, memory=memory)
            preserve_prompts(row, output)
            rows.append(row)
            save(raw, snapshot())
            print(json.dumps({'backend': backend, 'block': block, 'id': name, 'warmup': warmup,
                              'seconds': row.get('completeSeconds'), 'errors': row.get('errors'),
                              'validationFailures': row.get('validationFailures')}), flush=True)
            if 'error' in row or process.poll() is not None:
                raise RuntimeError('Worker failed; partial job and sampling evidence retained')
        process.stdin.write(b'{"op":"close"}\n')
        process.stdin.flush()
        closed = line(process, timeout=60)
        process.wait(timeout=30)
        if closed.get('closed') is not True or process.returncode:
            raise RuntimeError('Worker did not confirm successful model shutdown')
        # All recorded descendants must exit, including the reference bridge.
        for info in processes:
            try:
                os.kill(info['pid'], 0)
            except ProcessLookupError:
                continue
            raise RuntimeError('A recorded worker process remained alive after shutdown')
        assert_available()
    except Exception as error:
        failure = str(error)
    finally:
        # A failed prime exits itself after releasing the model. Reap that exit
        # before considering a signal; retain cleanup errors separately.
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            owned = processes
            try:
                owned = descendants(process.pid)
                if os.getpgid(process.pid) == process.pid:
                    os.killpg(process.pid, signal.SIGTERM)
                else:
                    process.terminate()
                process.wait(timeout=10)
            except (OSError, subprocess.TimeoutExpired) as error:
                failure = failure or f'Owned worker cleanup failed: {error}'
                # These PIDs were captured while still descendants of this
                # worker. Recheck executable identity before a forced stop.
                current = {p['pid']: p for p in descendants(process.pid)}
                for info in reversed(owned):
                    if current.get(info['pid'], {}).get('command') == info['command']:
                        try:
                            os.kill(info['pid'], signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    failure = 'Owned worker did not exit after forced cleanup'
        stderr.close()
        result = snapshot()
        result['after'] = environment()
        save(raw, result)
    return result


def valid_job(row, protocol):
    requests = row.get('trace', {}).get('requests', [])
    responses = row.get('trace', {}).get('responses', [])
    return (not row.get('errors', ['missing errors']) and 'error' not in row
            and isinstance(row.get('completeSeconds'), (float, int)) and row['completeSeconds'] > 0
            and bool(requests) and len(requests) == len(responses)
            and all(r.get('requestSHA256') and r.get('promptSHA256') and 0 < r.get('promptTokenCount', 0) <= protocol['maximumPromptTokens']
                    and r.get('generationTokens', 0) > 0 and bool(r.get('tokens')) for r in requests))


def paired_jobs(a, b):
    ar, br = a.get('trace', {}).get('requests', []), b.get('trace', {}).get('requests', [])
    return (a.get('startingItems') is not None and a.get('startingItems') == b.get('startingItems')
            and bool(ar) and len(ar) == len(br)
            and all(x.get('requestSHA256') and x.get('requestSHA256') == y.get('requestSHA256')
                    and x.get('promptSHA256') and x.get('promptSHA256') == y.get('promptSHA256')
                    and x.get('generationTokens') == y.get('generationTokens') for x, y in zip(ar, br)))


def summarize(results, protocol, pilot):
    expected_blocks = 1 if pilot else protocol['blocks']
    repetitions = 1 if pilot else protocol['repetitionsPerWorkloadPerBlock']
    excluded, problems = {}, []
    indexed = {(r['block'], r['backend']): r for r in results}
    if len(indexed) != len(results) or set(indexed) != {
        (block, backend) for block in range(expected_blocks) for backend in BACKENDS
    }:
        problems.append('Missing or duplicate paired worker')
    paired, tokens_equal = True, True
    for result in results:
        block, backend = result['block'], result['backend']
        ready = result.get('ready') or {}
        if (result.get('failure') or result.get('returncode') != 0 or result.get('closed') != {'closed': True}
                or ready.get('ready') is not True or not valid_job(ready.get('prime', {}), protocol)):
            problems.append(f'{block}/{backend}: worker or priming failure')
        required_roles = ['helper', 'host'] + (['reference'] if backend == 'reference' else [])
        if sorted(result.get('roles', [])) != sorted(required_roles):
            problems.append(f'{block}/{backend}: missing process footprint')
        if not result['before']['acPower'] or not result['after']['acPower']:
            excluded.setdefault(block, []).append('Lost AC supply')
        states = [result['before']['thermalState'], result['after']['thermalState']]
        order = protocol['workloads']
        order = order[block % len(order):] + order[:block % len(order)]
        schedule = [(True, name) for name in order] + [(False, name) for _ in range(repetitions) for name in order]
        rows = result['rows']
        if [(r.get('warmup'), r.get('id')) for r in rows] != schedule:
            problems.append(f'{block}/{backend}: missing, duplicate or out-of-order jobs/warmups')
        for sequence, row in enumerate(rows):
            memory = row.get('memory', {})
            states.append(memory.get('maximumThermalState', 0))
            if (not valid_job(row, protocol) or row.get('sequence') != sequence
                    or row.get('seed') != block * 1000 + sequence + 1
                    or row.get('backend') != backend or row.get('block') != block
                    or memory.get('errors', ['missing errors']) or memory.get('sampleCount', 0) == 0
                    or memory.get('observedPeakSumBytes', 0) <= 0
                    or sorted(memory.get('roles', [])) != sorted(required_roles)):
                problems.append(f'{block}/{backend}/{sequence}: invalid job or sampling evidence')
        if max(states) >= 2:
            excluded.setdefault(block, []).append('Serious or critical thermal pressure')
    for block in range(expected_blocks):
        a, b = indexed.get((block, 'native')), indexed.get((block, 'reference'))
        if not a or not b:
            paired = False
            continue
        left = [(a.get('ready') or {}).get('prime', {})] + a['rows']
        right = [(b.get('ready') or {}).get('prime', {})] + b['rows']
        paired = paired and len(left) == len(right)
        for x, y in zip(left, right):
            paired = paired and x.get('id') == y.get('id') and x.get('seed') == y.get('seed') and paired_jobs(x, y)
            xt = [r.get('tokens') for r in x.get('trace', {}).get('requests', [])]
            yt = [r.get('tokens') for r in y.get('trace', {}).get('requests', [])]
            tokens_equal = tokens_equal and bool(xt) and xt == yt
    comparisons = []
    for name in protocol['workloads']:
        stats = {}
        for backend in BACKENDS:
            rows = [r for result in results if result['backend'] == backend and result['block'] not in excluded
                    for r in result['rows'] if r.get('id') == name and r.get('warmup') is False]
            times = sorted(r['completeSeconds'] for r in rows if r.get('completeSeconds', 0) > 0)
            stats[backend] = {'samples': len(times), 'failed': sum(not valid_job(r, protocol) for r in rows),
                              'medianSeconds': statistics.median(times) if times else None,
                              'p95Seconds': times[math.ceil(.95 * len(times)) - 1] if times else None,
                              'validationFailures': sum(r.get('validationFailures', 0) for r in rows),
                              'observedPeakSumBytes': max((r['memory']['observedPeakSumBytes'] for r in rows), default=0)}
        ratios = {key: stats['native'][key] / stats['reference'][key]
                  if stats['native'][key] and stats['reference'][key] else None
                  for key in ['medianSeconds', 'p95Seconds']}
        latency = (all(s['samples'] == expected_blocks * repetitions and not s['failed'] for s in stats.values())
                   and ratios['medianSeconds'] is not None
                   and ratios['medianSeconds'] <= 1 + protocol['gate']['maximumMedianRegression']
                   and ratios['p95Seconds'] <= 1 + protocol['gate']['maximumP95Regression'])
        comparisons.append({'id': name, 'stats': stats, 'ratios': ratios, 'latencyThresholdsMet': latency})
    return {'pilot': pilot, 'problems': problems, 'excludedPairedBlocks': excluded,
            'identicalPairedPrompts': paired, 'identicalGeneratedTokens': tokens_equal, 'comparisons': comparisons,
            'workflowGatePassed': not pilot and not problems and not excluded and paired and tokens_equal
                                  and all(c['latencyThresholdsMet'] for c in comparisons),
            'productionAdoption': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--models-root', type=Path, required=True)
    parser.add_argument('--pilot', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    protocol_path = ROOT / 'integration/performance/workflow-protocol.json'
    protocol = json.loads(protocol_path.read_text())
    dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT))
    if dirty and not args.pilot:
        raise RuntimeError('Commit the tested harness and frozen protocol before qualification')
    pin = json.loads((ROOT / 'integration/splash.json').read_text())
    pack = json.loads((ROOT / 'Sources/SevraSplash/Resources/selected-model.json').read_text())
    assembly = (args.models_root / pack['name']).resolve(strict=True)
    grammar = json.loads((ROOT / '.build/llguidance-receipt.json').read_text())
    engine = ROOT / '.build/upstream' / ('splash-native-' + pin['release']) / 'engine/splash'
    for relative, checksum in pin['runtime']['files'].items():
        assert sha(engine.parent.parent / relative) == checksum, relative
    assert sha(ROOT / grammar['library']) == grammar['librarySHA256']
    assert footprint(os.getpid())['bytes'] > 0
    config_path = output / 'config.json'
    config = {'engine': str(engine), 'assembly': str(assembly),
              'engineFiles': {Path(k).name: v for k, v in pin['runtime']['files'].items() if k.startswith('engine/')},
              'grammarLibrary': str(ROOT / grammar['library']), 'grammarSHA256': grammar['librarySHA256'],
              'contextTokens': protocol['contextTokens'], 'memoryBytes': protocol['memoryBytes'], 'cases': [], 'workflowQualification': True,
              'modelsRoot': str(args.models_root.resolve()), 'python': str(ROOT / '.build/splash-reference/bin/python'),
              'referenceScript': str(ROOT / 'scripts/splash_performance_reference.py'), 'configPath': str(config_path)}
    save(config_path, config)
    sources = ['IntegrationTests/WorkflowPerformance/Runner.swift', 'IntegrationTests/WorkflowPerformance/ReferenceModel.swift',
               'Sources/SevraCore/FixtureContext.swift', 'Sources/SevraCore/Types.swift',
               'Sources/SevraNativeAI/NativeWorkbookModel.swift', 'Sources/SevraAI/WorkbookInference.swift',
               'Sources/SevraAI/WorkbookAgent.swift',
               'scripts/splash_performance_reference.py', 'scripts/compare_splash_performance.py',
               'scripts/compare_workflow_performance.py', 'integration/performance/workflow-protocol.json']
    sources = sorted(set(sources + [str(p.relative_to(ROOT)) for p in (ROOT / 'Sources').rglob('*.swift')]))
    save(output / 'identity.json', {
        'protocol': protocol, 'sourceSHA256': {name: sha(ROOT / name) for name in sources},
        'engineSHA256': sha(engine), 'grammarSHA256': grammar['librarySHA256'],
        'workerSHA256': sha(ROOT / '.build/release/sevra-workflow-performance'),
        'baseCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), 'dirty': dirty,
        'modelManifestSHA256': sha(ROOT / 'Sources/SevraSplash/Resources/selected-model.json'),
        'machine': subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip(),
        'memoryBytes': int(subprocess.check_output(['sysctl', '-n', 'hw.memsize'], text=True)),
        'os': subprocess.check_output(['sw_vers'], text=True),
        'swift': subprocess.check_output(['swift', '--version'], text=True),
        'referenceDependencies': subprocess.check_output([config['python'], '-m', 'pip', 'freeze'], text=True),
        'startedUTC': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())})
    results = []
    try:
        for block in range(1 if args.pilot else protocol['blocks']):
            order = protocol['workloads']
            order = order[block % len(order):] + order[:block % len(order)]
            for backend in BACKENDS if block % 2 == 0 else reversed(BACKENDS):
                result = worker(backend, block, order, 1 if args.pilot else protocol['repetitionsPerWorkloadPerBlock'], config_path, output)
                results.append(result)
                save(output / 'summary.json', summarize(results, protocol, args.pilot))
                if result['failure']:
                    raise RuntimeError(result['failure'])
    finally:
        summary = summarize(results, protocol, args.pilot)
        save(output / 'summary.json', summary)
        print(json.dumps(summary), flush=True)
    if summary['problems'] or summary['excludedPairedBlocks'] or not summary['identicalPairedPrompts'] or not summary['identicalGeneratedTokens']:
        raise SystemExit(1)
    if not args.pilot and not summary['workflowGatePassed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
