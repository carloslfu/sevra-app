"""Six bounded candidate context/memory screening cells, never promotion.

Each worker owns the real lease. Startup status observation is declared and
excludes these runs from performance qualification. Keep rejected cells and
failures; do not grow a running model or retry an unchanged failed task.
"""
import argparse
import json
import os
import re
from pathlib import Path
import signal
import subprocess
from compare_splash_performance import ROOT, Sampler, environment, line, save, sha
from compare_workflow_performance import assert_available
from probe_workflow_prefix import resource_files


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--models-root',type=Path,required=True);p.add_argument('--fixtures',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    gate=json.loads((ROOT/'integration/evidence/2026-11-16-splash-upgrade.json').read_text())
    if not gate.get('behavioralPrerequisitesPassed'):
        save(out/'blocked.json',{'reason':'Candidate behavioral prerequisites have not passed',
            'performanceQualification':False,'productionAdoption':False})
        raise RuntimeError('P3 behavioral gate blocks the context task matrix; startup-only admission is separate')
    protocol=json.loads((ROOT/'integration/performance/context-screen-protocol.json').read_text())
    fixture=json.loads((a.fixtures/'manifest.json').read_text())
    pin=json.loads((ROOT/'integration/splash.json').read_text())
    runtime=ROOT/'.build/upstream'/('splash-native-'+pin['release'])
    for name,digest in pin['runtime']['files'].items():
        if sha(runtime/name)!=digest:raise RuntimeError('Runtime differs from candidate pin')
    binary=ROOT/'.build/debug/sevra-agent-checks';engine=runtime/'engine/splash'
    library=ROOT/'.build/upstream/llguidance-1.8.0/target/release/libllguidance.dylib'
    files=[binary,engine,library,Path(__file__),ROOT/'IntegrationTests/Agent/ContextProfileProbe.swift',ROOT/'integration/performance/context-screen-protocol.json']
    files += [a.fixtures/(name+'.txt') for name in fixture['files']]
    files += list((ROOT/'Sources').rglob('*.swift'))
    files += [p for p in (ROOT/'Sources').rglob('*') if p.is_file() and 'Resources' in p.parts]
    files += list((ROOT/'IntegrationTests/Agent').glob('*.swift'))
    files += [ROOT/'integration/splash.json', ROOT/'Package.resolved', a.fixtures/'manifest.json']
    files += [runtime/name for name in pin['runtime']['files']]
    files += resource_files(binary)
    files += [a.models_root.resolve()/'qwen36-35b-a3b-4bit/model.json']
    frozen={str(f.resolve()):sha(f) for f in files}
    save(out/'identity.json',{'protocol':protocol,'fixtures':fixture,'frozenFiles':frozen,
        'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
        'qualification':False,'startupStatusObservation':True})
    results=[]
    for capacity,memory in protocol['cells']:
        assert_available()
        if any(sha(Path(f))!=v for f,v in frozen.items()):raise RuntimeError('Frozen input changed')
        name=f'{capacity//1024}k-{memory}g';folder=out/name;folder.mkdir()
        config={'modelsRoot':str(a.models_root.resolve()),'contextTokens':capacity,'memoryBytes':memory*1024**3,
            'engine':str(engine),'grammarLibrary':str(library),'fixtures':str(a.fixtures.resolve())}
        save(folder/'config.json',config)
        before = environment()
        physical = int(subprocess.check_output(['sysctl','-n','hw.memsize'],text=True))
        free = re.search(r'free percentage: (\d+)%', before.get('pressure',''))
        if not free or physical * int(free[1]) // 100 < (memory + 8) * 1024**3:
            result={'profile':name,'before':before,'cpuPreflightRefusal':'Unknown or insufficient available headroom estimate','events':[]}
            results.append(result);save(folder/'run.json',result)
            save(out/'summary.json',{'results':results,'performanceQualification':False,'productionAdoption':False})
            print(json.dumps(result),flush=True);continue
        if before.get('thermalState', 99) >= 2:
            result={'profile':name,'before':before,'cpuPreflightRefusal':'Serious or unknown thermal state','events':[]}
            results.append(result);save(folder/'run.json',result)
            save(out/'summary.json',{'results':results,'performanceQualification':False,'productionAdoption':False})
            raise RuntimeError('Thermal safety stop before helper launch; remaining cells are untested')
        stderr=(folder/'stderr.log').open('w')
        child=subprocess.Popen([str(binary),'--context-profile',str(folder/'config.json'),str(folder/'evidence')],
            stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=stderr,start_new_session=True)
        result={'profile':name,'before':before,'events':[],'failure':None}
        sampler=None
        try:
            while True:
                row=line(child,timeout=400);result['events'].append(row);save(folder/'run.json',result)
                if row.get('event')=='admission':
                    status=row['status'];sampler=Sampler([int(status['probeHostPID']),int(status['probeHelperPID'])]);sampler.thread.start()
                if row.get('event')=='complete':
                    if row.get('fatal'):result['failure']=row['fatal']
                    break
                if 'id'in row: print(json.dumps({'profile':name,**{k:row.get(k) for k in ['id','admitted','passed','promptTokens','seconds','error']}}),flush=True)
            child.wait(timeout=15);result['returncode']=child.returncode
            if child.returncode:raise RuntimeError('Profile worker failed')
        except Exception as error:
            result['failure']=str(error)
        finally:
            if sampler:
                result['memory']=sampler.stop();save(folder/'memory.json',sampler.samples)
            if child.poll()is None:
                os.killpg(child.pid,signal.SIGTERM)
                try:child.wait(timeout=5)
                except subprocess.TimeoutExpired:os.killpg(child.pid,signal.SIGKILL);child.wait()
            stderr.close();result['after']=environment();save(folder/'run.json',result)
            results.append(result)
            save(out/'summary.json',{'results':results,'performanceQualification':False,'productionAdoption':False})
            assert_available()
            if any(sha(Path(f))!=v for f,v in frozen.items()):raise RuntimeError('Frozen input changed during screening')
        print(json.dumps({'profile':name,'completed':result.get('returncode')==0,'failure':result['failure']}),flush=True)
        if result['failure']:
            raise RuntimeError('Profile worker failed; retain remaining cells as untested')
        if any(e.get('criticalPressureStop') for e in result['events']):
            raise RuntimeError('Critical memory pressure stopped screening; no automatic restart')
        if any(e.get('seriousThermalStop') for e in result['events']) or result.get('memory',{}).get('maximumThermalState',0)>=2:
            raise RuntimeError('Thermal safety stop; retain the remaining cells as untested')


if __name__=='__main__':main()
