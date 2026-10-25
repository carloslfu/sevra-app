"""Opt-in real >4 GiB asset/ZIP64 round-trip, using temporary synthetic bytes."""
import json, os, re, resource, subprocess, tempfile, time
from pathlib import Path
root=Path(__file__).resolve().parent.parent
cli=root/"output/bin/sevra"
def run(*args):
    start=time.monotonic()
    result=subprocess.run(["/usr/bin/time","-l",str(cli),*map(str,args)],capture_output=True,text=True,check=True)
    data=json.loads(result.stdout)
    assert data["ok"],data
    peak=int(re.search(r"(\d+)\s+maximum resident set size",result.stderr).group(1))
    print(json.dumps({"operation":args[0],"seconds":time.monotonic()-start,"peakRSSBytes":peak}),flush=True)
    return data["result"]
with tempfile.TemporaryDirectory(prefix="sevra-large-assets-") as folder:
    directory=Path(folder)
    source=directory/"synthetic-large.mp4"
    size=2**32+1_048_576
    with source.open("wb") as file:
        file.write(b"SEVRA SYNTHETIC BYTES, NOT PLAYABLE VIDEO\n")
        file.seek(size-1);file.write(b"\0")
    workbook=directory/"Large.sevra"
    run("create",workbook,"Large-asset fixture")
    imported=run("import",workbook,source)
    source.unlink()
    assert run("verify",workbook)["ok"]
    archive=directory/"Large.sevraz"
    run("export",workbook,archive)
    reopened=directory/"Reopened.sevra"
    run("open-archive",archive,reopened)
    assert run("verify",reopened)["ok"]
    assert archive.stat().st_size>2**32
    print(json.dumps({"assetBytes":size,"archiveBytes":archive.stat().st_size,"peakChildRSSBytes":resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss,"result":"passed"}))
