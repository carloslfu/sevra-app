"""Physical-Mac resource check with source-build access denied, without model weights."""
from pathlib import Path
import json, subprocess
root=Path(__file__).resolve().parent.parent
profile='(version 1) (allow default) (deny file-read* (subpath '+json.dumps(str(root/'.build'))+'))'
for executable,args in [(root/'output/bin/sevra',['check-resources']),(root/'output/Sevra.app/Contents/MacOS/Sevra',['--check-resources'])]:
    result=subprocess.run(['sandbox-exec','-p',profile,str(executable),*args],capture_output=True,text=True,timeout=45)
    assert result.returncode==0,result.stdout+result.stderr
    data=json.loads(result.stdout)
    value=data.get('result',data)
    assert value['tokenizerResources'] and value['metalLibrary'] and value['kernelCount']>0,value
    print(json.dumps({'product':executable.name,'buildTreeDenied':True,**value}))
