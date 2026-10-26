"""Identity checks shared by development-only reference fixture generators."""
import hashlib
import json
from pathlib import Path
import subprocess


def verify(root: Path, model: Path):
    pin = json.loads((root / "integration/splash.json").read_text())
    source = root / ".build/upstream" / ("splash-" + pin["release"])
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
    if revision != pin["commit"] or subprocess.check_output(["git", "status", "--porcelain"], cwd=source):
        raise RuntimeError("Reference source differs from the integration pin")
    pack = json.loads((root / "Sources/SevraSplash/Resources/selected-model.json").read_text())
    for name in ["tokenizer.json", "tokenizer_config.json", "chat_template.jinja"]:
        expected = next(x for x in pack["target"]["files"] if x["path"] == name)
        path = model / name
        if path.stat().st_size != expected["bytes"] or hashlib.sha256(path.read_bytes()).hexdigest() != expected["sha256"]:
            raise RuntimeError("Reference tokenizer does not match selected model: " + name)
    return source
