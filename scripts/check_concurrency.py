"""Real CLI writers, coherent export, stale writes, duplicate retries and recovery."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json, subprocess, tempfile
root=Path(__file__).resolve().parent.parent
cli=root/'output/bin/sevra'
def run(*args,success=True):
    r=subprocess.run([str(cli),*map(str,args)],text=True,capture_output=True)
    assert (r.returncode==0)==success,r.stdout+r.stderr
    data=json.loads(r.stdout if success else r.stderr)
    assert data['ok']==success,data
    return data.get('result',data)
with tempfile.TemporaryDirectory(prefix='sevra-concurrency-') as temporary:
    folder=Path(temporary);book=folder/'Active.sevra';archive=folder/'Shared.sevraz'
    run('demo',book)
    def add(i):
        return run('add',book,json.dumps({'title':f'Concurrent {i}','text':f'Independent observation {i}', 'status':'accepted','token':f'writer-{i}'}))
    with ThreadPoolExecutor(max_workers=4) as pool:
        work=[pool.submit(add,i) for i in range(30)]
        export=pool.submit(run,'export',book,archive)
        results=[job.result() for job in work];export.result()
    assert len({r['id'] for r in results})==30
    assert add(0)['id']==results[0]['id']
    assert run('verify',book)['ok']
    reopened=folder/'Reopened.sevra';run('open-archive',archive,reopened)
    assert run('verify',reopened)['ok']
    assert run('balance',reopened,'brass bolts')['quantity']=='18'
    table=run('tables',book)[0];row=run('rows',book,table['id'])[0]
    failure=run('edit-row',book,row['id'],json.dumps(row['data']),0,success=False)
    assert failure['error']['code']=='stale_revision',failure
    print(json.dumps({'concurrentWriters':30,'snapshotVerified':True,'idempotentRetry':True,'staleWriteRefused':True,'inventoryPreserved':True}))
