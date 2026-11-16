"""Reconstruct historical W1/D9 request envelopes without running inference.

The original frozen host consumes recorded historical replies as a fixture. The
result is only input reconstruction, never a fresh success/performance result.
Every reconstructed prompt is independently checked against the historical token
array before any candidate engine replay can use it.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def peer(config):
    config = json.loads(Path(config).read_text())
    root = Path(config['reconstructionOutput'])
    original = json.loads((Path(config['historicalRoot']) / '9-native.json').read_text())
    jobs = [original['ready']['prime']] + original['rows'][:2]
    pairs = [(j,r,s) for j in jobs for r,s in zip(j['trace']['requests'],j['trace']['responses'])]
    print(json.dumps({'ready':True,'helperPID':os.getpid()}),flush=True)
    index = 0
    for line in sys.stdin:
        command = json.loads(line)
        if command.get('op') == 'close':
            print(json.dumps({'closed':True}),flush=True)
            return
        job, request, response = pairs[index]
        (root / f'{index}.body.json').write_text(json.dumps(command['body'],indent=2)+'\n')
        old = Path(config['historicalRoot'])
        tokens = json.loads((old / (request['promptSHA256']+'.prompt.json')).read_text())
        row = dict(promptTokens=tokens,generationTokens=request['generationTokens'],tokens=request['tokens'],
            requestFrame=json.loads((old/(request['requestSHA256']+'.request.json')).read_text())['base64'],
            finish=0,bounded=False,text=response['text'],reasoning=response['reasoning'],
            calls=[{'name':v['name'],'arguments':v['arguments']} for v in response['calls']],
            matchedPromptTokens=request['metrics']['matchedPromptTokens'],
            deduplicatedKVTokens=request['metrics']['deduplicatedKVTokens'],
            diagnosticRequestCacheIsolation=False,completeSeconds=0,firstTokenSeconds=0,prefillSeconds=0,decodeSeconds=0)
        print(json.dumps(row),flush=True)
        index += 1
    raise RuntimeError('Reconstruction ended before close')


def main():
    if len(sys.argv)==2 and sys.argv[1].endswith('config.json'):
        peer(sys.argv[1]);return
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    historical=ROOT/'.build/workflow-performance/current-cohort2'
    identity=json.loads((historical/'identity.json').read_text())
    original=ROOT/'.build/workflow-performance/frozen-0e45190-sevra-workflow-performance'
    assert sha(original)==identity['workerSHA256']
    binary=out/'sevra-workflow-performance';shutil.copy2(original,binary)
    resources={
      'Sevra_SevraSplash.bundle/selected-model.json':'Sources/SevraSplash/Resources/selected-model.json',
      'Sevra_SevraSplashText.bundle/template-patch.json':'Sources/SevraSplashText/Resources/template-patch.json',
      'Sevra_SevraSplashGrammar.bundle/json-slices.json':'Sources/SevraSplashGrammar/Resources/json-slices.json'}
    for target,source in resources.items():
        data=subprocess.check_output(['git','show',identity['baseCommit']+':'+source],cwd=ROOT)
        path=out/target;path.parent.mkdir(exist_ok=True);path.write_bytes(data)
    config=json.loads((historical/'config.json').read_text())
    config.update(python=sys.executable,referenceScript=str(Path(__file__).resolve()),
        historicalRoot=str(historical),reconstructionOutput=str(out),configPath=str(out/'config.json'))
    (out/'config.json').write_text(json.dumps(config,indent=2)+'\n')
    with (out/'host.stdout.jsonl').open('w') as stdout, (out/'host.stderr').open('w') as stderr:
        result=subprocess.run([str(binary),str(out/'config.json'),'reference'],cwd=ROOT,text=True,
            input='{"id":"formula_review","seed":9001}\n{"id":"inventory_evidence","seed":9002}\n{"op":"close"}\n',
            stdout=stdout,stderr=stderr,timeout=120)
    assert result.returncode==0, 'Frozen host reconstruction failed; retain its outputs'
    rows=[json.loads(v) for v in (out/'host.stdout.jsonl').read_text().splitlines()]
    assert rows[0]['ready'] and rows[-1]=={'closed':True}
    assert all(not r['errors'] for r in [rows[0]['prime']]+rows[1:-1])
    record=json.loads((historical/'9-native.json').read_text())
    jobs=[record['ready']['prime']]+record['rows'][:2]
    cases=[]
    for j in jobs:
        for step,request in enumerate(j['trace']['requests']):
            index=len(cases);body=json.loads((out/f'{index}.body.json').read_text())
            cases.append(dict(id=j['id']+'-'+str(step+1),body=body,
                expectedPrompt=json.loads((historical/(request['promptSHA256']+'.prompt.json')).read_text()),
                expectedGenerationTokens=request['generationTokens'],historicalRequestSHA256=request['requestSHA256']))
    (out/'cases.json').write_text(json.dumps(cases,indent=2)+'\n')
    (out/'identity.json').write_text(json.dumps(dict(scope='CPU reconstruction only; no model outputs evaluated',
        sourceCommit=identity['baseCommit'],workerSHA256=sha(original),
        historicalResultSHA256=sha(historical/'9-native.json'),casesSHA256=sha(out/'cases.json'),
        reconstructionScriptSHA256=sha(__file__),cases=len(cases)),indent=2)+'\n')
    print(json.dumps({'reconstructedCases':len(cases),'modelExecution':False}))


if __name__=='__main__':main()
