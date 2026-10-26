#!/usr/bin/env python3
"""Fetch only pinned tokenizer resources and run native prompt parity checks.

Development tooling only. No model weights, credentials or inference are used.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def valid(path, entry):
    if not path.is_file() or path.stat().st_size != entry["bytes"]:
        return False
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest() == entry["sha256"]


def main():
    pack = json.loads((ROOT / "Sources/SevraSplash/Resources/selected-model.json").read_text())
    target = pack["target"]
    directory = ROOT / ".build/text-fixture" / target["revision"]
    directory.mkdir(parents=True, exist_ok=True)
    for name in ["tokenizer_config.json", "tokenizer.json", "chat_template.jinja"]:
        entry = next(x for x in target["files"] if x["path"] == name)
        destination = directory / name
        if valid(destination, entry):
            continue
        url = "https://huggingface.co/" + target["repository"] + "/resolve/" + target["revision"] + "/" + name
        fd, stage_name = tempfile.mkstemp(prefix=".download-", dir=directory)
        stage = Path(stage_name)
        try:
            with os.fdopen(fd, "wb") as stream:
                request = urllib.request.Request(url, headers={"User-Agent": "Sevra-development-check"})
                with urllib.request.urlopen(request, timeout=60) as response:
                    if response.status != 200 or urllib.parse.urlparse(response.url).scheme != "https":
                        raise RuntimeError("Unexpected tokenizer download response")
                    count = 0
                    while chunk := response.read(1024 * 1024):
                        count += len(chunk)
                        if count > entry["bytes"]:
                            raise RuntimeError("Tokenizer download exceeded the pinned size")
                        stream.write(chunk)
                stream.flush()
                os.fsync(stream.fileno())
            if not valid(stage, entry):
                raise RuntimeError("Tokenizer download does not match the pinned hash")
            os.replace(stage, destination)
        finally:
            stage.unlink(missing_ok=True)
    subprocess.run([str(ROOT / ".build/debug/sevra-splash-text-checks"), str(directory)], check=True)


if __name__ == "__main__":
    main()
