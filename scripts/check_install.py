"""Isolated install, update, conflict refusal, standalone CLI and uninstall."""
from pathlib import Path
import hashlib, json, os, plistlib, subprocess, tempfile
root=Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="sevra-install-check-") as path:
    folder=Path(path)
    env={**os.environ,"SEVRA_APP_INSTALL_DIR":str(folder/"Applications"),"SEVRA_CLI_INSTALL_DIR":str(folder/"bin"),"SEVRA_UNINSTALL_TRASH_DIR":str(folder/"Trash")}
    def script(name,*args,success=True):
        result=subprocess.run([str(root/"scripts"/name),*args],env=env,capture_output=True,text=True)
        assert (result.returncode==0)==success,result.stdout+result.stderr
        return result
    script("install.sh","--no-build")
    app = folder/"Applications/Sevra.app/Contents"
    info = plistlib.loads((app/"Info.plist").read_bytes())
    assert info["CFBundleIconFile"] == "Sevra.icns"
    assert hashlib.sha256((app/"Resources/Sevra.icns").read_bytes()).hexdigest() == "b28f2df8e40cafc2e89fb3ae5a0e361b5470851d833495df9b3dd4ca0395471d"
    assert {p.name for p in (app/"Resources").glob("*.bundle")} == {
        "swift-transformers_Hub.bundle", "ZIPFoundation_ZIPFoundation.bundle", "swift-crypto_Crypto.bundle"}
    cli=folder/"bin/sevra"
    def command(*args):
        result=subprocess.run([str(cli),*map(str,args)],cwd=folder,capture_output=True,text=True,check=True)
        value=json.loads(result.stdout)
        assert value["ok"],value
        return value["result"]
    assert command("version")["version"]=="0.1.0-dev"
    assert command("check-resources","--paths-only")["tokenizerResources"]
    workbook=folder/"Owned.sevra"
    command("demo",workbook)
    assert command("balance",workbook,"brass bolts")["quantity"]=="18"
    script("install.sh","--no-build")
    assert command("verify",workbook)["ok"]
    script("uninstall.sh")
    assert workbook.exists() and not cli.exists()
    assert list((folder/"Trash").glob("Sevra-*.app"))
    (folder/"bin/sevra").write_text("unrelated sentinel")
    script("install.sh","--no-build",success=False)
    assert (folder/"bin/sevra").read_text()=="unrelated sentinel"
    assert not (folder/"Applications/Sevra.app").exists()
    skill_env={**env,"SEVRA_SKILL_ROOT":str(folder/"skills")}
    installed=subprocess.run([str(root/"scripts/install_skill.sh"),"codex"],env=skill_env,capture_output=True,text=True)
    assert installed.returncode==0,installed.stderr
    skill=(folder/"skills/sevra/SKILL.md").read_bytes()
    conflict=subprocess.run([str(root/"scripts/install_skill.sh"),"claude"],env=skill_env,capture_output=True,text=True)
    assert conflict.returncode!=0 and (folder/"skills/sevra/SKILL.md").read_bytes()==skill
    print(json.dumps({"skillInstallAndConflict":True,"installed":True,"updated":True,"standaloneCLI":True,"uninstalled":True,"workbookPreserved":True,"unrelatedCLIProtected":True}))
