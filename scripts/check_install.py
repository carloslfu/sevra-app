"""Isolated install, update, conflict refusal, standalone CLI and uninstall."""
from pathlib import Path
import argparse, hashlib, json, os, plistlib, subprocess, tempfile
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("--native", action="store_true")
options=parser.parse_args()
name="Sevra Native Preview" if options.native else "Sevra"
mode=["--native"] if options.native else []
root=Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="sevra-install-check-") as path:
    folder=Path(path)
    env={**os.environ,"SEVRA_APP_INSTALL_DIR":str(folder/"Applications"),"SEVRA_CLI_INSTALL_DIR":str(folder/"bin"),"SEVRA_UNINSTALL_TRASH_DIR":str(folder/"Trash")}
    def script(name,*args,success=True):
        result=subprocess.run([str(root/"scripts"/name),*args],env=env,capture_output=True,text=True,timeout=300)
        assert (result.returncode==0)==success,result.stdout+result.stderr
        return result
    # Each product takes the CLI link from the other and leaves that app alone.
    other=folder/"Applications"/("Sevra.app" if options.native else "Sevra Native Preview.app")
    (other/"Contents/CLI").mkdir(parents=True)
    (other/"Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier":"com.sevra.workbooks" if options.native else "com.sevra.workbooks.native-preview"}))
    (other/"Contents/CLI/sevra").write_text("preserved sentinel")
    (folder/"bin").mkdir()
    (folder/"bin/sevra").symlink_to(other/"Contents/CLI/sevra")
    script("install.sh",*mode,"--no-build")
    app = folder/"Applications"/(name+".app")/"Contents"
    info = plistlib.loads((app/"Info.plist").read_bytes())
    assert info["CFBundleIconFile"] == "Sevra.icns"
    assert hashlib.sha256((app/"Resources/Sevra.icns").read_bytes()).hexdigest() == "b28f2df8e40cafc2e89fb3ae5a0e361b5470851d833495df9b3dd4ca0395471d"
    assert {p.name for p in (app/"Resources").glob("*.bundle")} == {
        "swift-transformers_Hub.bundle", "ZIPFoundation_ZIPFoundation.bundle", "swift-crypto_Crypto.bundle"} | ({
        "Sevra_SevraSplash.bundle", "Sevra_SevraSplashText.bundle", "Sevra_SevraSplashGrammar.bundle"} if options.native else set())
    cli=folder/"bin/sevra"
    def command(*args):
        result=subprocess.run([str(cli),*map(str,args)],cwd=folder,capture_output=True,text=True,check=True,timeout=120)
        value=json.loads(result.stdout)
        assert value["ok"],value
        return value["result"]
    assert command("version")["version"]=="0.1.0-dev"
    assert (other/"Contents/CLI/sevra").read_text()=="preserved sentinel"
    assert cli.readlink()==app/"CLI/sevra"
    resources = command("check-resources","--paths-only")
    assert resources["extractionWorker"]
    assert resources["runtimeDigests"] and resources["grammarLibrary"] if options.native else resources["tokenizerResources"]
    if options.native:
        manifest=json.loads((app/"Resources/native-runtime.json").read_text())
        for filename,digest in manifest["engineFiles"].items():
            assert hashlib.sha256((app/"Helpers/Splash"/filename).read_bytes()).hexdigest()==digest
            assert hashlib.sha256((app/"CLI/NativeRuntime/engine"/filename).read_bytes()).hexdigest()==digest
    original = folder / "Installed extraction.txt"
    original.write_text("Installed source invoice 1042")
    workbook=folder/"Owned.sevra"
    command("demo",workbook)
    imported = command("import", workbook, original)
    assert imported["intake"]["sourceID"] == imported["source"]["id"]
    assert command("tool", workbook, "read", json.dumps({"id": imported["source"]["id"]}))["extraction"]["state"] == "ready"
    assert command("balance",workbook,"brass bolts")["quantity"]=="18"
    script("install.sh",*mode,"--no-build")
    assert command("verify",workbook)["ok"]
    script("uninstall.sh",*mode)
    assert workbook.exists() and not cli.exists()
    assert list((folder/"Trash").glob(name+"-*.app"))
    (folder/"bin/sevra").write_text("unrelated sentinel")
    script("install.sh",*mode,"--no-build",success=False)
    assert (folder/"bin/sevra").read_text()=="unrelated sentinel"
    assert not (folder/"Applications"/(name+".app")).exists()
    cli.unlink()
    (other/"Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier":"unrelated.app"}))
    cli.symlink_to(other/"Contents/CLI/sevra")
    script("install.sh",*mode,"--no-build",success=False)
    assert cli.readlink()==other/"Contents/CLI/sevra"
    skill_env={**env,"SEVRA_SKILL_ROOT":str(folder/"skills")}
    installed=subprocess.run([str(root/"scripts/install_skill.sh"),"codex"],env=skill_env,capture_output=True,text=True)
    assert installed.returncode==0,installed.stderr
    skill=(folder/"skills/sevra/SKILL.md").read_bytes()
    conflict=subprocess.run([str(root/"scripts/install_skill.sh"),"claude"],env=skill_env,capture_output=True,text=True)
    assert conflict.returncode!=0 and (folder/"skills/sevra/SKILL.md").read_bytes()==skill
    print(json.dumps({"native":options.native,"ownedCLITransition":True,"skillInstallAndConflict":True,"installed":True,"updated":True,"standaloneCLI":True,"uninstalled":True,"workbookPreserved":True,"unrelatedCLIProtected":True}))
