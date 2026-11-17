"""Package only the development catalog; never install or replace the product."""
import json, pathlib, plistlib, shutil, subprocess, sys
from package_app_worker import package
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
    binary=pathlib.Path(sys.argv[1]); app=ROOT/'output/ui-catalog/Sevra UI Catalog.app'
    if app.exists(): shutil.rmtree(app)
    mac=app/'Contents/MacOS'; resources=app/'Contents/Resources'
    mac.mkdir(parents=True);resources.mkdir()
    for src,dst in [('SevraDesktop','Catalog'),('sevra-extract','sevra-extract')]: shutil.copy2(binary/src,mac/dst)
    for bundle in binary.glob('Sevra_*.bundle'): shutil.copytree(bundle,resources/bundle.name)
    shutil.copytree(ROOT/'examples/apps',resources/'CatalogExamples')
    shutil.copytree(ROOT/'examples/catalog/assets',resources/'CatalogAssets')
    commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    dirty=bool(subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip())
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.sevra.ui-catalog','CFBundleName':'Sevra UI Catalog','CFBundleExecutable':'Catalog','CFBundlePackageType':'APPL','CFBundleVersion':'1','CatalogSourceCommit':commit,'CatalogDirty':dirty,'CatalogBinaryIdentity':subprocess.check_output(['dwarfdump','--uuid',str(mac/'Catalog')],text=True).strip(),'CatalogSDK':subprocess.check_output(['xcrun','--show-sdk-version'],text=True).strip(),'NSHighResolutionCapable':True}))
    package(app,binary)
    subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    print(app)
if __name__=='__main__':main()
