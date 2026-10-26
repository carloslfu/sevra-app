#!/usr/bin/env python3
"""Fetch a pinned development reference; extract only native shipping candidates."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
PIN = json.loads((ROOT / "integration/splash.json").read_text())
CACHE = ROOT / ".build/upstream"


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    source = CACHE / ("splash-" + PIN["release"])
    if not source.exists():
        subprocess.run(["git", "clone", "--depth", "1", "--branch", PIN["release"],
                        PIN["source"], str(source)], check=True)
    commit = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if commit != PIN["commit"]:
        raise RuntimeError("Source commit does not match the pin; preserve this checkout for inspection.")
    if subprocess.check_output(["git", "-C", str(source), "status", "--porcelain"]):
        raise RuntimeError("Upstream reference has local changes; use a clean reference.")
    asset = PIN["runtime"]
    archive = CACHE / asset["url"].rsplit("/", 1)[1]
    if not archive.exists():
        partial = archive.with_suffix(archive.suffix + ".partial")
        try:
            with urllib.request.urlopen(asset["url"], timeout=60) as response, partial.open("wb") as out:
                received = 0
                while chunk := response.read(1024 * 1024):
                    received += len(chunk)
                    if received > asset["archiveBytes"]:
                        raise RuntimeError("Runtime download exceeds pinned size.")
                    out.write(chunk)
            if partial.stat().st_size != asset["archiveBytes"] or digest(partial) != asset["sha256"]:
                raise RuntimeError("Downloaded archive identity does not match the pin.")
            partial.replace(archive)
        finally:
            partial.unlink(missing_ok=True)
    if archive.stat().st_size != asset["archiveBytes"] or digest(archive) != asset["sha256"]:
        raise RuntimeError("Cached runtime archive identity does not match the pin.")

    # Whitelist individual regular members. Never unpack Python, links or arbitrary paths.
    prefix = archive.name.removesuffix(".tar.gz") + "/"
    wanted = ["engine/splash", "engine/splash.metallib", "engine/host-step.metallib",
              "LICENSE", "THIRD_PARTY_NOTICES"]
    destination = CACHE / ("splash-native-" + PIN["release"])
    with tempfile.TemporaryDirectory(dir=CACHE, prefix="native-stage-") as temp:
        stage = Path(temp)
        hashes = {}
        with tarfile.open(archive, "r:gz") as tar:
            members = {n: [] for n in wanted}
            for member in tar.getmembers():
                name = member.name.removeprefix(prefix)
                if member.name.startswith(prefix) and name in members:
                    members[name].append(member)
            for name in wanted:
                if len(members[name]) != 1 or not members[name][0].isfile():
                    raise RuntimeError("Missing, duplicate or non-regular native member: " + name)
                member = members[name][0]
                if member.size > 512 * 1024 * 1024:
                    raise RuntimeError("Unexpectedly large native artifact: " + name)
                target = stage / name
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as inp, target.open("wb") as out:
                    shutil.copyfileobj(inp, out)
                os.chmod(target, 0o755 if name == "engine/splash" else 0o644)
                hashes[name] = digest(target)
        receipt = {"release": PIN["release"], "commit": commit, "archiveSHA256": asset["sha256"],
                   "files": hashes}
        (stage / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        if destination.exists():
            if any(not (destination / n).is_file() or digest(destination / n) != h for n, h in hashes.items()):
                raise RuntimeError("Existing native candidate differs; preserve it for inspection.")
            if sorted(str(p.relative_to(destination)) for p in destination.rglob("*") if p.is_file()) != sorted([*wanted, "receipt.json"]):
                raise RuntimeError("Existing native candidate contains unexpected files.")
            if json.loads((destination / "receipt.json").read_text()) != receipt:
                raise RuntimeError("Existing native candidate receipt does not match the pin.")
        else:
            # Same filesystem; consumers see all native artifacts together.
            os.rename(stage, destination)
    print(json.dumps({"source": str(source), "native": str(destination), **receipt}, indent=2))


if __name__ == "__main__":
    main()
