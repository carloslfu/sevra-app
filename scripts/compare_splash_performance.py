"""Interleaved, local-only comparison of Swift and pinned Splash Python requests.

Runs sequential workers under Sevra's shared inference lease. Raw evidence is
written before assertions; --pilot cannot satisfy the performance gate.
"""
import argparse
import ctypes
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import select
import signal
import statistics
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[1]

ctypes.CDLL('/System/Library/Frameworks/Foundation.framework/Foundation')
OBJC = ctypes.CDLL('/usr/lib/libobjc.A.dylib')
OBJC.objc_getClass.argtypes = [ctypes.c_char_p]
OBJC.objc_getClass.restype = ctypes.c_void_p
OBJC.sel_registerName.argtypes = [ctypes.c_char_p]
OBJC.sel_registerName.restype = ctypes.c_void_p
MESSAGE = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)(('objc_msgSend', OBJC))
INTEGER_MESSAGE = ctypes.CFUNCTYPE(ctypes.c_long, ctypes.c_void_p, ctypes.c_void_p)(('objc_msgSend', OBJC))


def thermal_state():
    info = MESSAGE(OBJC.objc_getClass(b'NSProcessInfo'), OBJC.sel_registerName(b'processInfo'))
    return INTEGER_MESSAGE(info, OBJC.sel_registerName(b'thermalState'))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def environment():
    def command(*args):
        return subprocess.run(args, capture_output=True, text=True, timeout=15).stdout.strip()
    battery = command('pmset', '-g', 'batt')
    return {'acPower': "'AC Power'" in battery, 'thermalState': thermal_state(), 'thermal': command('pmset', '-g', 'therm'),
            'swap': command('sysctl', 'vm.swapusage'), 'vm': command('vm_stat'),
            'pressure': command('memory_pressure', '-Q'), 'loadAverage': os.getloadavg()}


# Exact Darwin rusage_info_v4 layout from sys/resource.h. RSS and physical
# footprint are different fields; lifetime high-water marks include startup.
class Usage(ctypes.Structure):
    _fields_ = [('uuid', ctypes.c_uint8 * 16)] + [(name, ctypes.c_uint64) for name in (
        'user system idle wakeups pageins wired resident footprint start exit '
        'child_user child_system child_idle child_wakeups child_pageins child_elapsed '
        'read written qos_default qos_maintenance qos_background qos_utility qos_legacy '
        'qos_initiated qos_interactive billed_system serviced_system writes lifetime_peak '
        'instructions cycles billed_energy serviced_energy interval_peak runnable').split()]


PROC = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
PROC.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
PROC.proc_pid_rusage.restype = ctypes.c_int


def footprint(pid):
    usage = Usage()
    if PROC.proc_pid_rusage(pid, 4, ctypes.byref(usage)) != 0:
        raise OSError(ctypes.get_errno(), 'Cannot sample process footprint')
    return {'bytes': usage.footprint, 'lifetimePeakBytes': usage.lifetime_peak,
            'pageins': usage.pageins, 'readBytes': usage.read, 'writtenBytes': usage.written}


class Sampler:
    def __init__(self, pids):
        self.pids = pids
        self.done = threading.Event()
        self.samples = []
        self.errors = []
        self.thread = threading.Thread(target=self.run, daemon=True)

    def run(self):
        while not self.done.is_set():
            try:
                samples = [footprint(pid) for pid in self.pids]
                self.samples.append({'time': time.monotonic(), 'processes': samples,
                                     'thermalState': thermal_state(), 'sumBytes': sum(s['bytes'] for s in samples)})
            except OSError as error:
                self.errors.append(str(error))
            self.done.wait(0.2)

    def stop(self):
        self.done.set()
        self.thread.join(timeout=5)
        return {'sampleCount': len(self.samples), 'errors': self.errors,
                'maximumThermalState': max((s['thermalState'] for s in self.samples), default=0),
                'observedPeakSumBytes': max((s['sumBytes'] for s in self.samples), default=0),
                'processLifetimePeaks': [max((s['processes'][i]['lifetimePeakBytes']
                    for s in self.samples), default=0) for i in range(len(self.pids))]}


def line(process, timeout=240):
    if not select.select([process.stdout], [], [], timeout)[0]:
        raise TimeoutError('Worker produced no terminal response within the recorded deadline')
    value = process.stdout.readline()
    if not value:
        raise RuntimeError(f'Worker exited before response: {process.poll()}')
    return json.loads(value)


def validate(case, row):
    if 'error' in row:
        return [row['error']]
    errors = []
    expected = case['expected']
    if row['finish'] != 0 or row['bounded']:
        errors.append('Response did not finish normally')
    if 'text' in expected and row['text'].strip() != expected['text']:
        errors.append('Exact requested text differs')
    if 'json' in expected:
        try:
            if json.loads(row['text']) != expected['json']:
                errors.append('Structured Unicode response differs')
        except ValueError:
            errors.append('Structured response is not JSON')
    if 'tool' in expected:
        calls = row['calls']
        if len(calls) != 1 or calls[0]['name'] != expected['tool']:
            errors.append('Wrong tool or call count')
        else:
            arguments = calls[0]['arguments']
            if expected['tool'] == 'propose_table':
                columns = {c['id']: c for c in arguments.get('columns', [])}
                if arguments.get('title') != expected['title'] or arguments.get('meaning') != 'plan':
                    errors.append('Wrong proposed table identity/meaning')
                if columns.get('total', {}).get('formula', '').replace(' ', '') != expected['formula']:
                    errors.append('Missing or changed formula')
                if arguments.get('inputs') != ['request-1'] or len(arguments.get('rows', [])) != 1:
                    errors.append('Wrong proposal lineage/row count')
                elif arguments['rows'][0] != {'item':'Washers','quantity':'3','unit_cost':'2.50'}:
                    errors.append('Requested row values changed')
            else:
                answer = arguments.get('answer', '')
                if arguments.get('basis') != 'evidence' or sorted(arguments.get('citations', [])) != sorted(expected['citations']):
                    errors.append('Comparison omitted its basis or supporting rows')
                if not all(x in answer for x in ['Oak', '3.5', '12.73']) or any(x in answer for x in '$€£'):
                    errors.append('Comparison omitted or invented a requested value')
    return errors


def worker(backend, block, order, repetitions, config_path, config, output):
    binary = ROOT / '.build/release/sevra-inference-performance'
    command = [str(binary), str(config_path)] if backend == 'native' else [
        str(ROOT / '.build/splash-reference/bin/python'), str(ROOT / 'scripts/splash_performance_reference.py'), str(config_path)]
    stderr = (output / f'{block}-{backend}.stderr').open('w')
    before = environment()
    if not before['acPower']:
        raise RuntimeError('AC power required before starting a worker')
    started = time.monotonic()
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr,
        start_new_session=True, env=dict(os.environ, HF_HUB_OFFLINE='1', TOKENIZERS_PARALLELISM='false'))
    rows, ready = [], None
    raw = output / f'{block}-{backend}.json'
    failure = None
    try:
        ready = line(process)
        ready['launchToReadySeconds'] = time.monotonic() - started
        if not ready.get('ready'):
            raise RuntimeError(str(ready))
        save(raw, {'ready': ready, 'before':before, 'rows':rows})
        schedule = [(True, i) for i in order] + [(False, i) for _ in range(repetitions) for i in order]
        for sequence, (warmup, index) in enumerate(schedule):
            sampler = Sampler([process.pid, ready['helperPID']])
            sampler.thread.start()
            try:
                process.stdin.write((json.dumps({'op':'request','case':index})+'\n').encode())
                process.stdin.flush()
                row = line(process)
            finally:
                memory = sampler.stop()
                memory_path = f'{block}-{backend}-{sequence}.memory.json'
                save(output / memory_path, sampler.samples)
                memory['trace'] = memory_path
            row.update(backend=backend, block=block, warmup=warmup, memory=memory, case=index)
            row['errors'] = validate(config['cases'][index], row)
            if 'promptTokens' in row:
                prompt = row.pop('promptTokens')
                row.update(promptTokenCount=len(prompt), promptSHA256=digest(prompt))
                token_path = output / (row['promptSHA256'] + '.prompt.json')
                if not token_path.exists(): save(token_path, prompt)
            rows.append(row)
            save(raw, {'ready':ready,'before':before,'rows':rows})
            print(json.dumps({'backend':backend,'block':block,'id':config['cases'][index]['id'],
                'warmup':warmup,'seconds':row.get('completeSeconds'),'errors':row['errors']}), flush=True)
            if process.poll() is not None or 'error' in row:
                raise RuntimeError('Worker failed; partial results retained')
        process.stdin.write(b'{"op":"close"}\n'); process.stdin.flush()
        closed = line(process, timeout=60)
        if closed.get('closed') is not True:
            raise RuntimeError('Worker did not confirm helper shutdown')
        process.wait(timeout=60)
        if process.returncode:
            raise RuntimeError(f'Worker exited with {process.returncode}')
    except Exception as error:
        failure = str(error)
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try: process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL);process.wait()
        stderr.close()
        result={'ready':ready,'before':before,'after':environment(),'rows':rows,'failure':failure,'returncode':process.returncode}
        save(raw,result)
    return result


def summarize(results, config, protocol, pilot):
    excluded = {}
    for result in results:
        reasons = []
        if not result['before']['acPower'] or not result['after']['acPower']:
            reasons.append('Lost AC power')
        states = [result['before']['thermalState'], result['after']['thermalState']]
        states += [r['memory']['maximumThermalState'] for r in result['rows']]
        if max(states) >= 2:
            reasons.append('Serious or critical thermal pressure')
        if reasons:
            excluded.setdefault(result['block'], []).extend(reasons)
    comparisons = []
    for index, case in enumerate(config['cases']):
        rows = {name:[row for result in results for row in result['rows']
            if row['backend']==name and not row['warmup'] and row.get('case')==index
                and row['block'] not in excluded] for name in ['native','reference']}
        stats = {}
        for name, values in rows.items():
            times=sorted(r['completeSeconds'] for r in values if 'completeSeconds' in r)
            stats[name]={'samples':len(times),'failed':sum(bool(r['errors']) for r in values),
                'medianSeconds':statistics.median(times) if times else None,
                'p95Seconds':times[math.ceil(len(times)*0.95)-1] if times else None,
                'observedPeakSumBytes':max((r['memory']['observedPeakSumBytes'] for r in values),default=0)}
        paired=len(rows['native'])==len(rows['reference']) and bool(rows['native'])
        prompt_equal=paired and all(a.get('promptSHA256') and a.get('promptSHA256')==b.get('promptSHA256') and a.get('generationTokens')==b.get('generationTokens') for a,b in zip(rows['native'],rows['reference']))
        token_equal=paired and all('tokens' in a and a.get('tokens')==b.get('tokens') for a,b in zip(rows['native'],rows['reference']))
        ratios={key: stats['native'][key]/stats['reference'][key] if stats['reference'][key] and stats['native'][key] else None for key in ['medianSeconds','p95Seconds']}
        expected=protocol['blocks']*protocol['repetitionsPerWorkloadPerBlock']
        passed=not pilot and prompt_equal and all(v['samples']==expected and not v['failed'] for v in stats.values()) and ratios['medianSeconds']<=1+protocol['requestGate']['maximumMedianRegression'] and ratios['p95Seconds']<=1+protocol['requestGate']['maximumP95Regression']
        comparisons.append({'id':case['id'],'stats':stats,'ratios':ratios,'identicalPrompts':prompt_equal,'identicalGeneratedTokens':token_equal,'requestGatePassed':passed})
    failed=any(r['failure'] for r in results)
    request_failed=any(row['errors'] or row['memory']['errors'] or row['memory']['sampleCount']==0 for r in results for row in r['rows'])
    return {'pilot':pilot,'workerFailure':failed,'anyRequestOrSamplingFailure':request_failed,
            'excludedPairedBlocks':excluded,'comparisons':comparisons,
            'requestGatePassed':not failed and not request_failed and not excluded and all(c['requestGatePassed'] for c in comparisons),
            'productionAdoption':False}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--models-root',type=Path,required=True)
    parser.add_argument('--pilot',action='store_true')
    args=parser.parse_args()
    args.output=args.output.resolve();args.output.mkdir(parents=True,exist_ok=False)
    protocol=json.loads((ROOT/'integration/performance/protocol.json').read_text())
    workloads=json.loads((ROOT/'integration/performance/workloads.json').read_text())
    dirty=bool(subprocess.check_output(['git','status','--porcelain'],cwd=ROOT))
    if dirty and not args.pilot:
        raise RuntimeError('Commit the tested harness and frozen protocol before qualification')
    for case in workloads['cases']:
        body=case['body']
        assert all(body[key]==value for key,value in {'temperature':0,'top_p':1,'top_k':0,
            'min_p':0,'presence_penalty':0,'frequency_penalty':0,'repetition_penalty':1,'seed':42}.items())
    assert sha(ROOT/'IntegrationTests/Agent/workbook-tools.json')==workloads['toolsSHA256']
    pin=json.loads((ROOT/'integration/splash.json').read_text())
    pack=json.loads((ROOT/'Sources/SevraSplash/Resources/selected-model.json').read_text())
    assembly=(args.models_root/pack['name']).resolve(strict=True)
    grammar=json.loads((ROOT/'.build/llguidance-receipt.json').read_text())
    engine=ROOT/'.build/upstream'/('splash-native-'+pin['release'])/'engine/splash'
    for relative,value in pin['runtime']['files'].items():assert sha(engine.parent.parent/relative)==value,relative
    assert sha(ROOT/grammar['library'])==grammar['librarySHA256']
    own=footprint(os.getpid());assert own['bytes']>0 and own['lifetimePeakBytes']>=own['bytes'],own
    config={'engine':str(engine),'assembly':str(assembly),'grammarLibrary':str(ROOT/grammar['library']),
        'grammarSHA256':grammar['librarySHA256'],'contextTokens':protocol['contextTokens'],
        'memoryBytes':protocol['memoryBytes'],'cases':workloads['cases']}
    config_path=args.output/'config.json';save(config_path,config)
    save(args.output/'identity.json',{'protocol':protocol,'protocolSHA256':sha(ROOT/'integration/performance/protocol.json'),
        'workloadsSHA256':sha(ROOT/'integration/performance/workloads.json'),'engineSHA256':sha(engine),
        'grammarSHA256':grammar['librarySHA256'],'nativeWorkerSHA256':sha(ROOT/'.build/release/sevra-inference-performance'),
        'referenceWorkerSHA256':sha(ROOT/'scripts/splash_performance_reference.py'),
        'coordinatorSHA256':sha(__file__),'baseCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
        'dirty':dirty,
        'machine':subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip(),
        'memoryBytes':int(subprocess.check_output(['sysctl','-n','hw.memsize'],text=True)),
        'os':subprocess.check_output(['sw_vers'],text=True),'startedUTC':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())})
    lock=Path.home()/'Library/Application Support/Sevra/inference.lock'
    lock.parent.mkdir(parents=True,exist_ok=True)
    descriptor=os.open(lock,os.O_CREAT|os.O_RDWR|os.O_NOFOLLOW,0o600)
    try:
        fcntl.flock(descriptor,fcntl.LOCK_EX|fcntl.LOCK_NB)
        results=[]
        count=1 if args.pilot else protocol['blocks']
        for block in range(count):
            order=list(range(len(config['cases'])))
            order=order[block%len(order):]+order[:block%len(order)]
            backends=['native','reference'] if block%2==0 else ['reference','native']
            for backend in backends:
                result=worker(backend,block,order,1 if args.pilot else protocol['repetitionsPerWorkloadPerBlock'],config_path,config,args.output)
                result['block']=block
                results.append(result)
                save(args.output/'summary.json',summarize(results,config,protocol,args.pilot))
                if result['failure']:raise RuntimeError(result['failure'])
        summary=summarize(results,config,protocol,args.pilot);save(args.output/'summary.json',summary)
        print(json.dumps(summary),flush=True)
        if not args.pilot and not summary['requestGatePassed']:
            raise SystemExit(1)
    finally:
        os.close(descriptor)


if __name__=='__main__':main()
