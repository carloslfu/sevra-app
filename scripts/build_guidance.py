#!/usr/bin/env python3
"""Build the pinned native grammar candidate. Python and Rust are build tools only."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(*args, cwd=None, env=None):
    subprocess.run(args, cwd=cwd, env=env, check=True)


def main():
    pin = json.loads((ROOT / "integration/llguidance.json").read_text())
    base = ROOT / ".build/upstream"
    base.mkdir(parents=True, exist_ok=True)
    with (base / ".llguidance-build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        source = base / ("llguidance-" + pin["version"])
        if not source.exists():
            stage = Path(tempfile.mkdtemp(prefix=".llguidance-", dir=base))
            try:
                run("git", "init", "--quiet", str(stage))
                run("git", "remote", "add", "origin", pin["repository"], cwd=stage)
                run("git", "fetch", "--depth", "1", "origin", pin["commit"], cwd=stage)
                run("git", "checkout", "--detach", "FETCH_HEAD", cwd=stage)
                os.rename(stage, source)
            finally:
                if stage.exists():
                    shutil.rmtree(stage)
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
        if revision != pin["commit"] or subprocess.check_output(["git", "status", "--porcelain"], cwd=source):
            raise RuntimeError("Grammar source differs from its pin; preserve it and inspect changes")
        for path, expected in [
            (source / "Cargo.lock", pin["cargoLockSHA256"]),
            (source / "parser/llguidance.h", pin["headerSHA256"]),
            (ROOT / "Sources/CLLGuidance/include/llguidance.h", pin["headerSHA256"]),
            (ROOT / "Sources/SevraSplashGrammar/Resources/json-slices.json", pin["jsonSlicesSHA256"]),
        ]:
            if digest(path) != expected:
                raise RuntimeError("Grammar source/resource identity changed: " + path.name)
        env = os.environ.copy()
        # The dylib is opened by its trusted installed path. Give it a portable
        # identity too; never encode the contributor's build folder as LC_ID_DYLIB.
        env["RUSTFLAGS"] = "-C link-arg=-Wl,-install_name,@rpath/libllguidance.dylib"
        run("cargo", "+" + pin["rustToolchain"], "build", "--release", "--locked", "-p", "llguidance", cwd=source, env=env)
        library = source / "target/release/libllguidance.dylib"
        if not library.is_file():
            raise RuntimeError("The native macOS grammar library was not built")
        receipt = {"schemaVersion": 1, "commit": revision, "rustToolchain": pin["rustToolchain"],
                   "cargoLockSHA256": pin["cargoLockSHA256"], "librarySHA256": digest(library),
                   "libraryBytes": library.stat().st_size, "library": str(library.relative_to(ROOT)),
                   "shipped": False}
        destination = ROOT / ".build/llguidance-receipt.json"
        destination.write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps(receipt))


if __name__ == "__main__":
    main()
