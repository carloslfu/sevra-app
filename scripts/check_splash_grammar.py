#!/usr/bin/env python3
"""Run candidate grammar fixtures without Python inference or model weights."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
receipt = json.loads((ROOT / ".build/llguidance-receipt.json").read_text())
pin = json.loads((ROOT / "integration/llguidance.json").read_text())
library = ROOT / receipt["library"]
if receipt["commit"] != pin["commit"] or hashlib.sha256(library.read_bytes()).hexdigest() != receipt["librarySHA256"]:
    raise RuntimeError("Native grammar candidate changed; rerun scripts/build_guidance.py")
pack = json.loads((ROOT / "Sources/SevraSplash/Resources/selected-model.json").read_text())
model = ROOT / ".build/text-fixture" / pack["target"]["revision"]
subprocess.run([str(ROOT / ".build/debug/sevra-splash-grammar-checks"), str(model), str(library)], check=True)
