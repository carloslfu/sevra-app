"""Collect dependency notices into the application; never fetch at runtime."""
from pathlib import Path
import shutil
root=Path(__file__).resolve().parent.parent
out=root/"output/Sevra.app/Contents/Resources/Licenses"
out.mkdir(parents=True,exist_ok=True)
shutil.copy2(root/"LICENSE",out/"Sevra.txt")
for package in (root/".build/checkouts").iterdir():
    for source in package.rglob("*"):
        if not source.is_file() or ".git" in source.parts:
            continue
        if source.name.lower().split(".")[0] not in {"license","copying","notice","copyright","licence"}:
            continue
        target=out/package.name/source.relative_to(package)
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(source,target)
shutil.copy2(root/"Package.resolved",out/"Package.resolved")
