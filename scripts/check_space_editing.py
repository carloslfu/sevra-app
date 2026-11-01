import json,subprocess,tempfile
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import sys
cli=str(Path(sys.argv[1]).resolve(strict=True))
def run(*a,ok=True):
 r=subprocess.run([cli,*map(str,a)],capture_output=True,text=True,timeout=120)
 assert (r.returncode==0)==ok,r.stdout+r.stderr
 v=json.loads(r.stdout if ok else r.stderr)
 return v.get('result',v)
with tempfile.TemporaryDirectory(prefix='sevra-layout-') as d:
 b=Path(d)/'Layouts.sevra';run('create',b)
 initial=next(s for s in run('spaces',b) if s['id']=='home')
 assert [x['id'] for x in initial['definition']['components']]==['input','reviews','shortcuts','tables','intake','recent']
 def write(n):
  r=subprocess.run([cli,'space-edit',str(b),'home','1',json.dumps([{'operation':'rename','title':f'Writer {n}'}]),f'writer-{n}'],capture_output=True,text=True,timeout=60)
  return r
 with ThreadPoolExecutor(2) as pool:r=list(pool.map(write,range(2)))
 assert sum(x.returncode==0 for x in r)==1,[x.stdout+x.stderr for x in r]
 assert next(json.loads(x.stderr)['error']['code'] for x in r if x.returncode)=='space_conflict' 
 history=run('space-history',b,'home');assert [x['version'] for x in history]==[2,1]
 current=next(s for s in run('spaces',b) if s['id']=='home')
 edits=json.dumps([{'operation':'remove','componentID':'recent'},{'operation':'move','componentID':'tables','beforeID':'input'}])
 saved=run('space-edit',b,'home','2',edits,'once');assert saved['version']==3
 assert run('space-edit',b,'home','2',edits,'once')==saved
 assert run('space-edit',b,'home','1',edits,ok=False)['error']['code']=='space_conflict'
 restored=run('space-restore',b,'home','1','3','restore');assert restored['version']==4
 assert restored['definition']==initial['definition']
 run('reconstruct',b,Path(d)/'Replay.sevra')
 assert run('spaces',Path(d)/'Replay.sevra')==run('spaces',b)
 assert run('verify',b)['ok']
 print(json.dumps({'concurrentWriters':2,'successfulWrites':1,'staleRefusal':True,'exactRetry':True,'historyVersions':[4,3,2,1],'restoredDefault':True,'inertReconstruction':True}))
