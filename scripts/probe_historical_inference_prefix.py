"""Replay frozen historical input envelopes on 1.6.1, R/N/N/R.

Inputs (including earlier cache history) stay fixed. These are diagnostic
requests, not live jobs or performance qualification. Keep every attempt.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import signal
import subprocess
from compare_splash_performance import ROOT, Sampler, environment, line, save, sha
from compare_workflow_performance import assert_available


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--inputs',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--diagnostic-masks',action='store_true')
    a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    cases=json.loads((a.inputs/'cases.json').read_text())
    original=ROOT/'.build/workflow-performance/current-cohort2'
    config=json.loads((ROOT/'.build/inference-context-20261116/p3-current-prefix/0-reference/config.json').read_text())
    config.update(cases=cases,workerOwnsLease=True,workflowQualification=True,diagnosticMasks=a.diagnostic_masks)
    order=['reference','native'] if a.diagnostic_masks else ['reference','native','native','reference']
    binary=ROOT/'.build/debug/sevra-inference-performance'
    files=[binary,Path(config['engine']),Path(config['grammarLibrary']),Path(config['referenceScript']),Path(__file__),a.inputs/'cases.json']
    frozen={str(f.resolve()):sha(f) for f in files}
    save(out/'identity.json',{'scope':'Historical fixed-input replay; six requests including complete prior cache history',
        'order':order,'diagnosticMasks':a.diagnostic_masks,'frozenFiles':frozen,'config':config,
        'inputIdentity':json.loads((a.inputs/'identity.json').read_text()),'performanceQualification':False})
    results=[]
    for i,backend in enumerate(order):
        assert_available()
        if any(sha(Path(f))!=v for f,v in frozen.items()):raise RuntimeError('Replay identity changed')
        folder=out/(str(i)+'-'+backend);folder.mkdir();config_path=folder/'config.json';save(config_path,config)
        command=[str(binary),str(config_path)] if backend=='native' else [config['python'],config['referenceScript'],str(config_path)]
        stderr=(folder/'stderr.log').open('w');process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=stderr,start_new_session=True)
        result={'backend':backend,'before':environment(),'rows':[],'closed':False,'failure':None}
        try:
            result['ready']=ready=line(process,timeout=400)
            if not ready.get('ready'):raise RuntimeError('Startup failed')
            for index,case in enumerate(cases):
                sampler=Sampler([ready['pid'],ready['helperPID']]);sampler.thread.start()
                try:
                    process.stdin.write((json.dumps({'case':index})+'\n').encode());process.stdin.flush()
                    row=line(process,timeout=240)
                finally:memory=sampler.stop()
                row['memory']=memory;save(folder/(str(index)+'.memory.json'),sampler.samples)
                if 'error' in row:raise RuntimeError(row['error'])
                row['historicalPromptExact']=row['promptTokens']==case['expectedPrompt'] and row['generationTokens']==case['expectedGenerationTokens']
                old=base64.b64decode(json.loads((original/(case['historicalRequestSHA256']+'.request.json')).read_text())['base64'])
                new=base64.b64decode(row['requestFrame'])
                # v11 and v13 Request payloads are identical; only the protocol version changes.
                row['historicalWireSemanticsExact']=old[:4]+old[6:]==new[:4]+new[6:]
                result['rows'].append(row);save(folder/'result.json',result)
                if not row['historicalPromptExact'] or not row['historicalWireSemanticsExact']:raise RuntimeError('Input mismatch before interpreting replay')
                print(json.dumps({'run':i,'backend':backend,'case':case['id'],'finish':row['finish'],'tokens':len(row['tokens'])}),flush=True)
            process.stdin.write(b'{"op":"close"}\n');process.stdin.flush();result['closed']=line(process,timeout=30);process.wait(timeout=10)
            result['returncode']=process.returncode
            assert result['closed']=={'closed':True} and process.returncode==0
            assert_available()
        except BaseException as e:
            result['failure']=str(e);raise
        finally:
            if process.poll() is None:
                os.killpg(process.pid,signal.SIGTERM)
                try:process.wait(timeout=5)
                except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
            result['after']=environment();save(folder/'result.json',result);stderr.close()
            results.append(result)
            summary={'completedWorkers':len(results),'failures':[r['failure'] for r in results],
                'performanceQualification':False,'productionAdoption':False}
            if len(results)==4 and not any(summary['failures']):
                def compare(x,y):
                    return [{'case':c['id'],'sameRequest':u['requestFrame']==v['requestFrame'],'sameTokens':u['tokens']==v['tokens'],
                        'firstDifference':next((n for n,(a,b) in enumerate(zip(u['tokens'],v['tokens'])) if a!=b),None),
                        'lengths':[len(u['tokens']),len(v['tokens'])]} for c,u,v in zip(cases,results[x]['rows'],results[y]['rows'])]
                summary.update(withinNative=compare(1,2),withinReference=compare(0,3),paired=[compare(0,1),compare(3,2)])
            if a.diagnostic_masks and len(results)==2 and not any(summary['failures']):
                comparisons=[]
                for c,u,v in zip(cases,results[0]['rows'],results[1]['rows']):
                    def masks(row):
                        result={}
                        for m in row.get('maskTrace',[]):
                            key=(m['tokenCount'],m['prefixSHA256'])
                            if key in result and result[key]!=m['maskSHA256']:
                                raise RuntimeError('One prefix produced inconsistent masks')
                            result[key]=m['maskSHA256']
                        return result
                    left,right=masks(u),masks(v);common=set(left)&set(right)
                    comparisons.append({'case':c['id'],'commonPrefixes':len(common),
                        'mismatches':sum(left[k]!=right[k] for k in common),
                        'referencePrefixes':len(left),'nativePrefixes':len(right),
                        'identicalGeneratedTokens':u['tokens']==v['tokens']})
                summary['maskComparison']=comparisons
                summary['scope']='Instrumented diagnostic only; cannot clear uninstrumented repeatability or qualify timing'
            save(out/'summary.json',summary)


if __name__=='__main__':main()
