"""Real CLI writers, coherent export, stale writes, duplicate retries and recovery."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse, fcntl, json, os, signal, subprocess, tempfile, time
root=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cli',type=Path,default=root/'output/native/bin/sevra')
cli=parser.parse_args().cli.resolve()
def run(*args,success=True):
    r=subprocess.run([str(cli),*map(str,args)],text=True,capture_output=True,timeout=120)
    assert (r.returncode==0)==success,r.stdout+r.stderr
    data=json.loads(r.stdout if success else r.stderr)
    assert data['ok']==success,data
    return data.get('result',data)
with tempfile.TemporaryDirectory(prefix='sevra-concurrency-') as temporary:
    folder=Path(temporary);book=folder/'Active.sevra';archive=folder/'Shared.sevraz'
    run('demo',book)
    revision=run('inspect',book)['revision'];commits=len(run('commits',book,1000))
    def add(i):
        return run('add',book,json.dumps({'title':f'Concurrent {i}','text':f'Independent observation {i}', 'status':'accepted','token':f'writer-{i}'}))
    with ThreadPoolExecutor(max_workers=4) as pool:
        work=[pool.submit(add,i) for i in range(30)]
        export=pool.submit(run,'export',book,archive)
        results=[job.result() for job in work];export.result()
    assert len({r['id'] for r in results})==30
    # A reported write must be in the file the next process opens, once each.
    assert [run('read',book,r['id'])['item']['title'] for r in results]==[f'Concurrent {i}' for i in range(30)]
    assert run('inspect',book)['revision']==revision+30 and len(run('commits',book,1000))==commits+30
    assert add(0)['id']==results[0]['id']
    assert run('inspect',book)['revision']==revision+30
    csv=folder/'resume.csv';csv.write_text('part,price\nbolt,2.40\nwasher,1.25\n')
    imported=run('import',book,csv,'--role','values')
    source=imported['source']['id'];table_id=imported['intake']['datasetIDs'][0]
    run('resume-intake',book,source)
    run('resume-intake',book,source)
    assert [t['id'] for t in run('tables',book)].count(table_id)==1
    assert len(run('rows',book,table_id))==2
    assert run('verify',book)['ok']
    reopened=folder/'Reopened.sevra';run('open-archive',archive,reopened)
    assert run('verify',reopened)['ok']
    assert run('balance',reopened,'brass bolts')['quantity']=='18'
    table=run('tables',book)[0];row=run('rows',book,table['id'])[0]
    failure=run('edit-row',book,row['id'],json.dumps(row['data']),0,success=False)
    assert failure['error']['code']=='stale_revision',failure
    failure=run('edit-row',book,row['id'],json.dumps(row['data']),'stale',success=False)
    assert failure['error']['code']=='usage',failure
    # An open waiting on another process stops at once, and a kill during export leaves no copy.
    lock=os.open(book/'.write-lock',os.O_RDWR);fcntl.flock(lock,fcntl.LOCK_EX)
    waiting=subprocess.Popen([str(cli),'inspect',str(book)],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    time.sleep(1);waiting.send_signal(signal.SIGINT)
    _,stderr=waiting.communicate(timeout=5)
    assert waiting.returncode!=0 and json.loads(stderr)['error']['code']=='cancelled',stderr
    os.close(lock)
    large=folder/'Large.bin';large.write_bytes(os.urandom(64_000_000));run('import',book,large)
    target=folder/'stopped';target.mkdir()
    # Foundation takes the temporary folder from the system, whatever TMPDIR says.
    system=Path(subprocess.check_output(['getconf','DARWIN_USER_TEMP_DIR'],text=True).strip())
    copies=lambda:set(system.glob('sevra-export-*'))
    before=copies()
    for number in [signal.SIGINT,signal.SIGTERM,signal.SIGHUP]:
        process=subprocess.Popen([str(cli),'export',str(book),str(target/'Stopped.sevraz')],text=True,
                                 stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        deadline=time.monotonic()+60
        while process.poll() is None and time.monotonic()<deadline and not list(target.iterdir()):
            time.sleep(0.005)
        process.send_signal(number)
        _,stderr=process.communicate(timeout=60)
        assert process.returncode!=0 and json.loads(stderr)['error']['code']=='cancelled',stderr
        assert not list(target.iterdir()) and copies()==before
    print(json.dumps({'crossProcessIntakeRetry':True,'concurrentWriters':30,'snapshotVerified':True,'idempotentRetry':True,'staleWriteRefused':True,'inventoryPreserved':True}))
